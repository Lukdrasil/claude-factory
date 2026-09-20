# factory solve

One problem end to end. You are the coordinator, not the executor: gates and verification are yours, every
line of code comes from a subagent in its own worktree, and a subagent's report is a claim you rerun.

## The loop

Run `<plugin-root>/bin/solve-next.sh <T-NNN>`, do what it prints, verify its `Completion:` line yourself,
repeat until step 16. It reads the state, so its step is the one the state asks for.

## The worktree rule

`<plugin-root>/bin/worktree-add.sh <task-id>` creates the worktree and branch for the parent and every block
and writes `branch:` through `state-report.sh --branch`. No product command runs in the user's clone, and no
worktree means no spawn.

## The gates you own

- **Triage.** `<plugin-root>/bin/investigate.sh <repo-dir> <symbol>` gathers the recon a `factory-investigator`
  judges into the parent's `## Context`.
- **Grill.** `<plugin-root>/bin/plan-lint.sh <plan-ready.md>` comes back clean before the cut.
- **Cut.** `<plugin-root>/bin/dag-check.sh <parent-id>` exits 0 over the block drafts, bodies from
  `<plugin-root>/bin/task-template.sh <kind>`. When one block builds a mechanism another block's document must
  reach, both acceptances name it. A recut needs a fresh cut-check verdict, which `architect-gate.sh` demands.
- **Spawn.** `<plugin-root>/bin/spawn-plan.sh <T-NNN>` prints the agent, the model and the brief per block of
  the wave, `<plugin-root>/bin/block-brief.sh <block-id> --agent <name>` prints the whole brief and
  `<plugin-root>/bin/model-for.sh` picks the model. A skeleton
  block declares the new surface and leaves an existing body alone; its gate is `arch-build`.
  With `spawn: herdr` in `<state>/factory.yml`, `<plugin-root>/bin/session-monitor.sh --parent <T-NNN>` runs
  that plan as one interactive session per block instead of one subagent per block
  (`<plugin-root>/skills/herdr/SKILL.md`). Their reports come back through the state repo, not to you, so
  read them with `<plugin-root>/bin/factory-list.sh` and rerun every proving command yourself.
- **Tests.** Rerun the red tests, then arm the lock with `state-report.sh --set-phase implement`.
- **Verify.** `<plugin-root>/bin/block-verify.sh <block-id>` is green before the MR, and `## Evidence` is
  written by you, never by a subagent. A block red twice is `failed`: spawn nothing new and ask the human
  through `_shared/blocked-question.md`.
- **Acceptance.** The parent's `## Acceptance` rerun verbatim over the session branch, then `crap`, `format`
  and `arch-build`.
- **Review.** A `factory-reviewer` over the whole diff, its verdict in the progress file, then
  `<plugin-root>/bin/mr-open.sh <T-NNN>` for the parent. `changes needed` gets one fix block and one more
  review.
- **Knowledge review.** Once per session on the parent, never per block.

## Stacked MRs

Every block is one reviewable functionality with its own MR (ADR-0057), cut from the last block it depends on. `<plugin-root>/bin/block-merge.sh <block-id> --verify` proves the merge into the session branch
and commits nothing; `<plugin-root>/bin/block-mr.sh <block-id>` opens the block MR into that base and records
it with `state-report.sh --mr-url`. A conflict is a cut defect: rebase the later block and run it again.

`<plugin-root>/bin/mr-watch.sh <T-NNN>` prints one line per forge event, armed through the Monitor tool; on
`merged` it retargets the children and sets the block done. On `changes-requested` set the block
`changes_requested`, spawn one implement subagent with the threads as acceptance, then
`<plugin-root>/bin/restack.sh <T-NNN> <block-id>`, whose exit 3 is a question for the human. The session may
end while the MRs wait.

## Identity and refusals

`owner:` is the `factory@<host>:<session_id>` of the Session identity line
`<plugin-root>/bin/session-start.sh` prints. `<plugin-root>/bin/policy-guard.sh` carries the fix in its deny
message.

## The quick lane

A green task of low complexity, or an explicit `--quick`: `references/solve-quick.md`.
