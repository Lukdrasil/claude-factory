---
written_against:
  keycloak: "26.7 (July 2026) — features list and token-exchange docs checked 2026-08"
  others: "Entra ID, Auth0/Okta, Ory Hydra, Dex, OpenFGA — as documented 2026-08"
  specs: "RFC 8252, 8628, 8693, 8705, 9449, and RFC 9700 (OAuth security BCP, Jan 2025)"
  note: >
    The capability table is product-version-sensitive. `audit` diffs this stamp against the versions
    it finds: a contradiction means this file is stale and the claim needs re-checking against the
    vendor's docs, not that the solution drifted.
---

# Authentication flows per client type — decision rubric

`security.md` decides the shape: identity bought or run, browser session or token, which
authorization model, how tenants are isolated in the data layer. This file starts after those
answers, picks the concrete grant for each client, and checks the chosen product implements it.
"IdP or not", "BFF or tokens in the browser", "shared schema or database per tenant", "RBAC or
ReBAC" are answered there — point at it, never repeat it. Outputs: an ADR per flow (which grant,
for which client, why), the mechanism annotated on the matching edge in `03-containers.md`, `C-`
rows for what the product cannot do (a missing capability below is a constraint, not a detail), and
`R-` rows for accepted weaknesses.

## Choosing by driver

| Driver | Candidates to put on the table |
|---|---|
| Browser app, human user | authorization code + PKCE (shape per `security.md`) |
| CLI on a developer laptop with a browser | auth code + PKCE with loopback redirect · device grant |
| CLI over SSH, in a container, on a headless box | device grant · pre-issued token |
| CI pipeline, scheduled job, no human ever | workload identity federation · client credentials |
| Script by a person, few users, low value | personal access token |
| Mobile or desktop app | auth code + PKCE in the system browser |
| API A must call API B as the user | token exchange · audience requested up front · internal trust past the gateway |
| Service acts as itself | client credentials · mTLS-bound token · workload identity (SPIFFE class) |
| One IdP deployment serves several customers | realm per tenant · one realm + organizations · separate IdP instances |

Two grants are excluded rather than offered: implicit, and resource owner password credentials —
RFC 9700 deprecates the first and says the second MUST NOT be used. An existing client on either is
an `R-` row with a migration target, not an option.

## Browser clients

The architectural choice — BFF with a session cookie, same-origin session, or tokens in the
browser — belongs to `security.md`. Once it is made the grant is the same in every branch:
**authorization code + PKCE**. Only who holds the secret changes.

A **confidential client** (server-rendered app, or the BFF acting for a SPA) authenticates to the
token endpoint with a secret or private key, keeps both tokens server-side, and gives the browser
only the session cookie. A **public client** (SPA or native app talking to the IdP itself) can keep
no secret, so PKCE is the only protection on the code, exact redirect-URI matching is mandatory, and
refresh tokens are rotated with reuse detection. **Typical mistakes** treating PKCE as optional for
confidential clients — it costs nothing and blocks code injection; wildcard or path-suffix redirect
URIs; tokens in `localStorage` when the ADR said BFF; a logout button whose scope (local, IdP, other
SSO apps) was never decided.

## CLI and developer tools

The section most often got wrong, because tools ship an API key first and never revisit it. Choose
per environment, and expect a real tool to implement two: interactive for humans, non-interactive
for CI.

### Authorization code + PKCE with a loopback redirect

The RFC 8252 pattern, and what the `gh` / `az` / `gcloud` class does interactively: listen on
`127.0.0.1` on an ephemeral port, open the system browser, take the code on that loopback URL.

- **Use when** a browser opens on the same machine as the CLI — a developer laptop, the common case.
- **Pros** fastest for the user (one tab, usually already signed in); the redirect proves the same
  machine started the flow; no code a human could be tricked into approving; device policies and MFA
  apply normally.
- **Cons** needs a free local port and a launchable browser; fails confusingly over SSH, in
  containers and in split browser/terminal setups (WSL, dev containers, forwarded ports).
- **Typical mistakes** a fixed port that collides with another tool — register `http://127.0.0.1`
  with any port, which the spec allows; `localhost` instead of the literal loopback IP, so name
  resolution decides where the code lands; skipping the `state` check; leaving the listener open.

### Device authorization grant (RFC 8628)

The CLI shows a user code, the human enters it at a URL on any device, the CLI polls the token endpoint.

