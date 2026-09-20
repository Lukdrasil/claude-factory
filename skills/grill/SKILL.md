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
round, numbered, each with your recommended answer, then wait.

```
❓ **Q1** - **<question title>**: <question body, possibly several paragraphs, with the choices>

➡️ <your recommended answer>

---

❓ **Q2** - ...
```

Every answer reshapes the tree, pushing the frontier outward. Recompute it and ask the next round. A question whose answer depends on another question
still open in this round belongs to a _later_ round.

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

## Steps

1. Run the interview loop, keeping the gap ledger of `references/ledger.md`, which also holds the musts the
   loop has to ask about, and close every row, dry run included.
2. Hold the design round of `references/design-round.md` and get the sketch approved as written.
3. Write the proposals and the plan, lint it with `${CLAUDE_PLUGIN_ROOT}/bin/plan-lint.sh` and run plan-check, per
   `references/output.md`.

**Done when** `plan-ready.md` exists in the state repo, `${CLAUDE_PLUGIN_ROOT}/bin/plan-lint.sh` passes over it, plan-check left a
verdict file matching its hash, and the human has the summary and the pointer to decompose. With a gap still
open, or a design the human has not approved as written, write no `plan-ready.md` and say so.
