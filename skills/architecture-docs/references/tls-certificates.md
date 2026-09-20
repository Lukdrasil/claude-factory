# TLS certificates — issuance, rotation, revocation

Load this whenever anything serves HTTPS, a certificate is being requested or renewed, mTLS or an
internal PKI comes up, or anyone proposes "just buy a cert and set a calendar reminder". The
question this file settles is narrow and unglamorous: who issues, rotates and revokes your
certificates — public and internal — and what happens when nobody is watching. `edge-proxy.md`
decides which component terminates TLS and therefore which certificate store matters;
`mtls-pki.md` owns the internal-CA project once mutual TLS is the answer rather than a passing
mention. This file covers the issuance and renewal machinery on both sides of that line.

Outputs land in `06-deployment.md` (where the cipher ends, who renews the certificate, what the
human steps at renewal are — ideally none), in `02-constraints.md` when compliance dictates a CA,
and in an ADR per `templates.md`. Options reach the human with consequences plus your
recommendation, per `approaches.md`.

The safe default is fully automated ACME issuance with zero human steps: Caddy or Traefik doing it
built in, cert-manager on Kubernetes, or the platform's managed certificates on PaaS and cloud load
balancers. Manual certificate handling is now actively dying. CA/Browser Forum ballot SC-081v3 cuts
public certificate lifetimes to 200 days in March 2026, 100 days in March 2027 and 47 days in March
2029, and Let's Encrypt is already shortening its defaults from 90 toward 45 days — any process
with a human in the loop will miss a renewal. Treat a certificate expiry outage as a process
failure, not bad luck.

