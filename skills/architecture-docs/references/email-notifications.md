---
written_against: "web research 2026-08"
---

`written_against` names the state of the receiving world this rubric was checked against — the
bulk-sender gates Google, Yahoo and Microsoft enforce, and the provider pricing quoted below. A
mailbox provider's own page that contradicts it means this file is stale and needs re-research,
not that the solution drifted.

# Email and notifications — provider, sending domain, streams, and the job layer

Load this when the system sends any email — password resets, invites, receipts, digests — or when
a checkout or signup flow is about to call SMTP inline, or when deliverability, bounces or DMARC
come up. `security.md` decides whether identity is in-app at all, and that answer settles whether
email is optional; `background-jobs.md` owns the queue this file insists every send goes through;
`operations.md` owns the dead-letter alerting and the retention of the delivery events.

Outputs land in `01-context.md` (the mail provider as an external system), in `06-deployment.md`
(the sending subdomain, the DNS records and where the provider credential lives), in
`04-quality-scenarios.md` (bounce and complaint thresholds, delivery latency) and in an ADR per
`templates.md`. Every choice below reaches the human as options with consequences plus your
recommendation, per `approaches.md`.

Email is an integration with the world's most hostile receivers. Since 2024 Google and Yahoo, and
since May 2025 Microsoft, hard-reject bulk mail — 5,000 or more messages a day — that lacks SPF,
DKIM, and a DMARC policy of at least `p=none` with From-domain alignment. So the decision is not
"which SMTP library" but a chain of five: a provider class (cloud transactional like SES, a
deliverability vendor like Postmark or SendGrid, or self-hosted); DNS authentication on a
dedicated sending subdomain, so a marketing blunder cannot burn the apex domain's reputation;
strict separation of transactional from bulk streams; a suppression list that is actually
honoured; and queue-backed async sending, so a third-party outage never blocks checkout and a
failed password reset retries instead of vanishing.

The safe default is a transactional provider, DKIM and DMARC on a sending subdomain, and every
send enqueued via the job layer with retries and a dead-letter path. The failure mode this
prevents is password resets that are silently not delivered, or request latency welded to someone
else's SMTP server.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| In-app identity — password reset, verification | email is mandatory infrastructure; "none needed" is off the table |
| Any user-facing flow sends mail | async via the job or bus layer; an inline SMTP call puts a third party's p99 into your request path |
| Volume approaching 5,000/day to any major mailbox provider | the bulk-sender gates: SPF, DKIM and DMARC with alignment, RFC 8058 one-click unsubscribe on marketing mail, complaint rate under ~0.3% |
| Marketing shares infrastructure with password resets | separate streams — one flagged campaign must not throttle transactional delivery |
| Already on a hyperscaler with ops for webhooks | the SES class: cheapest per-mail, bounce and complaint handling wired yourself |
| Small team, deliverability business-critical | the Postmark class — pay the markup for isolated transactional infrastructure and built-in suppression |
| Someone proposes Postfix on a VPS | fresh IPs start with zero reputation and VPS ranges are distrusted by default; this is a standing job, not a container |

## None needed

- **Use when** the system genuinely sends nothing: identity is delegated, so the IdP sends its own
  reset mail, and there are no receipts, invites or notifications. Rare, and usually temporary.
- **Pros** zero DNS, zero provider, zero suppression handling.
- **Cons** almost always wrong the moment in-app accounts exist.
- **Typical mistakes** letting the first email requirement land as a synchronous `SmtpClient` call
  in a controller.

## Cloud provider transactional (SES class)

- **License** proprietary; around $0.10 per 1,000 mails.
- **Use when** already on a hyperscaler, ops can wire bounce and complaint webhooks, and cost per
  mail matters.
- **Pros** the cheapest per-mail rate by an order of magnitude; account-level suppression is on by
  default, and DKIM key rotation is provider-managed via CNAME.
- **Cons** batteries are not included — bounce and complaint webhooks, event destinations and
  reputation dashboards are assembly required; sandbox exit and reputation management are your
  problem.
- **Typical mistakes** ignoring the suppression list until the bounce rate trips a sending pause;
  skipping custom MAIL FROM, so the Return-Path never SPF-aligns with your From domain; marketing
  blasts sent through the same configuration set as password resets.

## Deliverability vendor (Postmark / SendGrid class)

- **License** proprietary; roughly 10-20x the SES per-mail rate at volume.
- **Use when** deliverability of transactional mail is business-critical and the team wants it
  managed. Message streams isolate transactional from broadcast down to separate IP ranges.
- **Pros** transactional and bulk separation is a product feature rather than a discipline;
  suppression, bounce classification and activity logs support can search are built in; fast
  time-to-first-mail with guided DNS setup.
