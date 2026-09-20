---
written_against: "web research 2026-08"
---

`written_against` names the product and practice state this rubric was checked against — the
identity-native access tools and their free tiers, and the 2026 baseline they imply. A vendor page
that contradicts it means this file is stale and needs re-research, not that the solution drifted.

# Production access — how humans reach production

`security.md` answers who is trusted on each side of a boundary; the operator-to-production edge is
one of those boundaries, and this file is where it gets a mechanism. How humans reach production —
and how that access is authenticated, scoped, audited and revoked — is a separate question from how
services authenticate to each other (`mtls-pki.md`) or how the public surface is exposed
(`edge-proxy.md`). Where the secrets and emergency credentials live is `operations.md`; the audit
trail those sessions produce is `logging-and-audit.md`.

The perimeter model — VPN plus bastion — is being displaced by identity-native access: short-lived
certificates from an SSO-backed CA, per-resource authorization, and recorded sessions, in the
Teleport, Cloudflare Access and Tailscale SSH class. Network reachability and authorization are
separate questions: a WireGuard tunnel proves you are on the network, not who you are or what you
did.

The 2026 baseline is four statements. Nothing admin-shaped on the public internet. No static SSH
keys. Access tied to the IdP, so offboarding is one account disable. And a documented break-glass
path that works when the access plane itself is down.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Compliance includes audit | identity-attributed audit trail and SSH session recording — Teleport or equivalent, not raw VPN plus a shared bastion |
| No ops capacity, or a solo operator | a managed zero-trust overlay (Tailscale, Cloudflare Access free tier) over self-hosting VPN/bastion infrastructure |
| Many teams | per-resource RBAC and just-in-time access requests; shared network-level access stops scaling |
| An admin UI exists | a separate admin plane on an internal-only hostname with its own stronger auth (MFA mandatory) — never a `/admin` route on the public app |
| Contractors or churn | short-lived credentials from SSO, so offboarding is disabling one IdP account |

## WireGuard/OpenVPN into a private network

- **Use when** a small team, self-managed infrastructure, and you want everything internal reachable
  through one encrypted tunnel.
- **Pros** WireGuard is fast, with a tiny config surface and per-device keys; it hides all internal
  services — admin panels, databases, dashboards — from the public internet at once; and there is no
  per-service integration work.
- **Cons** network-level trust, so once tunnelled in access is flat unless you add internal
  firewalling; no identity-attributed audit, since logs show an internal IP rather than a person or
  a command; and key sprawl, where offboarding means hunting down peer configs on the gateway.
- **Typical mistakes** treating VPN presence as authentication and running internal services with
  no auth of their own; never rotating or removing peer keys when people leave; one shared VPN
  profile passed around the team.

## Bastion / jump host with SSH certificates

- **Use when** classic VM and SSH estates, and you want a single hardened, logged choke point in
  front of the servers.
- **Pros** a single audit choke point, which can carry session recording (auditd, tlog, or a
  Teleport agent on the bastion); it works everywhere OpenSSH works; and it pairs well with
  short-lived SSH certificates from smallstep or HashiCorp Vault's SSH CA, where certificates expire
  — passive revocation, with no key cleanup.
- **Cons** a pet server you must harden, patch and monitor forever; with plain `authorized_keys`
  instead of a CA it degrades into a shared-key free-for-all; and it does not cover web admin panels
  or databases without extra tunnelling gymnastics.
- **Typical mistakes** static `authorized_keys` copied to every host behind the bastion, so
  offboarding never actually happens; a bastion that accepts password auth or is itself unpatched;
  no session logging, leaving an audit trail that says only "someone SSHed".

## Mesh overlay (Tailscale / NetBird)

- **Use when** a small-to-mid team wanting VPN convenience with SSO identity and near-zero ops — the
  pragmatic 2026 default for small shops.
- **Pros** a WireGuard mesh keyed to your IdP (Google, GitHub, Entra), so offboarding is disabling
  the SSO account; ACLs per user or group per destination, with MagicDNS making internal hostnames
  trivial; and minutes to deploy, with a free tier that covers small teams and Tailscale SSH adding
  optional session recording.
- **Cons** still network-layer — IP-based ACLs, not per-resource policy, and a weaker audit story
  than an access proxy; the control plane is a third-party SaaS dependency, with self-hosted
  Headscale as the answer if that is unacceptable; and there are no just-in-time or approval
  workflows for privileged access.
