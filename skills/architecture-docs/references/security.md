# Security — decision rubric

Security decisions have the same shape as every other one in `approaches.md`: options,
consequences, a recommendation, the human decides. "Be secure" is not something you can record,
so this file turns it into things that fit the templates.

The outputs are `C-` rows, `QS-` rows under the `security` and `data protection` attributes,
trust boundaries on the edges of `01-context.md` and `03-containers.md`, an ADR per mechanism,
and `R-` rows for what stays unfixed — see "Recording the choice" at the end.

Where secrets are stored and rotated is `operations.md`; where TLS terminates and which surfaces
are publicly reachable is `deployment.md`. This file decides who is trusted on each side of a
boundary and how that trust is proven.

## The threat-model pass

Run this before offering any option below — it produces the ids the options are then argued
against. Half an hour with the human, not a formal exercise.

1. **Assets.** What an attacker would want and what it costs if they get it, per data class:
   personal data, credentials, money movement and the ability to act as another user are separate
   assets with separate costs.
2. **Trust boundaries.** Every edge in `01-context.md` and `03-containers.md` where the caller is
   not at the callee's trust level: browser to backend, backend to backend, backend to external
   system, operator to production, tenant to tenant.
3. **STRIDE-lite per boundary.** One line each: can the caller be **spoofed**, the payload
   **tampered** with, the action **denied** afterwards, data **leaked**, the callee **exhausted**,
   rights **gained** that were not granted. Write down only what is plausible here.
4. **Turn those into rows.** "Must" facts become `C-` constraints; anything with a number becomes
   a `QS-` row (`security` or `data protection`); what is accepted unfixed becomes an `R-` row
   with an owner.

**Done when** every boundary crossing drawn in `03-containers.md` has an answer to "who proves
identity here, and who decides what they may do" — the mechanism, or a `TODO(question)`.

## Choosing by driver

| Driver in the recorded scenarios / constraints | Candidates to put on the table |
|---|---|
| Users are humans who log in | buy an IdP · run Keycloak · in-app identity |
| Corporate SSO, SAML or directory federation is required | buy an IdP · run Keycloak |
| Browser frontend on its own origin | BFF with a session cookie · make it same-origin · tokens in the browser (with what it costs) |
| Sessions must die on demand — offboarding, fraud, lockout | opaque + introspection · short-lived JWT with a stated window |
| One deployment serves several customers | shared schema + tenant column · schema per tenant · database per tenant |
| Permissions follow job titles · depend on context · follow who owns or shares an object | RBAC · ABAC · ReBAC (Zanzibar class) |
| More than one deployable unit, network in between | client-credentials tokens · mTLS · segmentation only |
| Regulated data class | record the `C-` rows first; they narrow every option above |

## Identity provider

Who authenticates the user. Decide this before token shape — token shape follows from it.

### Buy a hosted IdP (Entra ID, Auth0, Okta, Cognito class)

- **Use when** users are humans, nobody on the team is an identity specialist, and enterprise
  SSO, MFA, passkeys and the audit trail are wanted rather than built.
- **Pros** protocol correctness, MFA, passkeys, breached-password checks and compliance evidence
  arrive as features; no patch cadence, no HA, no session store to operate.
- **Cons** per-MAU pricing scales with success rather than load; login-page customisation stops
  where the vendor stops; the vendor is a hard availability dependency on every login; leaving
  later means every user resets a password unless hashes are exportable.
- **Typical mistakes** using the vendor's profile as the product's user table, so the domain has
  no local user id and every join crosses the network; putting app authorisation data in vendor
  claims and meeting the token size limit; no login-outage scenario in `04-quality-scenarios.md`.

### Run Keycloak yourself

- **Use when** identity must stay on infrastructure the team controls (a `C-` about residency,
  air-gap or a customer contract), several applications need one SSO, or per-user pricing is the
  real blocker at the expected user count. Also when brokering many upstream IdPs (LDAP/AD, SAML
  partners) is itself the requirement.
