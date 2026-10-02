---
name: grill
description: The spec interview that ends in plan-ready.md, run in rounds the human answers, with a typed gap ledger, acceptance as a runnable command, an approved program design, and task proposals. Use at the start of a new spec and as the grill step of factory solve.
---

# grill

You ask, the human decides. You implement nothing and create no task: a grill ends with `plan-ready.md`,
and decompose is the next step.

## Interview loop

Interview the human relentlessly until you reach a shared understanding. Map it as a **design tree**: every
decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled: the
questions you can ask _now_ without guessing at answers you have not heard yet. Ask the whole frontier in one
round, numbered, each with lettered options and your recommendation, then wait. Every round goes through
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/ask.md`.

```
❓ **Q3** - **<question title>** (after Q1, Q2): <question body: what hangs on it, possibly several paragraphs>
  **A** <option>
  **B** <option>

➡️ **A**: <one paragraph why, naming the trade-off>

---

❓ **Q4** - ...
```

Two to four options; a question with no sensible options has none and the recommendation is a sentence. The
`(after ...)` names the questions it depends on and becomes the row's `deps` in the ledger; a root question
has none. The human answers in shorthand, several in one message one per line: `Q3 A`, `Q3 ok` (the recommendation),
free text, `Q4 defer`, `Q2 reopen`. `explore Q3` asks you for a table, one row per option, two to four pros
and cons each, specific to this repo and as honest about the recommended option's cons; if writing it changes
your mind, say so and give the new recommendation. `Q3 more` asks for more detail before the human decides:
what changes in the code under each option, what the recommendation assumes, and what would change it. It is
not an answer; the question stays open.

After every answered round, first write the grill file, `<state>/repos/<repo-key>/plans/<slug>-grill.md`
(see `## The grill file`); the round is not finished until it is on disk. Every answer reshapes the tree,
pushing the frontier outward. Recompute it and ask the next round. A question whose answer depends on another question
still open in this round belongs to a _later_ round. When an answer changes the recommendation of a question
already asked and still open, ask it again in the next round marked `(updated)`.

Finding _facts_ is your job, never the human's. When a frontier question needs a fact from the environment,
dispatch a sub-agent for it instead of asking. Do not block: a running exploration is an unsettled
prerequisite, so only the questions downstream of it wait. The _decisions_ are the human's.

The interview is done when the frontier is empty: every branch visited, nothing silently assumed.

## Preconditions

Checked before the first interview question, so an unfindable root costs no interview.

- `<state>` resolves. Ascend from cwd: a directory holding `repos.yml` *is* the state clone, one holding
  `state/repos.yml` makes `<state>` that `state/`; otherwise step to the parent, stopping at the filesystem
  root or the first unreadable directory. A brief naming the clone by absolute path overrides the walk.
  Finding nothing, stop and say where you walked.
- `<repo-key>` is in `<state>/repos.yml`, or stop: a plan with no registry entry cannot be decomposed.
- A spec from the human: a sentence, an issue, a triage report. If it is missing, ask.
- The product clone is read-only throughout.

## The grill file

The interview survives a dead session. After every round the human answers, write the plan as it stands to
`<state>/repos/<repo-key>/plans/<slug>-grill.md`: the `plan-ready` skeleton with every ledger row, open ones
included with their `deps`, the terms and the decisions settled so far. It is a working file, not committed.
`<slug>` is the one `references/output.md` gives the plan: two to four words from the spec, lowercase and
hyphenated.

Before the first question, look in that folder for a `*-grill.md` whose `task:` is this grill's task; with
`task: none`, list the ones there and ask which, if any. Found, it is a resume: say in one line which rows
are closed and which are open, recompute the frontier from the open rows, and continue. Never ask a closed
row again.

## Steps

1. Run the interview loop, keeping the gap ledger of
   `references/ledger.md`, which also holds the musts the loop has to ask about, and close every row, dry run
   included. Every answered round completes with the grill file `<slug>-grill.md` written.