- **Typical mistakes** a single flat tailnet where every employee can reach the production database;
  forgetting that node keys persist on stolen laptops if key expiry is disabled.

## Identity-aware access platform (Teleport, Cloudflare Access, StrongDM, Boundary)

- **Use when** compliance needs — SOC 2, ISO 27001, audit — or many teams: per-resource RBAC,
  session recording, just-in-time access requests.
- **Pros** short-lived certificates minted per session from SSO plus MFA, so there is nothing static
  to leak or offboard; full SSH, kubectl and database session recording with a searchable,
  identity-attributed audit trail; access-request workflows (approve one hour of production database
  access) replacing standing privilege; and Cloudflare Access additionally putting internal web
  admin panels behind SSO without a VPN.
- **Cons** real operational and cognitive cost — self-hosted Teleport is its own production service;
  overkill for a two-person team with one VM; and commercial tiers get expensive while the platform
  itself becomes a critical dependency needing a break-glass bypass.
- **Typical mistakes** deploying Teleport but leaving the old bastion and static keys alive as a
  backdoor; no break-glass path for when the access platform is down, which locks you out during the
  incident that most needs access.

## IP allowlist on admin endpoints

- **Use when** a stopgap or a defence-in-depth layer: office and VPN egress IPs allowed at the load
  balancer or cloud firewall. Which IPs those are, and whether they are stable, is `egress-control.md`.
- **Pros** zero client software and one firewall rule; it cuts internet-wide scanning and credential
  stuffing against admin surfaces instantly; and it is good belt-and-braces in front of any of the
  other options.
- **Cons** it breaks with remote work, dynamic IPs and mobile operators; IP is not identity, so
  anyone behind the allowed NAT is "trusted"; and rules rot, with stale entries accumulating that
  nobody dares delete.
- **Typical mistakes** using allowlisting as the only control with a weak password behind it;
  allowlisting an entire cloud provider's range "temporarily".

## Separate admin plane (internal-only hostname, stronger auth)

- **Use when** any app with an admin UI: run admin as its own app and hostname bound to the private
  network, with mandatory MFA. Combine it with one of the network options above — this is a
  companion pattern, not a standalone one.
- **Pros** the admin surface is unreachable from the internet even when app auth has a bug; it
  allows stricter policy where it matters — hardware-key MFA, short sessions, verbose audit logging
  for admin only; and it gives clean blast-radius separation, so admin can be upgraded or locked
  independently.
- **Cons** two deployments and hostnames to run and certificate-manage; it needs a network path for
  operators (VPN, overlay, Access); and shared code between app and admin can still leak privileged
  endpoints into the public app.
- **Typical mistakes** an admin panel on the public internet "protected" by a login form — the
  canonical breach entry point; `admin.example.com` resolving publicly with only basic-auth in
  front; the same session and auth strength for admin as for end users.

## What holds whatever you pick

- Nothing admin-shaped on the public internet: admin UIs, database consoles and SSH belong behind a
  VPN, an overlay, or an identity-aware proxy.
- Prefer short-lived credentials minted from SSO over static SSH keys — expiry is passive
  revocation, and offboarding becomes one IdP account disable.
- Network reachability is not authorization: services behind the VPN still need their own auth and
  MFA.
- If you need audit compliance, you need identity-attributed session recording, not just firewall
  logs.
- Have a tested break-glass procedure — a sealed emergency certificate or key, monitored and alarmed
  — that works when your access platform is down.
- Offboarding is an access-path inventory problem: every static key, VPN peer and shared credential
  is a place offboarding silently fails.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the managed mesh overlay keyed to the
existing IdP with per-group ACLs, plus a separate admin plane on an internal-only hostname with
mandatory MFA, and a sealed, alarmed break-glass credential. Name the trigger that would move to an
identity-aware access platform — an audit requirement, the third team needing production access, a
contractor population — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: which access paths exist
   today, who holds each one, and what an audit would be shown if it asked who ran a given command.
2. State the recurring cost of each — the bastion to patch, the SaaS control plane, the self-hosted
   access platform that is itself a production service — and what the break-glass path costs to keep
   tested.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected options as alternatives with
   the reason each lost, and reference it from `06-deployment.md` beside the admin plane and the
   network path that reaches it.
4. Numbers become `QS-` rows: credential lifetime, time from offboarding to access actually gone,
   session-recording retention, break-glass drill cadence. Every static key, VPN peer and shared
   credential still alive is an `R-` row in `07-risks.md` with an owner. Anything the human leaves
   open is a `TODO(question)` per `templates.md`.