- **Use when** the CLI cannot open a browser on its own machine — SSH, containers, appliances — or
  as the documented fallback when the loopback flow fails.
- **Pros** no local browser, listener or port; the user can approve on a phone; the server dictates
  poll interval and expiry.
- **Cons** slower and manual; failure is silent until the poll times out; phishable by design, since
  an attacker can start the flow and get a victim to approve their code — after the STORM-2372
  campaign (2025) Microsoft advises blocking it tenant-wide except for documented cases, so an
  enterprise IdP may simply refuse it.
- **Typical mistakes** making it the only flow, so the tool dies when a customer disables the grant;
  polling faster than the returned `interval` and being throttled; a clickable link that pre-fills
  the code, which trains users to approve codes they did not generate; no expiry handling.

### Personal access tokens and API keys

A long-lived string the user creates in a UI and pastes into the tool.

- **Use when** users are few, value at risk is bounded, or the audience is scripts written by the
  account's own owners.
- **Pros** trivial on both sides; works everywhere, curl included; scopes and expiry attach to it if
  the product implements them.
- **Cons** a long-lived bearer secret that lands in shell history, `.env` files and CI variables; MFA
  and conditional access bypassed; revocation waits for someone to notice; the audit trail says "the
  user", never "which tool".
- **Typical mistakes** no expiry and no scopes, so one token is the whole account; one token shared by
  a team, making revocation an outage; a validation path separate from OAuth tokens, so the two
  authorization models drift apart.

### Where the tokens live

**OS keychain first** (macOS Keychain, Windows DPAPI, Secret Service on Linux) with a `0600` file
fallback in the tool's config directory — headless Linux has no keyring, so the fallback is not
optional. **Cache the refresh token, not the password**: store access token, refresh token and expiry
together, refresh before expiry rather than on a 401 loop, and replace the whole pair when the server
rotates it, or the next refresh fails and the user is logged out for no visible reason. **State the
re-login interval** — refresh idle timeout and absolute lifetime decide how often a developer
re-authenticates, so it is a `QS-` row; IdP defaults (30 minutes idle in a stock Keycloak realm)
produce an unusable CLI if nobody looked. **Typical mistakes** one token file shared by every profile
or tenant; a world-readable path; the token printed on `--verbose`; a `logout` that deletes the file
without revoking anything.

### The CI and non-interactive case

Prefer **workload identity federation**: the pipeline presents the OIDC token its platform already
issues (GitHub Actions, GitLab CI, a Kubernetes service account) and exchanges it for an IdP token,
with trust configured as issuer + subject + audience. No secret is stored anywhere. Fall back to
client credentials — the tool acting as itself, not as a person — only where federation is
unavailable, and then record rotation ownership in `operations.md`; a long-lived CI secret with no
owner is the usual way a build system becomes the weakest identity in the system.

## Mobile and desktop apps

Same family as the CLI's interactive flow: authorization code + PKCE, public client, authorization
request opened in the **system browser** (`ASWebAuthenticationSession`, Custom Tabs) or the
platform broker — never an embedded webview, which sees the user's credentials, breaks device-bound
SSO and is rejected by several IdPs. Redirect via a claimed HTTPS URL where the platform supports
it, a private-use URI scheme otherwise; refresh tokens live rotated in the platform keystore, and
the app must survive their revocation.

## Token exchange (RFC 8693)

One endpoint call trades a token for another with a different audience, scope or subject — how a
downstream call keeps the user's identity without replaying the user's token.

**Delegation vs impersonation.** In delegation the new token names both parties — the subject stays
the user, an `act` claim says which service is acting. In impersonation it looks exactly like the
user's and the acting service disappears. Delegation is the default whenever anyone will later ask
"who actually did this": under impersonation the audit trail cannot separate the user's own action
from a service acting for them. Impersonation is for deliberate cases (support staff reproducing a
user's view) audited at the point of issue.

**The downstream-call problem** — API A must call API B as the user. Three answers:

- **Exchange at the boundary.** A swaps its inbound token for one addressed to B with a narrower
  scope. Pros: B validates a token meant for it, scope shrinks per hop, `act` records the chain.
  Cons: a round trip to the IdP per hop unless cached, and the IdP must permit each pair.
- **Ask for the audience up front.** One token issued for A and B together. Pros: no extra call,
  simplest to operate. Cons: valid at every listed audience for its whole life, so the blast radius
  is their union — workable for two or three services, not a mesh.
- **Trust the network past the gateway.** The edge authenticates the user; inside, services pass the
  user id in a header over mTLS or a private network. Pros: no per-hop token work. Cons: any
  workload on that network can claim to be any user, so it is honest only with segmentation plus
  service authentication, recorded as an accepted risk with the boundary named.

Microsoft's On-Behalf-Of is the same idea with a different grant (`jwt-bearer`, not the 8693 grant
type) and no `act` claim — the acting party sits in `azp`. Compare it as token exchange, record the
difference as portability cost.

