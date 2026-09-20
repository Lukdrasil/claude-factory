---
written_against:
  date: 2026-08
  license_texts: "MIT, BSD-2/3-Clause, Apache-2.0, MPL-2.0, LGPL-2.1/3.0, GPL-2.0/3.0, AGPL-3.0, BSL 1.1, SSPL v1, Elastic License 2.0, FSL 1.1, Commons Clause — all stable, none revised since 2023"
  landscape: >
    volatile part: Redis tri-licensed AGPL-3.0/SSPLv1/RSALv2 since Redis 8 (2025); Elasticsearch
    offers AGPL-3.0 alongside SSPL/ELv2 since 2024; Terraform and Vault are BUSL-1.1 under IBM;
    Valkey (BSD), OpenTofu, OpenSearch (Apache-2.0) and OpenBao (MPL-2.0) all sit in the Linux
    Foundation.
  note: >
    audit re-checks the landscape block against the licenses actually declared in the repo's
    manifests — a mismatch means this file is stale and needs re-research, not that the product
    repo did something wrong.
---

# Licensing — what each license family lets you do

Not legal advice: this file turns license text into architectural consequence so you can put
options to the human and route the genuinely risky ones to a lawyer. Said once, here; the
judgment below is given plainly.

Every family is answered against the five questions an architect asks of a dependency or a
platform component:

1. **Use** — may we run it in production, free, self-hosted, commercially?
2. **Modify** — may we change it, and must we publish the changes?
3. **Distribute** — may we embed it in a product we ship to customers?
4. **Serve** — may we offer its functionality to others as a service?
5. **Reach** — does it impose anything on *our* code?

Outputs land as `02-constraints.md` rows with kind `legal` (one per obligation the license
imposes on us), an ADR when a dependency is chosen because of or despite its license, and an
`07-risks.md` row when the exposure is real but accepted. Offer options with consequences and a
recommendation, per `approaches.md` — the human decides.

## Choosing by driver

| Signal in the plan or the repo | What to check |
|---|---|
| A dependency is being added or swapped | its family below, plus the family of everything it pulls in transitively |
| We self-host and never ship binaries | only questions 1, 2 and 4 apply — most copyleft fear here is misplaced |
| We ship an on-prem installer, a container image or a desktop/mobile app | question 3 is live: copyleft reach and NOTICE obligations both bite |
| We offer the component's own functionality to customers as a service | question 4: AGPL, SSPL, ELv2, BSL, FSL all decide here |
| The component is a single-vendor product with a CLA | relicensing risk — see "License change as a driver" |
| A customer contract or tender lists forbidden licenses | a `C-` row, not a preference |

## Permissive — MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0

Yes to all five questions. Nothing reaches into your code.

- **What remains**: keep the copyright and license text in what you distribute. Apache-2.0 adds
  two: state which files you changed, and carry forward the upstream `NOTICE` file's attribution
  into your distribution (a `NOTICE` file, your docs, or a screen the product shows).
- **Apache's patent grant** is why it is the permissive default for anything touching a patented
  area: every contributor grants you a patent licence, and it terminates only if you sue over
  that work. MIT and BSD say nothing about patents, so you rely on an implied licence.
- **Trademarks** are not granted. You may say your product uses the component; you may not name
  your fork after it or use its logo as your own.
- **Typical mistakes** shipping a desktop app or container image with no aggregated
  attribution/NOTICE at all — the one obligation permissive licences do have; assuming Apache-2.0
  and GPL-2.0 mix (they do not — Apache-2.0 is compatible with GPL-3.0 only); treating a
  permissive licence on a repo as covering its trademarks or its hosted service's terms.

## Weak copyleft — MPL-2.0, LGPL-2.1/3.0

Copyleft with a boundary. Your code stays yours; theirs stays theirs.

- **MPL-2.0 is per file.** Files that contain MPL code stay MPL: if you change them and
  distribute the result, those files' source must be available. New files you write contain no
  MPL code, so they are not covered — you may link MPL code statically into a proprietary build
  and ship the whole as a Larger Work under your own terms. Explicit patent grant, like Apache.
- **LGPL is per library.** Same deal one level up: changes to the library are LGPL, your
  application is not. The condition is that a user can replace the library with their own build.
  **Dynamic linking** satisfies that by construction. **Static linking** does not — you must then
  ship what lets the user relink (your object files or the equivalent), which is usually the
  moment a team decides to link dynamically instead.
- **Self-hosted web apps**: nothing is distributed, so nothing triggers at all. Weak copyleft is
  a non-issue for a service you operate; it only becomes work when you ship artefacts.
- **Typical mistakes** vendoring an MPL file into your own module, editing it and forgetting it is
  still MPL; static-linking LGPL into a shipped binary and treating it like MIT; assuming the
  "weak" label means the library's own modifications are yours to keep private — they are not.

## Strong copyleft — GPL-2.0, GPL-3.0

The trigger is **distribution** (GPLv3: "conveying"), not use. Running it is unconditional.