2. Hold the UI round of `references/ui-round.md` when the change reaches a surface a person sees: the human
   chooses a mockup with variants to pick from, or leaves the look to the agent. Then the design round of
   `references/design-round.md`, and get the sketch approved as written.
3. Hold the proposals round of `references/output.md`: the cut with every proposal's steps, approved as
   written.
4. Write the proposals and the plan (its frontmatter carries `task:`), lint it with `${CLAUDE_PLUGIN_ROOT}/bin/plan-lint.sh` and run plan-check, per
   `references/output.md`.

**Done when** `plan-ready.md` exists in the state repo, `${CLAUDE_PLUGIN_ROOT}/bin/plan-lint.sh` passes over it, plan-check left a
verdict file matching its hash, and the human has the summary and the pointer to decompose. With a gap still
open, or a design the human has not approved as written, write no `plan-ready.md` and say so.

## Auto mode

`/claude-factory:grill <task file> --auto`, the grill step of `factory auto`, or `--autonom`, the grill step
of `factory autonom` (`${CLAUDE_PLUGIN_ROOT}/skills/factory/references/auto.md`). The interview loop, the
ledger, the grill file, the design round, the proposals round and the plan are as above, with these deltas
and no other:

- **The spec** is the task's `## Solution` and the solution file or files it names in the state clone, read
  first; a mixed pick names both, and the human's words say what is taken from each. Their `## Open
  questions` seed the ledger, their `## Changes` and `## Tests` the design and the proposals. The human's
  words in `## Solution` are settled decisions, never asked again.
- **Nobody is asked by default.** Every round is still written, numbered questions with options and the
  recommendation, into the grill file; then the recommendation is the answer of every row, under
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-decision.md`. A question that file sends to the human goes
  through `_shared/ask.md` as a round of its own, and the questions that do not hang on it go on. The design
  round and the proposals round are approved by the same rule: the sketch and the cut as you would recommend
  them, re-sketched when the dry run finds a gap.
- **Tests in every proposal.** The `steps:` of every proposal that is not `research` name the tests that
  cover its functionality, one sub-bullet per test file, `test <path>: <what it proves>`, and the end-to-end
  test it needs, or a sub-bullet `no e2e`. A behaviour of the design with no test line is an open gap.
  `${CLAUDE_PLUGIN_ROOT}/bin/plan-lint.sh <plan> --auto` checks both and is the lint of step 4 here;
  `solve-next.sh` runs it again before plan-check and sends a plan that fails it back to this grill.
  `## Acceptance` stays one runnable command; the crap threshold is `block-verify.sh`'s gate and needs no
  acceptance line.
- **Plan-check with the same flag.** The plan-check of step 4 (`references/output.md`) runs as
  `architect-review plan-check <plan> --auto` or `--autonom`, the flag this grill got: its findings are edits
  and reruns under its `## Auto mode`, never a question to the human, and `overridden-by-human` is never
  written; a `misaligned` no edit clears is a stop the lane reports.
- **Every decision is recorded.** `## Decisions` holds each one, one line, `[locked]` where it passes the
  three gates of `references/ledger.md`, and a decision the human answered ends with `(human)`; its first
  line is the pick of step 4a, the solution chosen and by whom, `(human)` or `(analysed)`. The task MR carries
  every line of the section (`mr-open.sh --decisions`, the `[locked]` tag dropped).
- **The UI round is still asked** under `--auto`. A change that reaches a surface a person sees puts the
  question of `references/ui-round.md` to the human, mockup or agent, and the variant pick after a mockup;
  the fifth case of `_shared/auto-decision.md`.
- **`--autonom` asks nothing** but the third and fourth cases of that file (a destructive or outward-facing
  choice; a block whose every option fails): a question with no recommendation, the UI round and its variant
  included, is analysed and decided as its `## Autonomous` section says, the table in the grill file and the
  decision line ending with `(analysed)`.
- **Finishing** is the summary of `references/output.md` as a notice, no question in it.