**Typical mistakes** forwarding the user's original token onward, so audience checks must be
loosened — after which any service holding any token can call any other; exchanging without
narrowing scope, which is a rename not a reduction; accepting a token whose `aud` is someone else;
chains long enough that nobody can say what the last hop may do; caching exchanged tokens past the
user's session.

## Service to service

`security.md` decides *whether* the boundary needs authentication and how it is layered; this is
what to configure once it does.

| Mechanism | Use when | Costs and caveats |
|---|---|---|
| Client credentials grant | the callee must know what the caller may do, not only who it is; the IdP is already there | a secret to rotate (or a key pair); scopes need the same review as user scopes; a stolen token is usable anywhere the audience accepts it |
| Certificate-bound token (RFC 8705) | a stolen token must be useless without the caller's key | mTLS everywhere on that path; a PKI with rotation; the `cnf` claim must actually be checked by the callee, which is the step most often skipped |
| DPoP (RFC 9449) | sender-constraining is wanted without mTLS plumbing — typically public clients | proof-of-possession code on every caller; less mature server-side than mTLS binding |
| Workload identity (SPIFFE/SPIRE, cloud managed identity) | the platform can attest workloads, so no secret exists to steal | ties the design to that platform or a mesh; identity says who, never what they may do — pair it with scopes or a policy engine |

**The tenant dimension.** A service token says which service is calling, not which tenant it acts
for. Decide explicitly and write it on the edge in `03-containers.md`:

| How the tenant is carried | Consequence |
|---|---|
| A claim — one client per tenant, or one exchange per tenant | strongest: the callee reads it from a claim it already validates; costs one client or exchange per tenant, which caps how far it scales |
| A header beside a system-level token | cheap and common, sound only where the caller is trusted to assert tenancy — the callee treats a header as trusted input, which is the assumption to record |
| Derived from the exchanged user token | works for request paths; background jobs with no user need their own answer, or the batch path silently becomes the header case |

Whichever is chosen, the tenant reaching the data layer comes from a validated claim, never from a
request body — the isolation mechanism in `security.md` is only as good as this step.

## Multi-tenancy at the IdP

Distinct from the data-layer isolation in `security.md`: that decides where a tenant's *rows* live,
this decides where its *users, login page and IdP configuration* live. Chosen independently —
database-per-tenant under a single shared realm is a coherent pair.

- **One realm per customer** — **use when** customers need separate admins, their own federation and
  themes, or a contract demands visible separation. **Pros** hard separation of users, clients, roles
  and configuration; per-customer theming and upstream IdPs; offboarding is deleting a realm.
  **Cons** no SSO across realms without brokering; every realm is configuration to migrate on
  upgrade; admin work multiplies; onboarding becomes provisioning. **Ceiling** low hundreds on
  Keycloak before cache tuning, and each realm's own admin client is evaluated on master-realm
  login — fine at 5–20 tenants, painful at 500.
- **One realm plus organizations** — **use when** tenants are many and need branding, their own
  upstream IdP and membership in tokens rather than isolated administration. **Pros** one realm to
  operate and upgrade; a user can belong to several organizations; email-domain routing to the right
  upstream IdP; membership arrives as a claim the API authorizes on. **Cons** weaker admin isolation;
  clients, roles and flows are shared; membership is a user concept, so service accounts need the
  tenant carried another way.
- **Separate IdP instances** — **use when** residency, an air gap or a customer-run directory forces
  it. **Pros** total isolation, availability and upgrade schedule included. **Cons** every operational
  cost multiplied; no shared SSO; the product must resolve which issuer a request belongs to before
  it can validate anything.