- **Cons** the markup is real, with the crossover against SES around 15-20k mails a month; and the
  vendor's shared-pool reputation is still partly a commons.
- **Typical mistakes** buying it for deliverability and then routing the newsletter through the
  transactional stream anyway; assuming a default shared plan isolates your reputation, which costs
  extra; letting the vendor's suppression list and your own user preferences drift apart.

## Self-hosted SMTP

- **Use when** almost never for outbound in 2026: only with dedicated ops, a hard residency or
  air-gap constraint, and volume consistent enough to hold IP reputation. The honest compromise is
  to self-host inbound and relay outbound through a provider.
- **Pros** full data control, and no per-mail cost at volume.
- **Cons** fresh IPs have zero reputation, VPS ranges are distrusted by default, and residential
  ISPs block port 25; you own the full gate list — SPF, DKIM rotation, DMARC reports, feedback-loop
  registration, blocklist delisting; and one blocklist entry means password resets silently vanish
  until support tickets arrive.
- **Typical mistakes** estimating the cost as "a Postfix container" and ignoring the standing
  deliverability job; no DMARC report monitoring, so the failure is silent and discovered by users;
  sending from the apex domain, so a reputation hit poisons corporate mail too.

## DNS records on the sending subdomain

| Record | What it does | What breaks without it |
|---|---|---|
| SPF (TXT) | Lists servers allowed to send for this domain | With DKIM also missing, Google, Yahoo and Microsoft reject bulk mail outright |
| DKIM (selector CNAME/TXT) | Publishes the key receivers verify signatures against | DMARC leans on SPF alone, which breaks on forwarding — deliverability degrades then fails |
| DMARC (TXT on `_dmarc`) | Tells receivers what to do on alignment failure, and where to send reports | Bulk mail rejected; without `rua=` reports you fly blind on spoofing and misconfiguration |
| Custom MAIL FROM / Return-Path | Aligns the envelope-from with your domain; routes bounces to you | SPF passes but does not align; bounces land at the provider, invisible |
| MX on the sending subdomain | Makes the subdomain able to receive | Some receivers score down mail from domains that cannot receive; replies vanish |

## Transactional vs bulk separation

| Concern | Transactional | Bulk / marketing |
|---|---|---|
| Subdomain / stream | Own stream (`mail.example.com`), never shared with campaigns | Separate subdomain (`news.example.com`) so complaints burn only this reputation |
| One-click unsubscribe (RFC 8058) | Not required — users cannot opt out of password resets | Required by Google and Yahoo; must be honoured within two days |
| Suppression list | Hard bounces and complaints; visible to support | Bounces, complaints and unsubscribes; synced with the preference store |
| Failure handling | Queue with retries and dead-letter alerting — a lost reset mail is an incident | Best-effort; a dropped newsletter is a metric |

## What holds whatever you pick

- Send from a subdomain, sign with DKIM there, publish DMARC — the apex domain's reputation must
  survive your worst campaign.
- The 2026 floor near 5,000 messages a day is SPF plus DKIM plus DMARC `p=none` with alignment;
  the big receivers hard-reject below it, they do not spam-folder.
- Never call the mail provider in the request path: enqueue, retry with backoff, dead-letter with
  alerting.
- Transactional and bulk never share a stream, a subdomain or an IP pool.
- Honour the suppression list before every send — repeatedly mailing a hard-bounced address is how
  providers pause your account.
- Treat "password reset delivered" as an observable outcome: track delivery events, alert on the
  bounce and complaint rate, and read the DMARC aggregate reports.
- Self-hosted outbound SMTP in 2026 is a part-time job, not a container. If you must self-host,
  self-host inbound and relay outbound.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend a transactional provider on a dedicated
sending subdomain with SPF, DKIM and DMARC published, every send enqueued through the job layer,
and no bulk stream at all until marketing asks for one. Name the trigger that would change it — a
first campaign, volume approaching the 5,000/day gates, a residency constraint that rules the
provider out — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: the provider class, the
   sending subdomain, and whether a bulk stream exists at all.
2. State the recurring cost of each — per-mail rate at expected volume, the vendor markup, the
   standing deliverability job a self-hosted sender obliges — and what reversing it later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `01-context.md` and `06-deployment.md`.
4. The measurable outcomes become rows in `04-quality-scenarios.md` with a number and a unit: the
   complaint-rate ceiling, the bounce-rate ceiling, the retry budget and the delivery latency a
   password reset is allowed.
5. An unmonitored DMARC `rua=` mailbox, a suppression list nobody reconciles with the preference
   store, and a dead-letter queue with no owner are rows in `07-risks.md`. Anything the human
   leaves open is a `TODO(question)` per `templates.md`.