- **The happy consequence most web teams miss**: operating GPL software on your own servers —
  modified or not — is not distribution, so nothing obliges you to publish anything. GPL server
  tools, databases, build tools and CLIs are usable in a commercial SaaS. This is the "ASP
  loophole", and it is why AGPL exists.
- **Where it bites**: shipping an installer, image, appliance or app that contains GPL code. Then
  the whole combined work goes out under the GPL, with complete corresponding source. That
  usually ends the discussion for a proprietary distributed product.
- **Combining vs aggregating**: linking GPL code into your process makes one work; shipping a
  separate program you invoke over a CLI, pipe or socket is normally mere aggregation. The line
  is a legal judgment, not a technical one — if the product's value depends on which side you
  land, that is the case to send to a lawyer.
- **v2 vs v3 in one paragraph**: v3 adds an express patent grant with defensive termination,
  compatibility with Apache-2.0, a 30-day cure period for accidental violations, and
  anti-tivoization — ship GPLv3 code in a consumer device and you must also ship what lets the
  owner install a modified build. For pure server or desktop software the two behave the same;
  for firmware, v3 is a real constraint on locked bootloaders.
- **Typical mistakes** believing internal server use requires publishing anything; reading GPL on
  a CLI tool you merely invoke as reaching your code; ignoring that "complete corresponding
  source" for a shipped product includes your build scripts.

## Network copyleft — AGPL-3.0

AGPL is GPL-3.0 plus §13: **if you modify the program**, users interacting with your modified
version over a network must be offered its corresponding source.

- **Unmodified upstream, run as infrastructure** — an AGPL database, IdP or broker your app talks
  to over a socket — is the low-risk class. There is no modified version, and upstream's source is
  already public. This is a legitimate architecture, not a policy violation.
- **AGPL code inside your application** is the high-risk class. Link it in and your application is
  part of the covered work, so every network user of your service can demand *your* source under
  AGPL. That is the case blanket bans are aimed at.
- **"Modified" in practice** covers more than patching upstream: your own plugin, module or
  extension compiled into the program is a modification. Configuration, deployment manifests and
  code that only talks to it over a documented protocol are not.
- **Why companies blanket-ban it**: policy is cheaper than case-by-case review, and the downside
  is catastrophic rather than expensive. Record the ban as a `C-` row if a customer or an internal
  policy imposes it; do not invent it as a technical fact.
- **Typical mistakes** the transitive AGPL dependency nobody noticed — a small library four levels
  down the tree, pulled into the same process as your service; treating a vendor's AGPL-licensed
  SDK as safe because "we only call it"; assuming an AGPL component makes the whole solution
  unsellable when it is actually a separate process you never modified.

## Source-available — not open source

None of these is OSI-approved, and all of them permit far more than teams assume. The pattern is
the same: you may self-host for your own products; you may not resell the thing itself.

| License | You may | You may not | Ends when |
|---|---|---|---|
| **BSL 1.1** | copy, modify, redistribute, non-production use — *plus whatever the Additional Use Grant says*; vendors' grants typically allow all production use except a competing hosted/embedded offering | anything outside that grant without a commercial licence | per version, at the Change Date (max 4 years from release) it becomes the stated Change License, which must be GPL-2.0-compatible |
| **SSPL v1** | everything GPL-3.0 allows, including unlimited internal and commercial self-hosting | offer the program's functionality to third parties as a service without publishing the *entire* service stack's source under SSPL — management, UI, APIs, monitoring, backup, hosting | never |
| **Elastic License 2.0** | use, copy, modify, distribute, embed | provide it to third parties as a hosted or managed service exposing a substantial part of its functionality; circumvent licence-key functionality; remove notices | never |
| **FSL 1.1** | anything that is not a Competing Use — internal use, production, consulting, redistribution | make it available commercially as a substitute for the producer's own offering, or with substantially the same functionality | per version, 2 years after release it becomes Apache-2.0 or MIT |
| **Commons Clause** | whatever the underlying licence grants, minus selling | sell, host for a fee, or charge for support where the value derives substantially from the software | never |

- **BSL's parameters are the license.** Two BSL products are two different licenses — read the
  Additional Use Grant and the Change Date in that repo's own `LICENSE` header, never a summary.
- **Fair Source** is the umbrella term (FSL, BSL and similar): source readable, use with
  restrictions protecting the vendor's business, and delayed open-source publication. It is a
  category, not a license — cite the actual license.
- **Where this actually decides things**: modern infrastructure. For a company self-hosting
  Terraform, Vault, Elasticsearch or Redis Enterprise features to build its own product, the
  answer to "can we use it for free" is normally yes. It flips to no the moment the product *is*
  that component offered to customers.
- **Typical mistakes** blocking a BSL component in a policy written for open source, and paying
  for a licence the Additional Use Grant already covered; the reverse — shipping a managed service
  on ELv2 or BSL; assuming a source-available component's Change Date rescues you now (it applies
  per version, so today's release converts years from today).

## License change as an architectural driver

The last decade's pattern: single-vendor infrastructure relicenses from open source to
source-available, and a foundation-hosted fork appears within weeks.