- **Pros** full protocol surface — OIDC, OAuth 2.x, SAML for legacy clients, brokering, LDAP/AD
  federation; realms separate environments or customer sets hard, and Organizations (26.x) give
  B2B tenants inside one realm instead of one realm per customer; no per-user cost.
- **Cons** you now operate a clustered database-backed application: patch and minor releases land
  every few weeks carrying CVEs, so patching is a standing task; HA means replicated PostgreSQL,
  an Infinispan cache for sessions and a failing-over load balancer, with the Kubernetes operator
  as the maintained path; an outage is a total login outage; major upgrades have broken admin
  APIs and themes before.
- **Typical mistakes** a realm per tenant at a count where realms become an operations problem,
  when Organizations or a tenant claim would do; a login theme customised so far that upgrades
  stall; configuring through the admin console only, so realm config exists solely in production
  and no restore drill has ever been run; one node called HA.

### In-app identity (ASP.NET Core Identity, Devise, Django auth class)

- **Use when** there is one application, no SSO requirement, no second consumer of the identity,
  and the user table is part of the domain. Genuinely adequate there — do not sell a federated
  IdP to an internal tool with sixty users.
- **Pros** no extra deployable unit and no extra failure mode; users are a local table you can
  join; the framework covers hashing, lockout and reset, and is maintained.
- **Cons** MFA, passkeys, social login and SSO are each a project; you own reset flows,
  enumeration resistance and session invalidation; a second application later means sharing a
  database or taking the migration.
- **Typical mistakes** hand-rolling hashing or reset tokens beside a framework that ships both;
  email enumeration through differing error messages or timings; growing three clients against
  the same identity tables rather than migrating.

### No authentication, or homegrown

Legitimate only when the system has no user-specific data and no state-changing endpoint, and
then it is recorded as a decision, not an omission. A homegrown scheme (a shared API key, a
cookie format you designed) has no independent review and no rotation story. **Typical
mistakes**: an "internal only" service reachable from the network whose only protection is that
nobody has looked; one shared key for every caller, so revoking it breaks everyone and the log
cannot say who acted.

## Token and session architecture

- **Session cookie against the app that issued it** — `HttpOnly`, `Secure`, `SameSite`. Simplest
  correct answer for a server-rendered or same-origin frontend: state is server-side, so logout is
  immediate. Costs a shared session store beyond one instance and CSRF defence on writes.
- **JWT bearer token** — self-contained, validated locally against the issuer's JWKS, no call per
  request. Right when many services validate independently and a short validity window is
  acceptable. It cannot be un-issued: until `exp` it is valid whatever happened server-side.
- **Opaque token plus introspection** (RFC 7662) — the resource asks the authorization server per
  request. Real revocation for one call on the hot path, and if you cache it the cache TTL *is*
  the revocation window. The phantom-token variant keeps tokens opaque outside and exchanges them
  at the gateway for a short-lived JWT inside.

**Browser frontends.** A SPA is a public client: any script on the page reads whatever the page
reads, so tokens in `localStorage` fall to one XSS or one compromised dependency. RFC 10017 puts
the backend-for-frontend first — a server-side component is the confidential OAuth client, holds
the tokens, and gives the browser only an `HttpOnly` session cookie while proxying API calls.
Recommend BFF when a browser app calls APIs that matter; where frontend and API are one
deployable unit on one origin, a plain session cookie already is a BFF and needs no OAuth
machinery. If tokens must live in the browser, record the blast radius as a risk, keep them in
memory only, and use authorization code + PKCE with refresh-token rotation.

**Where validation runs.** At the edge: one implementation, one place to get issuer and audience
checks right — and then services behind it must be unreachable from outside, or the check is
optional. In every service: no bypass point, at the cost of the same code everywhere. Most
systems do both, and the honest version is that the edge rejects garbage while the service still
checks the claims it acts on.

**Refresh, revocation, logout.** State the number: how long after an account is disabled can that
user still act. Short access-token lifetimes with rotating refresh tokens are the usual answer;
introspection or a deny-list is the answer when the number must be near zero. Logout must say
what it ends — the local session, the IdP session (OIDC RP-initiated logout), or the other
applications on that SSO session, which is what back-channel logout is for. The window is a `QS-`
row. **Typical mistakes**: refresh tokens in `localStorage` beside a third-party script;
verifying a signature but not `iss`, `aud` and expiry; trusting the header's `alg`; a logout that
clears client storage while the token stays valid for an hour.

