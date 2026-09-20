---
written_against:
  date: 2026-08-29
  verified_from: "each project's LICENSE file on its default branch, plus the vendor's own feature and pricing docs"
  state: >
    Vault 2.0.4 (BUSL-1.1, licensor IBM Corp) · OpenBao 2.6.2 (MPL-2.0, Linux Foundation) ·
    step-ca 0.30.2 (Apache-2.0) · SPIRE 1.15.3 (Apache-2.0, CNCF graduated) ·
    cert-manager 1.21.1 + trust-manager + csi-driver-spiffe (Apache-2.0, CNCF graduated) ·
    Linkerd source Apache-2.0, stable artifacts only through Buoyant Enterprise (free below
    50 employees) · Istio ambient GA since 1.24, Apache-2.0 · CFSSL BSD-2-Clause ·
    Caddy Apache-2.0 · Traefik Proxy MIT · EJBCA Community LGPL-2.1
---

`written_against` names the licence and version state this rubric was checked against; a licence
line that contradicts it means this file is stale and needs re-verification against the project's
`LICENSE` file, not that the solution drifted.

# Internal PKI and mTLS — decision rubric

`security.md` decides **whether** service-to-service calls are authenticated with mTLS at all —
one of three answers there, beside client-credentials tokens and segmentation alone. This file
starts after that decision: who issues certificates, how they rotate, how trust bundles reach
every process, what revocation means, and what each option costs to run and to license. Where
secrets are stored is `operations.md` (Vault and OpenBao appear there as secret stores; here only
as certificate authorities); where TLS terminates at the edge is `deployment.md`.

mTLS is roughly ten percent handshake and ninety percent certificate lifecycle. Judge every
option against these six, not against its handshake:

- **Issuance** — what proves a workload may hold identity X: a bootstrap secret, a platform
  identity, or an attestation of how the process runs.
- **TTL and rotation** — the short TTL is the whole benefit and the whole risk: a day-long
  certificate must be renewed *and picked up* with no human involved.
- **Reload without restart** — most servers read the certificate once at start-up, so renewal that
  needs a restart turns rotation into a deploy, and rotation then stops happening.
- **Trust-bundle distribution** — every peer needs the CA bundle, updatable *before* the CA
  rotates, or a root rotation is a full outage.
- **Revocation** — CRL and OCSP are a distribution problem of their own; short TTLs plus refusing
  to reissue ("passive revocation") is what most estates operate, legitimately, once the
  compromise window is a `QS-` row.
- **Clock skew** — hosts minutes apart produce not-yet-valid errors that look like network faults,
  so NTP everywhere is part of the design.

Licence is a first-class column because it decides what may be run at all. `licensing.md` owns
what each licence family permits; per option below, state the licence it ships under today, what
free commercial self-hosting covers, and the caveat.

## Choosing by driver

| Driver in the recorded scenarios / constraints | Candidates to put on the table |
|---|---|
| A contract or regulator names encryption and auditable issuance between internal components | Vault/OpenBao PKI · step-ca · EJBCA when X.509 profile management itself is audited |
| A zero-trust mandate: every call authenticated, no implicit network trust | SPIFFE/SPIRE · a mesh, if the platform is Kubernetes |
| East-west traffic crosses hosts, networks or clouds you do not fully control | any issuing CA with short TTLs and automated renewal |
| Kubernetes is already the platform | cert-manager (+ trust-manager), possibly fronting one of the CAs; a mesh already running for retries or policy brings its own mTLS, and a second CA buys nothing |
| Secrets already live in Vault or OpenBao | the same instance's PKI engine, before any new component |
| Compose on one or a few VMs, one small team | step-ca or OpenBao issuing short-lived certs · a scripted CA with a named owner |
| Only OSI-approved licences may enter the build or the deploy | OpenBao · step-ca · SPIRE · cert-manager — this excludes Vault |
| No clause, no threat model, only "internal traffic should be encrypted" | segmentation plus client-credentials tokens per `security.md`; revisit when a driver is written down |

## HashiCorp Vault — PKI secrets engine

**Licence** BUSL 1.1, licensor IBM Corp since the acquisition. **Not** OSI-approved open source.
Its Additional Use Grant permits production use — a company self-hosting Vault to issue
certificates for its own products is squarely inside it; what it forbids is offering Vault itself
to third parties, hosted or embedded, in competition with IBM's paid versions. Each release turns
MPL 2.0 four years after publication. Free is real for the ordinary case; the caveat is
procurement rules that reject non-OSI licences outright, and terms that are IBM's to change.

- **Use when** Vault is already operated for secrets (`operations.md`) and the same policy model,
  audit device and identity system should govern certificates too.