- **Typical mistakes** a realm per tenant at a count that turns upgrades into a programme; SSO
  promised across realms that share no session; tenant read from a subdomain or header rather than
  the token's issuer and claims; theming forked until upgrades stall; no automated provisioning, so
  tenant configuration exists only in production.

## Capability mapping

Verified 2026-08 against the versions in the frontmatter. Re-check any cell before quoting it in an
ADR; this table dates faster than the rest of this file.

| Capability | Keycloak 26.7 | Entra ID | Auth0 / Okta | Ory Hydra / Dex | OpenFGA class |
|---|---|---|---|---|---|
| Auth code + PKCE | yes | yes | yes | yes | n/a |
| Device grant (RFC 8628) | yes, `device-flow:v1` default-on, enabled per client | yes, but Microsoft advises blocking it tenant-wide after device-code phishing — assume enterprise customers disable it | yes | yes (both) | n/a |
| Token exchange (RFC 8693) | partial: standard v2 default-on but **internal-to-internal, same realm only**; public clients cannot exchange; no `resource` parameter. Impersonation and external-to-internal remain in the deprecated preview v1; cross-domain chaining needs preview JWT bearer grant (RFC 7523, 26.5) plus experimental delegation | no 8693 grant: On-Behalf-Of via `jwt-bearer`, no `act` claim, acting party in `azp` | yes — Auth0 Custom Token Exchange (validation logic written as an Action), Okta exchange grant incl. third-party subject tokens | Hydra: claimed since v2, reports of gaps — verify against your version before designing on it. Dex: only external token → Dex token via the OIDC connector, no internal delegation | n/a |
| Client credentials | yes | yes | yes | yes (Hydra); Dex is not an OAuth AS for machine clients beyond exchange | n/a |
| Certificate-bound tokens (RFC 8705) | yes, per client (`cnf.x5t#S256`); enabling it forces certificate authentication for that client — non-mTLS flows on the same client break | yes | yes (Auth0 mTLS sender-constraining) | Hydra partial — check the version; Dex no | n/a |
| DPoP (RFC 9449) | yes, `dpop:v1` default-on | partial, platform-specific | partial | partial | n/a |
| IdP multi-tenancy | realms, plus Organizations (GA since 26) for B2B tenants inside one realm | separate tenants; B2B collaboration and External ID for customer-facing | Auth0 Organizations; Okta orgs | none built in — tenancy is yours to model | n/a |
| Fine-grained authorization | Authorization Services (`authorization:v1`, UMA 2.0 resources/policies/permissions) — capable but a per-request call to the IdP; large systems commonly keep coarse roles in the token and put object-level checks in a policy engine | app roles and groups only — object-level authorization is the app's job | Auth0 FGA / Okta FGA (OpenFGA-based) | none — pair with a policy engine | OpenFGA (CNCF incubating since 2025), SpiceDB, Cedar/AVP: relationship or policy checks only, no tokens and no login |
| Runs on your infrastructure | yes | no | no (self-hosted Okta variants aside) | yes | yes |

A "partial" cell is a constraint to record, not a warning to work around: if the design needs
impersonation on Keycloak, the honest options are the deprecated preview feature, another product,
or another design — the human picks which.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the flows that stay correct as the system
grows: authorization code + PKCE wherever a human is present, loopback redirect for the CLI with the
device grant as a documented fallback, workload identity federation for CI, client credentials
between services, and the user's identity carried downstream by exchange rather than forwarding.
Name the trigger that would change it — "the CLI must run over SSH", "a customer requires its own
admins" — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human per client type, with the consequence for the affected `QS-` and
   `C-` ids and what changing the flow later costs (every installed CLI, every mobile release), then
   one recommendation with the driver behind it. The human decides.
2. Check the chosen product against the capability table before the ADR is written; a "partial" cell
   becomes a `C-` row naming the missing capability, or the choice changes.
3. Write the accepted flow as an ADR under `docs/adr/` with the rejected grants as alternatives and
   the reason each lost, and annotate the mechanism on the matching edge in `03-containers.md`.
4. Numbers become `QS-` rows: access-token lifetime, refresh idle and absolute lifetime, how often a
   CLI user re-authenticates, revocation window for a service credential. Accepted weaknesses — a
   long-lived PAT, a trusted internal header, impersonation without `act` — are `R-` rows with an
   owner and a mitigation. Anything left open is a `TODO(question)`, per `templates.md`.
