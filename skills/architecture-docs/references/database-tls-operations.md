---
written_against: "web research 2026-08"
---

`written_against` names the product and version state this rubric was checked against — which
engines reload certificates live and by what mechanism, and which managed providers rotate CAs on
their own schedule. A vendor page that contradicts it means this file is stale and needs
re-research, not that the solution drifted.

# Database TLS — who issues the certificates, whether they rotate live, and whether clients verify

Load this when TLS is being enabled on a database, when cert-manager or ACME certificates for a
datastore are on the table, when `sslmode` and verification settings are being decided, when a
cloud CA bundle or a forced CA rotation appears, or when mTLS to the database is proposed.
`database-products.md` has settled which engine this applies to and whether it is managed;
`mtls-pki.md` owns the general question of who issues, rotates, distributes and revokes
certificates across the system, and this file is its database-shaped corner. `edge-proxy.md` owns
where TLS terminates at the edge; `operations.md` owns the monitoring and secrets storage that any
answer here depends on.

Outputs land in `06-deployment.md` (the issuer, the cert lifetime, the reload trigger, the client
trust bundle), in `02-constraints.md` when compliance mandates encryption in transit, and in an ADR
per `templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

Database TLS fails differently from web TLS. There is no browser warning — just every client
connection dying at once when a certificate expires, which makes a database cert expiry a
full-system outage. So the first decision is whether you need it at all: on a genuinely private
network with no compliance driver, plaintext plus network policy is a defensible choice, provided
it is written down. Compliance, or any shared network, makes TLS mandatory.

If you do enable it, the deciding question is rotation. PostgreSQL (via `pg_reload_conf` since
v10), MySQL (`ALTER INSTANCE RELOAD TLS`, 8.0.16+), MongoDB (`rotateCertificates`, 4.4+) and
Redis/Valkey (`CONFIG SET tls-cert-file`) all reload server certificates without a restart, which
is what makes cert-manager's short-lived auto-renewed certificates safe. SQL Server has no reload
at all: a certificate change means a service restart. On Kubernetes, cert-manager issuing
short-lived certificates into a Secret plus the engine's reload hook is the correct default; manual
annual certificates with a calendar reminder is the pattern that produces the outage.

Managed databases invert the problem. The platform owns the server certificate, and your only job
is shipping the provider CA bundle to every client and honouring forced CA rotations — the
rds-ca-2019 expiry broke exactly the clients that ignored the notices. And finally, encryption
without verification is theatre: `sslmode=require` does not check the certificate, so clients must
run `verify-full` with the right CA, or the TLS spend bought nothing against MITM.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Database and apps share a private VPC or network, with no compliance driver | no-TLS is defensible; document it as a decision, not an accident |
| Compliance includes audit or PCI-class requirements, or a zero-trust policy | TLS mandatory; aim for auto-rotated or platform-managed |
| A managed database | platform-managed: your work is the client CA bundle and the rotation notices, not issuance |
| Kubernetes with cert-manager already installed | auto-rotated: a cert-manager `Certificate` plus an engine reload hook |
| The engine is self-hosted SQL Server | a cert change requires a restart — one-year certs with planned windows, not 90-day ACME |
| Ops capacity is none and someone proposes manual certs | refuse: manual database certs with nobody watching expiry is a scheduled outage |
| mTLS or client-cert auth to the database | only with automated issuance on both ends; manual mTLS doubles the expiry surface |
| Clients connect with `sslmode=require` or trust-all settings | fix verification (`verify-full` plus the CA) before calling the link secured |

## No-TLS on a private network

- **Use when** the database is reachable only inside a private network — a VPC, a NetworkPolicy,
  WireGuard — no compliance requirement names encryption in transit, and the team writes the
  decision down.
- **Pros** zero certificate operations: nothing expires, nothing rotates, no 3 a.m. handshake
  failures; and no TLS overhead on connection-heavy workloads, with the simplest debugging story.
- **Cons** one compliance question later forces a retrofit under audit pressure; anyone who reaches
  the network segment reads credentials and data off the wire; and it is indefensible on shared
  clusters, peered VPCs, or anything multi-tenant.
- **Typical mistakes** being "private" via security-group defaults rather than deliberate topology,
  and then peering the VPC; not documenting it, so the next audit treats it as negligence instead
  of a decision.

## TLS with manual certs

- **Use when** TLS is required but issuance is manual — a corporate PKI ticket, an `openssl`
  one-off — with long-lived certificates. Acceptable only as a transition state.
- **Pros** meets the encryption-in-transit checkbox with no new infrastructure; and works with
  corporate PKI processes that cannot be automated yet.
- **Cons** rare rotation means nobody remembers how, so the renewal is performed from scratch,
  wrong, at expiry; a database cert expiry is a total outage, with every client failing
  simultaneously; and humans distribute private keys, which is how keys end up in wikis.
- **Typical mistakes** no expiry monitoring, so the outage *is* the monitoring; issuing without the
  SANs clients actually connect by, discovered at `verify-full` rollout; copying the same key and
  certificate to every replica and never rotating after an admin leaves.

## TLS auto-rotated (cert-manager plus engine reload)

- **Use when** the database is self-hosted on Kubernetes or a VM with automation available:
  cert-manager (or ACME, or Vault) issues short-lived certificates and the engine reloads them
  without restarting. This is the correct target state for self-hosted TLS.
- **Pros** rotation happens by machinery and is rehearsed continuously, which makes expiry outages
  near-impossible; short-lived certificates shrink the key-compromise blast radius; Postgres, MySQL,
  MongoDB and Redis/Valkey all reload live with no connection drops; and operators of the
  CloudNativePG class integrate cert-manager natively.
- **Cons** it needs the reload plumbing — a Secret-change trigger calling the engine's reload
  command; SQL Server breaks the model, since a restart is required and short-lived certificates
  therefore mean scheduled restarts; and debugging adds a layer, because a failure could be the
  database, the certificate, cert-manager or the CA.
- **Typical mistakes** cert-manager renews the Secret but nothing tells the database to reload, so
  the engine serves the old certificate until it expires; rotating the CA rather than just the leaf
  without pre-distributing the new CA to client trust stores.

## Platform-managed (cloud)

- **Use when** the database is managed. The platform issues and rotates the server certificate; you
  configure the clients.
- **Pros** server-side issuance, renewal and rotation are entirely the provider's problem; modern
  CAs auto-rotate server certificates without customer action; and combined old-plus-new CA bundles
  allow zero-downtime client transitions when done in the right order.
- **Cons** forced CA rotations arrive on the provider's schedule, and clients with stale trust
  stores fail; every client, sidecar, lambda and CI job must carry the provider CA bundle, and the
  long tail is where it breaks; and certificate pinning or custom CAs are generally impossible.
- **Typical mistakes** baking a CA bundle into a container image years ago and never updating it;
  rotating the instance's CA before updating client trust stores, when the correct order is clients
  first with a combined bundle; `sslmode=require` against a managed database believed to be
  MITM-proof, when without `verify-full` and the bundle it is not; ignoring provider deprecation
  emails because "the database is managed".

## TLS cert reload per product

| Product | Reload without restart? | Exact mechanism | Works with short-lived certs? | Notes |
|---|---|---|---|---|
| PostgreSQL | yes (since v10) | `SIGHUP` / `SELECT pg_reload_conf()` re-reads `ssl_cert_file`, `ssl_key_file`, `ssl_ca_file` | yes — pair renewal with a reload trigger | existing sessions keep the old SSL context; a broken new cert fails the reload and the old cert stays active |
| MySQL 8.0.16+ | yes | `ALTER INSTANCE RELOAD TLS` | yes — replace file contents, run the statement | new connections get the new cert; MariaDB has `FLUSH SSL` |
| SQL Server | no | none — the cert is bound via Configuration Manager or the registry; a service restart is required | poorly — short-lived certs imply scheduled restarts | in an Always On AG, rotate via rolling restarts of secondaries, then fail over |
| MongoDB 4.4+ | yes | `db.adminCommand({rotateCertificates: 1})`; also `SIGUSR2` on Linux | yes — trigger on Secret change | rotates TLS, cluster and CRL files together; works on `mongod` and `mongos` |
| Redis / Valkey | yes | `CONFIG SET tls-cert-file` / `tls-key-file` / `tls-ca-cert-file` at runtime | yes — `CONFIG SET` on renewal | the same mechanism on both forks |
| SQLite | n/a | no network listener — no TLS at all | n/a | a network proxy in front owns TLS |
| CockroachDB | yes | `SIGHUP` reloads certs from `--certs-dir` | yes — the standard Kubernetes pattern | the `cockroach cert` CLI or cert-manager can issue |
| ClickHouse | yes | config reload picks up changed cert files; `SYSTEM RELOAD CONFIG` | yes | verify the specific version's behaviour in staging |
| RDS / Azure SQL / Cloud SQL | platform-managed | the provider rotates the server cert | n/a — you cannot issue | your job: ship the provider CA bundle to clients and honour forced CA rotations |

## What holds whatever you pick

- A database certificate expiry is not a warning banner — it is every client connection failing at
  once.
- Encrypted but unverified is theatre: `sslmode=require` checks nothing. `verify-full` or it did
  not happen.
- If certificates are manual and nobody owns expiry monitoring, you have scheduled an outage, date
  TBD.
- Postgres, MySQL, MongoDB and Redis/Valkey reload certificates live; SQL Server restarts — plan
  certificate lifetime around that fact.
- cert-manager renewing the Secret is half the job; the reload trigger is the other half.
- Rotate CAs clients-first with a combined bundle. Server-first is the rds-ca-2019 outage replayed.
- On managed databases your entire TLS job is the client trust bundle — so actually do it,
  everywhere, including CI.
- Private-network plaintext is a decision you write down, not a default you fell into.

## When the evidence is thin

If nothing recorded distinguishes the options and the database is managed, the answer is already
made for you: platform-managed certificates, with the work being the provider CA bundle shipped to
every client and `verify-full` on every connection string. If it is self-hosted on Kubernetes with
cert-manager present, recommend auto-rotated certificates plus the engine's reload hook. If it is
self-hosted on a private network with no compliance driver and no automation, recommend plaintext
written down as a decision, rather than manual certificates nobody will renew. Name the trigger
that would change it — a compliance requirement naming encryption in transit, a VPC peering, a
move to a shared cluster — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: whether TLS is on at all,
   who issues the certificate, the certificate lifetime, and what triggers the reload.
2. State the recurring cost of each — the cert-manager plumbing, the restart window SQL Server
   obliges, the trust-bundle distribution across every client including CI — and what an expiry
   costs when it lands.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `06-deployment.md`, which records the issuer, the
   lifetime, the reload trigger and the client trust bundle.
4. Manual certificates with no expiry monitoring, a renewal with no reload trigger, a client fleet
   on `sslmode=require`, and an unanswered provider CA-rotation notice are rows in `07-risks.md`,
   each with an owner. Anything the human leaves open is a `TODO(question)` per `templates.md`.