## Multi-tenancy isolation

Only where one deployment serves several customers. The trade is blast radius against cost per
tenant; migration weight decides how hard it is to change later.

- **Shared schema, tenant column** — **use when** tenants are many, small, and no contract demands
  separation. **Pros** one migration, one backup, one pool; cheapest by a wide margin;
  cross-tenant reporting is a query. **Cons** isolation is as good as the weakest query — one
  missing tenant predicate leaks; noisy neighbours share tables and indexes; restoring one tenant
  means extracting rows, not restoring a backup. **Typical mistakes** relying on developers to
  remember the filter instead of enforcing it once (database row-level security, a global query
  filter, a repository that cannot be bypassed); taking the tenant id from a client-controlled
  field rather than the verified token; caches, search indexes and read models keyed without it.
- **Schema per tenant** — **use when** tenants are moderate in number, want visible separation, or
  a few need extensions. **Pros** a corrupted tenant is one schema; per-tenant restore is
  straightforward; the filter is the connection, not the query. **Cons** every migration runs N
  times and must survive interruption halfway; catalogue and connection pool grow with tenants;
  onboarding is provisioning, not an insert; the ceiling is thousands. **Typical mistakes** no
  automated migration runner, so "which tenants are on which version" is unanswerable;
  per-tenant customisation that makes the next migration bespoke.
- **Database or instance per tenant** — **use when** a contract, a regulator or data residency
  requires it, or tenants are few and large enough to pay. **Pros** the strongest blast radius —
  separate credentials, backups, restore, region if needed; noisy neighbours disappear. **Cons**
  highest cost and operational surface; cross-tenant analytics needs its own pipeline; a
  fleet-wide migration is a release programme. **Typical mistakes** choosing it for tenants who
  never asked; a connection string per tenant with no rotation path.

A tiered hybrid (shared for the standard plan, dedicated for enterprise) is legitimate and costs
supporting both paths forever. Whatever is chosen, the tenant id comes from the authenticated
principal and never from client input, and the isolation mechanism is named in `03-containers.md`
beside the store.

## Authorization model

Authentication says who; this says what they may do. It couples to the domain model harder than
anything else here, so decide it with the aggregates in front of you.

- **RBAC** — permissions attach to roles, users hold roles. Use when access follows job function
  and the role list is short and stable. Cheap, auditable, understood by everyone. It fails by
  role explosion: once permissions depend on *which* object, roles multiply per object and the
  model is being abused.