- **Pros** issuance is an API call against a role pinning allowed domains, key types and maximum
  TTL; ACME (RFC 8555) is in Community, so standard clients renew unattended; root and intermediate
  lifecycle, CRL generation and tidy jobs are built in; every issuance is audited.
- **Cons** Vault becomes a hard dependency of every start-up and renewal, so it needs HA,
  auto-unseal, snapshots and a restore drill; EST, SCEP, CMPv2 and the external issuance-policy
  service (CIEPS) are Enterprise-only, so a regulated enrolment protocol means a paid licence.
- **Typical mistakes** a role with no `max_ttl`, so a service quietly issues year-long certificates;
  the bootstrap credential that fetches them never rotated, reinstating the shared secret mTLS was
  meant to remove; running Vault solely for PKI over four containers.

## OpenBao — the MPL-2.0 fork

**Licence** MPL 2.0, OSI-approved, weak copyleft that applies per file and does not reach your
application. Governed under the Linux Foundation rather than one vendor. Free for commercial
self-hosting, no user cap, no enterprise edition holding features back. The caveat is ecosystem
size, not terms: fewer contributors and fewer integrations that name it explicitly.

- **Use when** the Vault design is right and the BUSL licence is the blocker, or when
  vendor-independent governance is itself a constraint.
- **Pros** PKI parity with Vault Community is effectively there — same API paths (cert-manager's
  Vault issuer works against it unchanged), ACME, root and intermediate management, CRL, rotation
  primitives; CEL-based issuance policies exist here and not in Vault; migration from Vault
  Community is a supported path, not a rewrite.
- **Cons** the same operational weight as Vault — HA, unseal, snapshots, upgrades; what is missing
  was never in Vault Community either (EST, SCEP, CMPv2, CIEPS), so switching solves no
  requirement for those; commercial support exists, from a short list of vendors.
- **Typical mistakes** following Vault documentation version-for-version as the two diverge;
  assuming a tool that says "Vault" is tested against OpenBao — most work, some do not, so verify;
  treating the licence win as a reason to skip the restore drill.

## smallstep step-ca

**Licence** Apache-2.0 for `step-ca` and the `step` CLI. Free for commercial self-hosting,
production included, no employee or endpoint cap. The caveats are feature-shaped: Smallstep's own
list of what the open-source CA does not do is a single issuing intermediate, limited revocation
(a minimal CRL server, no OCSP responder), no Certificate Transparency and no ACME external
account binding — those live in the paid Step CA Pro and the hosted Certificate Manager.

- **Use when** you want a private CA and nothing else — ACME issuance, short lifetimes, one Go
  binary. The strongest fit for a Compose estate with no Vault and no wish for one.
- **Pros** an ACME server on your own infrastructure, so any ACME client (Caddy, Traefik, certbot,
  `step ca renew`) renews unattended; provisioners (JWK, OIDC, X5C, cloud instance identity) give
  several honest ways to prove who may enrol; templates constrain the SANs and key usages a
  certificate may carry.
- **Cons** the default embedded database has no concurrency, so HA means MySQL or PostgreSQL
  behind an active/standby or load-balanced pair; revocation is passive by design, which is fine
  until a requirement names OCSP; the CA is a single point whose loss stops all renewal.
- **Typical mistakes** running it on the same host as everything it issues for, so one host loss
  takes the CA and the renewals with it; the root key left on the running server instead of
  offline; provisioner passwords in the Compose file; long TTLs "to avoid churn", which discards
  the reason for an online CA.

## SPIFFE / SPIRE

**Licence** Apache-2.0, CNCF graduated. Free for commercial self-hosting with no caveat — this
is the cleanest licence position in the list.

- **Use when** identity must be *attested* rather than configured: the workload proves what it is
  (which image, node, cloud instance) and receives an SVID for it, with no bootstrap secret
  anywhere. Worth its cost when a zero-trust mandate is written down, or when one trust domain
  must span Kubernetes, VMs and Compose hosts.
- **Pros** rotation is the design, not a feature — the Workload API streams renewed SVIDs and the
  current trust bundle to the process, so trust distribution and root rotation stop being
  deployment problems; identity is portable across platforms, and a mesh's identity layer is built
  on it, so adopting a mesh later is not a migration.
- **Cons** a server (with its own datastore and HA) plus an agent on every host, and registration
  entries become configuration with a lifecycle of their own; workloads must consume the Workload
  API — an SDK, a `spiffe-helper` sidecar writing certificates to a volume and signalling the
  process, or a proxy terminating for them. The Docker workload attestor and nested topologies do
  work on Compose, but that is two more components for four services.