certbot-on-cron is acceptable, but understand what it is: a strictly worse Caddy. You own the cron
job, the reload hook and the monitoring, and each of those is a thing that fails quietly. Corporate
PKI is for internal trust — mTLS, service identity — and for compliance-mandated environments; it
is never for public endpoints, and it still needs automation, whether that is ACME against the
internal CA or cert-manager pointed at a CA or Vault issuer. Whatever issues the certificate must
also be what rotates it. Split responsibility is where outages live.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Public HTTPS endpoint, any platform | ACME automation (Let's Encrypt / ZeroSSL) — free, and immune to the shrinking-lifetime treadmill |
| Using Caddy or Traefik as edge | built-in ACME — the decision dissolves; just persist the certificate storage volume |
| Kubernetes | cert-manager with an ACME `ClusterIssuer`; certificates as declarative resources |
| Cloud LB or PaaS terminates TLS | platform-managed certificates — never fight the platform by importing your own |
| Wildcard certificate, or servers not reachable on port 80/443 | DNS-01 challenge — requires API access to your DNS provider; pick a provider with good ACME plugin support |
| mTLS, internal service identity, or an air-gapped network | an internal CA (corporate PKI, step-ca, Vault) — public ACME cannot issue client certificates for you |
| Compliance demands EV/OV or a specific commercial CA | a commercial CA, but still via ACME where offered — the lifetime clock ticks for paid certificates too |
| Certificates on many hosts issued from one place | watch Let's Encrypt rate limits (50 certificates per registered domain per week; renewals exempt) and persist ACME state |

## ACME automated (Let's Encrypt with certbot / acme.sh)

- **License** certbot Apache-2.0; acme.sh GPL-3.0; the certificates themselves are free.
- **Use when** the edge is nginx, HAProxy, IIS or any other proxy without native ACME, and you
  accept owning the renewal plumbing.
- **Pros** free, scriptable and works everywhere; a huge ecosystem of DNS plugins for DNS-01 and
  wildcards; well-understood failure modes.
- **Cons** you own the cron job or systemd timer, the deploy hook and the reload — three things
  that silently break; a renewal that succeeds without a server reload still serves the old
  certificate; nobody notices the breakage until expiry, or until monitoring exists.
- **Typical mistakes** no `--deploy-hook` to reload the proxy after renewal; testing against the
  production ACME endpoint and burning rate limits instead of using `--staging`; no expiry
  monitoring, so the renewal cron died months ago and nothing said so.

## Caddy / Traefik built-in ACME

- **License** Caddy Apache-2.0; Traefik MIT.
- **Use when** you control the edge proxy and it is one of these — the best default for VM and
  Compose deployments.
- **Pros** zero-config issuance, renewal and reload in one process, so there is nothing to forget;
  OCSP stapling and staggered renewal handled automatically; already renewing well within the
  47-day future.
- **Cons** certificate storage lives inside the proxy, so `/data` or `acme.json` needs backing up;
  multi-instance setups need shared storage or a certificate-distribution plan; DNS-01 needs a
  provider plugin or module.
- **Typical mistakes** ephemeral container storage, so certificates reissue on every deploy until
  the rate limit stops them; two proxy instances racing each other for the same hostname's
  certificate; blocking outbound 443 or inbound 80 in the firewall and then wondering why issuance
  fails.

## cert-manager on Kubernetes

- **License** Apache-2.0 (CNCF).
- **Use when** you are on Kubernetes, full stop. It is also the bridge to internal PKI, via the CA,
  Vault and step issuers.
- **Pros** certificates become declarative resources with a status you can alert on; one tool
  covers both public ACME and internal CA issuance; it auto-renews and updates Secrets, and ingress
  annotations make it near-invisible.
- **Cons** another controller to run and upgrade; webhook and CRD upgrade hiccups are a known
  operational papercut; useless outside Kubernetes — do not contort non-k8s workloads to use it.
- **Typical mistakes** deploying it to a Compose or VM stack "because we use it at work", when it
  requires Kubernetes; using the production `ClusterIssuer` for experiments and hitting rate
  limits; not alerting on `Certificate Ready=False`, and so discovering the problem at expiry.

## Cloud-managed certificates (ACM / App Service / Cloud Run class)

- **License** proprietary managed service; certificates are typically free with the platform.
- **Use when** TLS terminates at a cloud load balancer or PaaS edge you have already chosen.
- **Pros** issuance, rotation and revocation are fully handled — the strongest "nobody gets paged"
  option; insulated from the 47-day change, because the provider absorbs it; integrates with the
  platform's DNS for validation.
- **Cons** certificates usually cannot leave the platform, since there is no private-key export;
  lock-in, because moving edge providers means redoing the certificate plumbing; validation records
  left dangling cause silent renewal failures.
- **Typical mistakes** importing a manually bought certificate into the platform and inheriting its
  manual renewal; deleting the DNS validation CNAME during a zone cleanup; assuming platform
  certificates cover internal service-to-service TLS, which they do not.

## Corporate PKI / manually issued certificates

- **License** not applicable — an internal or commercial CA.
- **Use when** internal trust, mTLS, service identity, air-gapped or compliance-mandated
  environments are the case — not public endpoints.
- **Pros** full control of the trust chain and of lifetimes for internal traffic; the only option
  for client certificates and mTLS at organisation scale; you can run ACME internally (step-ca,
  Vault, AD CS with ACME) to get automation back.
- **Cons** you now run a CA, with a root key ceremony, CRL/OCSP and HSM questions; manual issuance
  means manual expiry — the classic Saturday-night outage; distributing the internal root to every
  client and device is a project of its own.
- **Typical mistakes** using internal-CA certificates on a public endpoint, where browsers reject
  them and customers leave; spreadsheet-plus-calendar renewal tracking, which 47-day lifetimes make
  arithmetically impossible; 10-year internal certificates passed off as "automation", leaving key
  compromise with no rotation path.

## Deployment platform → who terminates TLS → who rotates certificates

| Platform | TLS terminates at | Certificates rotated by | Human steps at renewal |
|---|---|---|---|
| Single VM + Caddy | Caddy | Caddy built-in ACME | none |
| Single VM + nginx | nginx | certbot timer plus deploy hook | none if the hook and monitoring exist; otherwise an outage timer |
| Docker Compose | Caddy/Traefik container | built-in ACME (persist `/data` or `acme.json`) | none |
| Kubernetes | ingress / Gateway | cert-manager | none; alert on `Certificate Ready=False` |
| Cloud LB (ALB / Front Door) | the cloud LB | the cloud provider (ACM class) | none; keep the validation DNS records alive |
| PaaS | the platform edge | the platform | none |
| IIS on Windows | IIS | win-acme scheduled task, or manual (avoid) | none with win-acme; a quarterly fire drill if manual |
| Internal mTLS mesh | sidecar / service | mesh CA, step-ca, Vault, or a cert-manager CA issuer | none if automated; do not do this manually |

## Public certificate maximum lifetime trajectory (CA/B Forum SC-081v3)

| Effective date | Max validity | Practical consequence |
|---|---|---|
| Today (pre-2026-03-15) | 398 days | annual manual renewal still barely survivable |
| 2026-03-15 | 200 days | twice-yearly manual renewal; a calendar-based process starts fraying |
| 2027-03-15 | 100 days | quarterly renewals; manual handling now negligent |
| 2029-03-15 | 47 days | automation mandatory; DCV reuse also drops toward 10 days |

## What holds whatever you pick

- If a human touches certificate renewal, you have scheduled an outage — 47-day lifetimes just
  moved the date up.
- Whatever issues the certificate must also rotate it and reload the server; split responsibility
  is where expiries live.
- Public endpoints get publicly trusted ACME certificates; internal CAs are for internal trust and
  mTLS only.
- cert-manager without Kubernetes is a category error; Kubernetes without cert-manager is a
  manual-renewal trap.
- Always test ACME against the staging endpoint first — production rate limits (50 per domain per
  week) do not forgive experiments.
- Persist your ACME storage; ephemeral certificate state plus container restarts equals rate-limit
  lockout.
- Renewals are exempt from Let's Encrypt rate limits, so shrinking lifetimes cost you nothing once
  you are automated.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend whatever issuance the chosen edge already
does for itself with no human step — the proxy's built-in ACME, the platform's managed
certificates, or cert-manager on Kubernetes — with the certificate storage persisted and an expiry
alert wired regardless. Name the trigger that would change it — a compliance mandate for a specific
CA, a wildcard requirement that forces DNS-01, the first internal mTLS requirement — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: who issues, what rotates,
   what reloads, and whether any human step remains at renewal.
2. State for each what it costs per month and in whose hours, what it locks in, and what moving off
   it later costs — including whether the private key can leave the platform at all.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `06-deployment.md`, which records where the cipher
   ends and who renews the certificate.
4. An unautomated renewal, a certificate store nobody backs up, a missing expiry alert and an
   internal root nobody has planned to distribute are rows in `07-risks.md`, not sentences in the
   deployment document. Anything the human leaves open is a `TODO(question)` per `templates.md`.
