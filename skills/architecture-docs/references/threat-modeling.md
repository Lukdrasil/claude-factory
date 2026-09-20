---
written_against: "web research 2026-08"
---

`written_against` names the practice state this rubric was checked against — Shostack's four
questions and the STRIDE framing as currently taught. A newer method that contradicts it means this
file is stale and needs re-research, not that the solution drifted.

# Threat modeling — who the attacker is, and when you re-ask

`security.md` runs a threat-model pass as the step that produces the ids its options are argued
against. This file is that pass in full: how the practice is scoped, what tier of formality the
system earns, and — the part teams skip — what triggers re-opening the model after launch. The
mechanisms the model justifies are chosen in `security.md`; the boundaries themselves are drawn on
`01-context.md` and `03-containers.md`, so `diagrams.md` decides which view carries them.

The practice is Shostack's four questions — what are we working on, what can go wrong, what are we
going to do about it, did we do a good job — answered against trust boundaries drawn on the
existing architecture diagram. STRIDE is walked per boundary crossing, or abuse cases are listed
per top flow when STRIDE feels too ceremonial. The output is a ranked mitigations list with owners,
not a document. The safe default is one workshop at design time, re-run on triggers: a new edge on
the diagram, a new data classification, a new principal, a new deployment boundary.

Mechanisms without a model of the attacker produce the classic failure — strong auth on the front
door and an unauthenticated admin webhook on the side. The model is what tells you the webhook is a
door.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Nobody can say who the attacker is or what they would want | one design-time workshop before any mechanism is chosen |
| A diagram exists but has no trust boundaries drawn | draw them first — every arrow that crosses one is a threat surface |
| New edge: webhook, callback, admin panel, integration, queue consumer | re-run for that edge before it ships — side doors are where the front-door model is silently wrong |
| New data class: payments, health, credentials | disclosure and repudiation threats change even if code paths do not |
| LLM feature ingesting untrusted content, or an agent loop with tools | the model boundary is a trust boundary; prompt injection is tainted input crossing it |
| Compliance audits the SDLC | recurring per-feature review with a written register — auditors ask for the model, not the firewall config |
| Internal tool, one boundary, no sensitive data | a one-time boundary sketch is honest; a formal program is process theater |

## None

- **Use when** almost never honest — defensible only for a throwaway prototype with no real data,
  and it stops being defensible the day either appears.
- **Pros** zero cost until the incident.
- **Cons** security becomes a pile of mechanisms with no model, so controls cluster where
  developers already looked and vanish where they did not; and the unauthenticated admin webhook
  ships, because nobody asked what doors exist.
- **Typical mistakes** believing a pentest before launch substitutes for a model — it samples the
  surface once, late; equating "we use OAuth and TLS" with "we thought about threats".

## One-time design workshop (four questions plus boundary sketch)

- **Use when** the safe default for a small team: one session at design time — boundaries on the
  diagram, the four questions, STRIDE or abuse cases on the top flows, a ranked mitigations list
  with owners.
- **Pros** hours, not weeks, and it produces the one artifact that catches side doors: an
  enumeration of every boundary-crossing edge. The list plugs straight into the backlog.
- **Cons** the model rots as the system grows — a launch diagram says nothing about the webhook
  added in month four, and there is no trigger to re-open it.
- **Typical mistakes** producing a threat document instead of a mitigation list, since findings
  without owners are shelfware; modeling components instead of boundary crossings, when threats
  live on the arrows and not the boxes; inviting only security people, so the developers who know
  the real data flows stay silent.

## Recurring per-feature review

- **Use when** the system is alive and growing: the model is re-opened on defined triggers — a new
  edge, a new data class, a new principal, a new deployment boundary — and abuse cases become
  acceptance criteria on the story that introduces the surface.
- **Pros** the model tracks the system instead of describing its past, and it is cheap per
  iteration, since most features touch no boundary and take five minutes to wave through.
- **Cons** it needs a working definition of "touches a boundary" or everything gets waved through,
  and the discipline decays without a PR-template hook.
- **Typical mistakes** triggering on "big feature" instead of "new edge or new data class", when
  the dangerous webhook is often a small feature; re-running the full workshop every sprint until
  the team stops attending.

## Formal program (tooling, register, SLAs)

