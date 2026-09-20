---
written_against: "web research 2026-08"
---

`written_against` names the product and specification state this rubric was checked against — what
the managed DNS providers offer at the apex, which registrars support hardware-key MFA and registry
lock, and what CAA supports beyond `issue`/`issuewild`. A vendor page that contradicts it means
this file is stale and needs re-research, not that the solution drifted.

# DNS and domains — ownership, zone hosting, records

Load this when domain registration, DNS host choice, environment subdomains, TTLs, CAA records,
apex and www handling, or DNS-driven failover comes up. The question it settles: who owns the
domain, who serves the zone, and can you change the records that matter in minutes — reviewed,
versioned, and not living in a founder's personal account. `tls-certificates.md` depends on the
answer, because DNS-01 issuance needs an API token in the zone; `edge-proxy.md` owns what the
records point at; `machine-topology.md` decides whether there is a second site to fail over to at
all, which is what makes low TTLs worth paying for.

Outputs land in `06-deployment.md` (the zone, the registrar, the TTL policy, who can change a
record), in `02-constraints.md` when ownership or a naming scheme is a fixed constraint, and in an
ADR per `templates.md`.

DNS is the one dependency in front of everything else, and it fails in two boring ways. Ownership:
the domain sits in a personal registrar account with SMS 2FA and a personal recovery email.
Agility: the record you must flip during an incident carries a 24-hour TTL, so a five-minute
failover becomes a day.

Separate the two roles. The registrar holds legal ownership — put it in an organisation account,
with MFA via an authenticator app or hardware key, registrar lock on, and individual logins. The
DNS host serves the zone — pick one with a real API, so IaC and ACME DNS-01 both work. Then treat
zone content as code: Terraform, OctoDNS or DNSControl, reviewed in pull requests, rolled back by
revert.

TTL is a failover parameter, not a performance knob: 30 to 60 seconds on records you flip in an
incident, longer on stable ones — and remember that resolvers floor small TTLs, so DNS failover is
a minutes-scale tool, never seconds. CAA records pin which CA may issue for the domain. Apex
domains cannot carry a CNAME, so use the host's ALIAS or flattening feature and redirect www
consistently in one direction. The safe default is cloud DNS managed by IaC, low TTLs on
failover-relevant records, wildcard staging subdomains, and a registrar with MFA and organisation
ownership.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Domain registered under a founder's personal account | move it to an org account now, while everyone is still friendly |
| Any DR posture beyond backup-only | low TTLs on the records the failover flips, and the flip automated or one reviewed commit away |
| Wildcard or per-service certificates via ACME DNS-01 | a DNS host with an API and plugin support; scope the token to TXT in the target zone only |
| Multiple environments | a wildcard subdomain per environment — one record, one wildcard certificate, no DNS change per deploy |
| An app or CDN target at the naked domain | ALIAS/ANAME/flattening at the apex — a literal CNAME there is illegal and shadows MX |
| Records edited by hand with no history | the zone in IaC; keep DNS state separate from compute state so the zone survives a stack rebuild |
| Issuance abuse is a concern | CAA `issue`/`issuewild` naming your CA; pin `accounturi` and `validationmethods` for the strongest posture |

## Registrar defaults (manual)

- **Use when** a side project fronting nothing critical.
- **Pros** zero setup; one bill, one login.
- **Cons** registrar DNS panels are the weakest consoles in the industry — often no API, no ALIAS
  and only coarse TTLs; a registrar compromise takes DNS down with it, and there is no history of
  what changed.
- **Typical mistakes** a personal account with SMS 2FA and personal-email recovery; default 24-hour
  TTLs left on records that will one day need flipping.

## Managed DNS, console-managed

- **Use when** a real DNS host (Route 53, Cloudflare, Azure DNS class) is in place but records are
  clicked in by hand — a tolerable waypoint, not a destination.
- **Pros** proper features: ALIAS at the apex, per-record TTLs, health checks available; separating
  the DNS host from the registrar cuts concentration risk.
- **Cons** unversioned and unreviewed, so a fat-fingered record has no PR and no revert; tribal
  knowledge, where the person who set it up is the documentation.
- **Typical mistakes** no MFA on the DNS host account, because "it's just DNS".

## Managed DNS in IaC

- **Use when** anything a business depends on — this is the default: zone content in Terraform,
  OctoDNS or DNSControl, applied through CI, consoles read-only.