- **Typical mistakes** taking the identity model and then writing SVIDs to disk with a renewal
  nobody wired to a reload, which is restart-driven rotation again; registration entries
  maintained by hand until nobody knows which are live; treating the trust domain name as
  cosmetic — it is in every identity, and renaming it is a migration.

## cert-manager

**Licence** Apache-2.0, CNCF graduated. Free for commercial self-hosting; `trust-manager` and
`csi-driver-spiffe` are the same project and licence.

- **Use when** the platform is Kubernetes. It is the default answer there: `Certificate` resources
  are reconciled, renewal happens before expiry, and the issuer can be self-signed, a CA key in a
  Secret, ACME, or Vault/OpenBao/step-ca behind it.
- **Pros** one mechanism for public and internal certificates; `trust-manager` distributes CA
  bundles as ConfigMaps, so root rotation is a controlled roll rather than an outage;
  `csi-driver-spiffe` mounts short-lived per-pod SPIFFE identities whose key never touches a
  Secret; it fronts the CAs above, so the issuer decision stays reversible.
- **Cons** Kubernetes-only — no Compose or VM story, and pretending otherwise is how this option
  gets mis-sold; a renewed Secret does not restart the pod, so without a file watch or a reloader
  the rotation is invisible to the process; a CA key in a Secret is only as safe as cluster RBAC.
- **Typical mistakes** a self-signed issuer per namespace, so there is no common trust anchor and
  every peer pair needs bespoke configuration; a CA bundle mounted from a ConfigMap nobody
  updates; no alert on `Certificate` resources stuck not-ready, so expiry is the first symptom.

## Service-mesh built-in mTLS

**Licence** Istio is Apache-2.0 (CNCF graduated), ambient mode GA since 1.24; ztunnel obtains
certificates from istiod for every workload on its node. Linkerd's *source* is Apache-2.0, but
since February 2024 the project publishes only edge releases — weekly builds with no upgrade
guarantees. Stable, semver-guaranteed artifacts come from Buoyant Enterprise for Linkerd, free
with a licence key only for organisations under 50 employees, paid above that. Say that split out
loud: the free path at any company size is edge builds, an operational decision, not a footnote.

- **Use when** the platform is Kubernetes and at least two of {mTLS, traffic policy, retries and
  timeouts, per-call telemetry} are recorded requirements — the bar `security.md` sets. Then mTLS
  arrives as a side effect of something you were buying anyway.