| Component | Change | Fork and home |
|---|---|---|
| Elasticsearch | Apache-2.0 → SSPL + ELv2 (2021); AGPL-3.0 added back as an option (2024) | OpenSearch, Apache-2.0, Linux Foundation |
| Terraform | MPL-2.0 → BUSL-1.1 (2023) | OpenTofu, Linux Foundation |
| Vault | MPL-2.0 → BUSL-1.1 (2023) | OpenBao, MPL-2.0, Linux Foundation |
| Redis | BSD → SSPL + RSALv2 (2024); AGPL-3.0 added as an option (2025) | Valkey, BSD, Linux Foundation |

What it means for a choice you are making now:

- **A foundation home (CNCF, Linux Foundation, Apache) is a longevity property**, and it belongs
  in the recommendation next to features and operability. Copyright spread across many
  contributors cannot be relicensed unilaterally.
- **A single vendor plus a CLA that assigns broad rights is relicensing power.** Not a reason to
  refuse — a reason to know the fork landscape before committing, and to record the exposure.
- **Pin and plan.** A license change applies to future versions; the version you have keeps its
  terms. That buys months, not years — the exit is stopping upgrades, and security patches end it.
- **Record it**: a component whose licence could change under you is an `07-risks.md` row with the
  named fork as its mitigation, and the ADR that chose it says which fork we would move to.

## Hygiene

- **Declare licenses machine-readably**: an SPDX identifier in the package manifest of everything
  we publish, and SPDX ids (not prose names) wherever a license is recorded in the docs.
- **Scan in CI as a policy decision, not a tool choice**: an allowlist that passes silently, a
  review list that requires a named approver, a blocklist that fails the build — decided with the
  human and recorded as a `C-` row plus an ADR. Scan transitive dependencies; that is where the
  surprises live.
- **Dual- and multi-licensed components**: you accept one license, and which one is a decision.
  Write it in the ADR — "Redis 8 taken under AGPL-3.0, unmodified, run as a separate process" is
  a complete record; "Redis is open source" is not.
- **CLA vs DCO** on the upstream project: a CLA grants the vendor rights to relicense your
  contributions and everyone else's, a DCO only certifies provenance — read a CLA as a signal of
  who can change the terms later.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the component with the fewest live
questions: a permissive or weak-copyleft license, a foundation home, and no AGPL or
source-available code inside our own process. Note the trigger that would change the answer — "we
start shipping an on-prem build", "we resell this capability as a service" — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human with the licence consequence for each: what it obliges us to do
   now, what it forbids in a future we can foresee (shipping on-prem, offering it as a service),
   and what replacing the component would cost.
2. Give one recommendation with its driver. The human decides. Anything that turns on a legal
   judgment — combination vs aggregation, whether an offering competes — is named as such and
   routed to a lawyer, not answered here.
3. Write the accepted choice as an ADR under `docs/adr/`, naming the license by SPDX id, the
   version taken under it for a multi-licensed component, and the rejected alternatives with the
   reason each lost.
4. Every obligation the license puts on us becomes a `02-constraints.md` row with kind `legal` and
   the license as its source — attribution in the distribution, source offer on request, no
   managed-service offering. A constraint with no consequence stated is not finished.
5. Relicensing exposure and any accepted obligation we are not yet meeting become `07-risks.md`
   rows with an owner and an action. Anything the human leaves open is a `TODO(question)` per
   `templates.md`.

## The payoff table

Answers assume you take the component as published and do not buy a commercial license.

| License | Use in production, self-hosted | Modify | Embed in a distributed product | Offer as a service to others | Reach into our code |
|---|---|---|---|---|---|
| MIT, BSD-2/3 | yes | yes, keep private | yes — keep the copyright notice | yes | none |
| Apache-2.0 | yes | yes, keep private | yes — notice, changed-file statement, NOTICE forwarded | yes | none |
| MPL-2.0 | yes | yes; changed MPL **files** published on distribution | yes — link statically, ship your code under your terms | yes | the MPL files only |
| LGPL-2.1/3.0 | yes | yes; changed **library** published on distribution | yes if the user can relink — dynamic linking is the clean path | yes | the library only |
| GPL-2.0/3.0 | yes, unconditional | yes, private while you do not distribute | no in practice — the whole work becomes GPL | yes | none while nothing is shipped; total if it is |
| AGPL-3.0 | yes | yes, but a modified version served over a network must offer its source | no in practice | depends: unmodified separate process, yes; linked into your app, only by publishing your source | none if unmodified and out-of-process; total if linked in |
| BSL 1.1 | depends on the Additional Use Grant — usually yes | yes | depends on the grant; embedding to compete is the usual exclusion | no, unless the grant allows it | none |
| SSPL v1 | yes | yes | yes | no, unless you publish the whole service stack under SSPL | none until you serve it |
| Elastic License 2.0 | yes | yes, except licence-key functionality | yes — notices intact | no | none |
| FSL 1.1 | yes | yes | yes, if not a Competing Use | no while it competes with the producer's offering | none |
| Commons Clause | yes | yes | yes, if you are not selling the software's own value | no | per the underlying licence |