- **Pros** every record has a PR, an author and a revert path; ACME DNS-01 and external-dns work
  against the same API; the zone is reproducible after an account loss.
- **Cons** console bypasses create drift that the next apply silently reverts, so enforce read-only
  consoles or reconcile on a schedule.
- **Typical mistakes** assuming NS delegation and registrar settings are covered by IaC, when they
  usually are not; god-scoped API tokens in CI where a TXT-only token would do; DNS state
  entangled with compute state, so a stack teardown takes the zone with it.

## Managed DNS in IaC with failover routing policies

- **Use when** DR is warm standby or active-active: health-checked failover, latency or weighted
  routing declared in code, so the incident-time flip is automatic or a one-line change.
- **Pros** failover in roughly 30 to 90 seconds of detection plus TTL, with no human at 3 a.m.; the
  failover path lives in the repo, not in someone's head.
- **Cons** health checks must probe real application health — a TCP-open check fails over on
  nothing and misses a dead app; resolvers floor small TTLs and corporate caches stretch them, so
  sub-minute guarantees need an anycast load balancer, not DNS.
- **Typical mistakes** failover records with a one-hour TTL, so the policy flips instantly while
  clients keep the dead IP for an hour; never rehearsing the failover, so the first test is the
  incident.

## Record decisions

| Decision | Recommendation | What breaks otherwise |
|---|---|---|
| TTL on failover-relevant records | 30–60s; the query-volume cost is negligible | a 24h TTL on the record you flip during an incident — a day of stale caches |
| TTL on stable records (NS, MX) | 1h–24h; lower it temporarily before planned migrations | everything at 60s buys nothing; everything at 24h makes every change a day-long rollout |
| CAA | `issue`/`issuewild` naming your CA; pin `accounturi` and `validationmethods=dns-01` if you can keep them current | no CAA means any CA can be tricked into issuing for your domain |
| Apex / www | ALIAS or flattening at the apex; 301 www to apex (or the reverse) — one direction, everywhere | a literal apex CNAME is rejected or shadows MX/TXT and mail dies; a split-brain apex-vs-www duplicates cookies and SEO |
| Environment scheme | wildcards per environment (`*.staging`); production records explicit | per-service manual records make every new service wait on a DNS PR; one flat wildcard over prod and staging lets a staging takeover impersonate production |
| Registrar account | org-owned, individual logins, authenticator or hardware-key MFA, registrar lock; registry lock for high-value domains | the founder leaves or gets phished and the company's front door goes with them |

## What holds whatever you pick

- Registrar and DNS host are two decisions: the registrar holds legal ownership, the DNS host
  serves the zone. Bundling them concentrates risk in one login.
- The domain belongs to the organisation, not a person: org account, individual logins,
  hardware-key MFA — never SMS.
- TTL is a failover parameter: 30–60s on anything you flip in an incident, and DNS failover is a
  minutes-scale tool, never seconds.
- Zone content is code, applied by CI, with consoles read-only; keep DNS state separate from
  compute state.
- Publish CAA before an attacker publishes a certificate.
- No CNAME at the apex — ALIAS or flattening plus a consistent 301.
- Wildcards for ephemeral environments, explicit records for production; a wildcard spanning prod
  is an impersonation risk.
- If failover depends on a DNS flip, the flip is automated or one reviewed commit — a runbook step
  that says "log into the console" fails at 3 a.m.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a managed DNS host separate from the
registrar with the zone in IaC, low TTLs on whatever the incident runbook would flip, a wildcard
per non-production environment, CAA naming the CA that `tls-certificates.md` selected, and the
registrar in an organisation account with hardware-key MFA and registrar lock. Name the trigger
that would add routing policies — a warm standby worth failing over to, a signed availability
target, a second region — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: who owns the domain, who
   hosts the zone, whether records are code, and what the TTL is on anything an incident flips.
2. State for each what it costs and in whose hours, what it locks in, and what a lost registrar
   account or a stack teardown would cost if the zone lives inside it.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `06-deployment.md`.
4. A personally owned domain, a 24-hour TTL on a failover record, a missing CAA record, a
   god-scoped DNS token in CI and a failover nobody has rehearsed are rows in `07-risks.md`.
   Anything the human leaves open is a `TODO(question)` per `templates.md`.