- **Use when** multiple teams, regulated data, or auditors in the room: threat modeling tooling, a
  living register, mitigation SLAs by severity, a named owner per finding.
- **Pros** it survives team churn and audit scrutiny, because the register is the evidence, and
  findings cannot silently expire.
- **Cons** real ongoing cost, and it degenerates into register-tending theater if leadership only
  reads the metrics.
- **Typical mistakes** buying the tool before the team can run a whiteboard session — tooling
  amplifies a practice, it cannot create one; measuring threats-logged instead of
  mitigations-shipped.

## STRIDE per trust boundary

| Letter | Question at each boundary crossing | Typical finding |
|---|---|---|
| S — Spoofing | Who is on the other end of this arrow, and how do we know? | A webhook that trusts the caller by network position — anyone who finds the URL is "the payment provider" |
| T — Tampering | Can the data be altered in transit or at rest across this boundary? | Client-supplied price or role fields trusted after the boundary |
| R — Repudiation | If this action is disputed, can we prove who did it? | Admin actions with no audit trail; shared service accounts making every log line say "system" |
| I — Information disclosure | What leaks if this flow is observed, logged, or errors out? | PII in URLs and access logs; stack traces to the client; errors that enumerate valid usernames |
| D — Denial of service | What happens when this boundary is flooded or the dependency stalls? | An unauthenticated endpoint doing expensive work (file parsing, LLM call) with no rate limit |
| E — Elevation of privilege | Can a caller on this side reach capabilities meant for the other? | The classic side door: authenticated user endpoints, unauthenticated admin webhook; IDs checked for authentication but not ownership |

## Re-run triggers

| Change | Why the old model is now wrong |
|---|---|
| New edge (webhook, integration, admin surface, consumer) | The model enumerated doors; this is a door it has never seen |
| New data class (payments, health, credentials) | Disclosure and repudiation stakes changed without any code path changing |
| New principal or auth mechanism | Spoofing and elevation assumptions were written against the old identities |
| New deployment boundary (extracted service, new region, edge logic) | In-process trust became network trust |
| LLM feature or agent tool added | A new interpreter of untrusted input appeared inside the trust boundary |

The LLM row is where this file meets `llm-features.md`: the model boundary is a trust boundary, and
prompt injection is tainted input crossing it.

## What holds whatever you pick

- Answer the four questions in order — a mechanism chosen before question one is a guess wearing a
  control's clothes.
- Threats live on arrows that cross trust boundaries, not on boxes: draw the boundaries first, then
  walk STRIDE per crossing.
- The deliverable is a ranked mitigations list with owners, not a threat document.
- The model exists to find side doors: enumerate every externally reachable edge, then ask why each
  is allowed to exist and who authenticates it.
- Re-run on triggers, not on a calendar — new edge, new data class, new principal, new deployment
  boundary.
- Abuse cases become acceptance criteria on the story that introduces the surface; security
  requirements that cannot fail a build do not exist.
- "We use strong auth" is a mechanism, not a model — the front door being locked says nothing about
  the loading dock.

## When the evidence is thin

If nothing recorded distinguishes the tiers, recommend the one-time design workshop with defined
re-run triggers: boundaries drawn on the existing diagram, the four questions answered, STRIDE
walked on the top flows, and a ranked mitigations list with an owner per row. Name the trigger that
would move it up a tier — the first regulated data class, the second team pushing to the same
system, an auditor asking for the model — as a row in `07-risks.md`.

## Recording the choice

1. Put the tiers to the human against the affected `QS-` and `C-` ids: which formality the system's
   data class, team count and audit exposure actually earn, and what each costs per iteration.
2. State what the model produces and who owns it — the mitigations list, the register, the PR-template
   hook — and what its absence costs, which is a control surface shaped by where developers happened
   to look.
3. Write the accepted practice as an ADR under `docs/adr/`, the rejected tiers as alternatives with
   the reason each lost, and draw the trust boundaries on `01-context.md` and `03-containers.md`
   where the options can be argued against them.
4. Each mitigation becomes a backlog row with an owner; measurable ones become `QS-` rows with a
   number and a unit. Threats accepted unfixed are `R-` rows in `07-risks.md` with an owner and a
   mitigation. Anything the human leaves open is a `TODO(question)` per `templates.md`.