- **ABAC** — a policy evaluates attributes of subject, resource, action and context. Use when
  access genuinely depends on context — amount, time, department, ownership — and the rules are
  stated as rules. Expressive; costs a policy language (Rego, Cedar, or the framework's own) that
  becomes a second codebase with its own tests, and policy sprawl is its failure mode.
- **ReBAC (Zanzibar class: OpenFGA, SpiceDB, Permify)** — permission is reachability in a graph
  of relationships, inherited through folders, groups and teams. Use when users share individual
  objects with users, permissions inherit through a hierarchy, or "who can see this document"
  must be answerable directly. Costs a second store written on every relationship change and read
  on every request; a tuple that fails to be written is a silent access bug, so that write needs
  the same care as the database transaction.

B2B products commonly land on RBAC for coarse rights plus per-object relationships for the rest.
Recommend that hybrid explicitly if it is the answer — chosen deliberately it is fine, arrived at
by accident it is two half-models.

**Where it is enforced.** Every decision runs server-side, in the layer that owns the data, on
the identity from the verified token; the UI hides what a user may not do, it never decides it.
Object-level checks are the ones that get skipped — broken access control has stayed at the top
of the OWASP data across editions, and the recurring shape is an endpoint that authorises the
action but not the specific id, so prefer a query that cannot return another owner's row over a
check bolted on after fetching it. **Typical mistakes**: authorising in a gateway that sees only
the route, not the object; roles duplicated across IdP claims, database and hard-coded strings;
an unscoped "admin" escape hatch; no test that a user of tenant A gets 404 on tenant B's data.

## Service to service

From the second deployable unit onward. Below that this is one line in the ADR: in-process, no
boundary.

- **Client-credentials tokens** — the caller gets its own token from the same IdP and the callee
  validates it like any other, with scopes audited like user scopes. Use when the callee needs to
  know what the caller may do, not only who it is. Costs credentials to rotate; platform workload
  identity (managed identity, federated credentials) removes the stored secret and is preferred
  where it exists.
- **mTLS** — both ends present certificates; identity is the certificate. Use when the transport
  itself must be authenticated and a CA exists or SPIFFE/SPIRE is being run, typically through a
  mesh that rotates short-lived certificates. It answers who is calling, never what they may do,
  and a mesh earns its operating cost only when two of {mTLS, traffic policy, retries} are
  recorded requirements.
- **Network segmentation alone** — private subnets, security groups, no public route. Right as a
  layer under either of the above; as the *only* layer it authenticates the network rather than
  the caller, so use it alone only in a small single-operator system and record the accepted risk.
- Propagating the end user's identity inward is a separate decision: forwarding the user's token
  couples every service to the IdP's audience rules, and token exchange (RFC 8693) is the
  deliberate alternative. Either way the callee must not read the user id from a header the
  caller sets freely.

## Perimeter and application hardening

Not a checklist — the five with architectural consequences, each one line in the ADR.

- **CORS** is a decision only when the frontend has its own origin: name the allowed origins and
  whether credentials are allowed (`*` with credentials is the absence of a decision). Making the
  frontend same-origin, or fronting both from one gateway, removes the question entirely.
- **CSP** pays where XSS would cost most, and it constrains how the frontend may be built (no
  inline scripts without nonces, no arbitrary third-party tags) — so decide it before the UI
  exists or accept a retrofit.
- **Rate limiting** at the proxy protects the app from load but cannot see identity or tenant; in
  the app it can limit per user, per tenant and per expensive operation, at the cost of a request
  that already spent a process. Login, password reset and anything that sends mail or money need
  the per-identity kind.
- **WAF** buys time against generic attacks and answers compliance questions; it costs false
  positives on real traffic and the belief that input handling is solved. Yes when a requirement
  says so and someone owns the tuning; no when nobody will.
- **Supply chain** is among the most common failure categories in the current OWASP data and is
  architectural because it constrains the build: where dependencies may come from, whether the
  lockfile is authoritative, whether images are pinned by digest with provenance verified, and
  who reviews an update. The policy is recorded here; the pipeline enforcing it is
  `deployment.md`.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the reversible, low-surface set: an
identity provider the team does not operate, a server-side session or BFF so no token reaches
browser storage, authorisation enforced in the layer that owns the data with roles at the coarse
level, one tenant-scoped store whose filter is enforced in one place, and service calls kept
in-process until a second deployable unit exists. Name the trigger that would change it — "an
enterprise customer requiring SAML SSO", "a contract demanding data separation", "sharing a
document with an external user" — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human: for each, the consequence for the affected `QS-` and `C-` ids,
   what it costs to run, and what changing it later costs — for identity and multi-tenancy that
   means migrating every user or every row, so say so.
2. Give one recommendation with the driver behind it. The human decides.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected options as its
   alternatives with the reason each lost, and reference it from `03-containers.md` beside the
   boundary it protects.
4. Every measurable outcome becomes a `QS-` row with a number and a unit — revocation window,
   session lifetime, authorisation-check latency, rate limits, time to patch a dependency.
   `security` and `data protection` are named attributes in `04-quality-scenarios.md`; an
   attribute with no row is recorded as not applicable, with its reason.
5. A boundary with a known-weak answer is an `R-` row in `07-risks.md` with an owner and a
   mitigation, not a sentence buried in prose. Anything the human leaves open is a
   `TODO(question)` in the affected document, per `templates.md`.