- **Pros** transparent to the application: no library, no certificate files, no reload logic;
  certificates are short-lived and rotated by the control plane; policy ("mTLS required in this
  namespace") is declarative and auditable; ambient removes the per-pod sidecar cost.
- **Cons** a mesh is a Kubernetes commitment and a platform to upgrade, debug and keep
  version-compatible with the cluster; ambient does not cover VMs, so a mixed estate still needs
  sidecars; the mesh's own CA and root rotation become yours; failure modes move into a proxy the
  application team cannot read.
- **Typical mistakes** adopting a mesh purely for mTLS, the most expensive way to get
  certificates; permissive mode left on forever, so plaintext still works and nobody notices;
  running Linkerd edge builds in production with no plan for upgrade breakage, or meeting the
  50-employee threshold after the company has grown past it.

## The minimal CA: scripts, CFSSL, or a proxy's internal CA

**Licence** OpenSSL is Apache-2.0; CFSSL is BSD-2-Clause (Cloudflare, effectively maintenance
mode); Caddy is Apache-2.0; Traefik Proxy is MIT (Traefik Enterprise is not). All free for
commercial self-hosting. EJBCA Community is LGPL-2.1 — the heavyweight option when audited X.509
profile management is itself the requirement, and a Java application server's worth of weight.

- **Use when** the estate is a handful of containers on one or two hosts, one person owns it, and
  the requirement is "internal traffic is encrypted and the peers are known". Caddy's internal CA
  issues and renews automatically, and `acme_server` turns one Caddy into an ACME CA for other
  hosts; Traefik verifies client certificates against a CA bundle you supply but issues nothing.
- **Pros** nothing new to operate; the CA is a file and a script, reviewable in an afternoon;
  sufficient at this size, and saying so beats selling Vault to a four-service system.
- **Cons** everything the tools above automate is yours — renewal, reload, trust distribution,
  revocation; Caddy's local CA is trusted only where its root is installed, and distributing that
  root is your job.
- **It stops being honest** when any of these is true: a certificate has expired in production; the
  CA key sits on one disk with no backup and no rotation plan; more than one person needs to issue;
  an auditor asks who issued a given certificate and when. Record those as an `R-` row now, so the
  move to step-ca or OpenBao happens on the trigger rather than after the outage.
- **Typical mistakes** a ten-year CA and ten-year leaves, because rotation was never automated; the
  generation script living on a laptop; one key copied into staging and production; no record of
  which service holds which certificate, so revocation is guesswork.

## Compose scale — the honest version

One or a few VMs running Docker Compose, the assumed baseline in `containers.md`. No mesh, no
Kubernetes, no control plane.

- **Terminate at one reverse proxy per host** (Caddy, Traefik, nginx) that verifies client
  certificates; services behind it on a private Compose network stay plaintext or server-only TLS.
  One certificate lifecycle per host instead of one per service.
- **Issue short-lived certificates from step-ca or OpenBao** over ACME or their own renewal
  clients, with the CA on a host it does not itself serve. Renewal is a sidecar or a systemd timer
  per host, and it must be monitored — a silent renewal failure is invisible until expiry.
- **Distribute the trust bundle as a mounted file** from one place, deployed as configuration, not
  baked into images where a root rotation means rebuilding everything. Certificates carried in env
  vars break first, on size and on newlines.
- **Expect restart-on-renewal.** Most servers read certificates once at start-up, so the renewal
  hook signals or restarts the container. Decide deliberately whether a brief drop per renewal is
  acceptable; if it is not, that is the argument for a proxy that reloads live, or for SPIRE.
- **Keep revocation passive** — short TTLs plus removing the workload's ability to renew — and
  write the compromise window into `04-quality-scenarios.md` as a number. That number answers "how
  do you revoke" better than an OCSP responder nobody polls.
- **With no driver, do not recommend mTLS at all**: a private network with no published ports plus
  client-credentials tokens is less machinery and fewer failure modes — `security.md`'s
  service-to-service table owns that fork. Record the trigger that would change it as an `R-` row.

## Payoff table

| Option | Free for commercial self-host | Issuance automation | Rotation without restart | Revocation | Compose fit | Kubernetes fit | Ops weight |
|---|---|---|---|---|---|---|---|
| Vault PKI | yes, BUSL — not OSI, IBM terms | API + ACME | client-dependent | CRL; enterprise protocols paid | workable | good (cert-manager issuer) | high |
| OpenBao PKI | yes, MPL-2.0 | API + ACME | client-dependent | CRL | workable | good (Vault issuer works) | high |
| step-ca | yes, Apache-2.0; OCSP is paid | ACME + provisioners | client-dependent | CRL, passive by design | strong | good (ACME issuer) | low–medium |
| SPIFFE/SPIRE | yes, Apache-2.0 | attestation-based | yes, via Workload API | short TTL, entry removal | possible, heavy for the size | strong | medium–high |
| cert-manager | yes, Apache-2.0 | CRDs + issuers | needs a reloader | delegated to the issuer | none (K8s only) | native | low on K8s |
| Istio ambient | yes, Apache-2.0 | automatic | yes | short TTL, control plane | none | strong, K8s-only | high |
| Linkerd | edge builds yes; stable = BEL, free under 50 employees | automatic | yes | short TTL, control plane | none | strong, K8s-only | medium–high |
| Minimal CA (scripts, CFSSL, Caddy) | yes, Apache-2.0 / BSD-2 / MIT | scripted or Caddy ACME | no | none, or manual | strong at small size | poor | lowest, until it is not |

## When the evidence is thin

Put no CA on the table: recommend a private network with no public route plus client-credentials
tokens, and name the trigger that would justify certificates. If mTLS is already decided, the
reversible pair is step-ca on Compose and cert-manager on Kubernetes — both Apache-2.0, both
leaving SPIRE and mesh open.

## Recording the choice

1. Put the options to the human with the licence in the first line of each — name, whether it is
   OSI-approved, what free commercial self-hosting covers, the caveat. For Vault, say plainly that
   BUSL is source-available rather than open source and that the terms are IBM's.
2. Give one recommendation with the driver behind it, and the operational cost in the same
   sentence as the security benefit. The human decides.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected options as its alternatives
   with the reason each lost — a licence is a legitimate reason — and reference it from
   `03-containers.md` beside the boundary it protects and from `06-deployment.md`, where the CA
   and the trust bundle live.
4. Every number becomes a `QS-` row: certificate TTL, renewal lead time, the compromise window
   passive revocation leaves, tolerated clock skew, time to rotate the CA root.
5. Unautomated renewal, a CA key with no backup or rotation plan, and a licence a future
   procurement review may reject are `R-` rows in `07-risks.md` with an owner. Anything left open
   is a `TODO(question)` in the affected document, per `templates.md`.
