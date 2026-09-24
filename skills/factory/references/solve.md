# factory solve

One problem end to end. You are the coordinator, not the executor: gates and verification are yours, every
line of code comes from a subagent in its own worktree, and a subagent's report is a claim you rerun.

## The loop

Run `<plugin-root>/bin/solve-next.sh <T-NNN>`, do what it prints, verify its `Completion:` line yourself,
repeat until step 16. It reads the state, so its step is the one the state asks for.

## The worktree rule

`<plugin-root>/bin/worktree-add.sh <task-id>` creates the worktree and branch for the parent and every block
and writes `branch:` through `state-report.sh --task <id> --branch`. No product command runs in the user's clone, and no
worktree means no spawn.

## The gates you own

- **Triage.** `<plugin-root>/bin/investigate.sh <repo-dir> <symbol>` gathers the recon a `factory-investigator`
  judges into the parent's `## Context`.
- **Grill.** `<plugin-root>/bin/plan-lint.sh <plan-ready.md>` comes back clean before the cut.
- **Cut.** `<plugin-root>/bin/dag-check.sh <parent-id>` exits 0 over the block drafts, bodies from
  `<plugin-root>/bin/task-template.sh <kind>`. When one block builds a mechanism another block's document must
  reach, both acceptances name it. A recut needs a fresh cut-check verdict, which `task-new.sh --parent` demands.
- **Spawn.** `<plugin-root>/bin/spawn-plan.sh <T-NNN>` prints the agent, the model and the brief per block of
  the wave, `<plugin-root>/bin/block-brief.sh <block-id> --agent <name> --phase <phase>` prints the whole
  brief and `<plugin-root>/bin/model-for.sh` picks the model. The brief is the subagent's whole input: it
  binds to `_shared/block-subagent.md`, never to the session contract. A green block, or a yellow one at
  complexity low, runs as one implement agent with red-first TDD inside: its first commit is the red tests
  alone, and you check that commit out and run them red yourself before you arm `phase: implement`. Every
  other block gets a tests phase first. A skeleton block declares the new surface and leaves an existing body alone; its gate is
  `arch-build`.
  With `spawn: herdr` in `<state>/factory.yml`, `<plugin-root>/bin/session-monitor.sh --parent <T-NNN>` runs
  that plan as one interactive session per block instead of one subagent per block
  (`<plugin-root>/skills/herdr/SKILL.md`). Their reports come back through the state repo, not to you, so
  read them with `<plugin-root>/bin/factory-list.sh` and rerun every proving command yourself.
- **Tests.** Rerun the red tests yourself with the toolset's `test-filter` over the files the handoff names,
  each failing for the reason it states, paste the `## Handoff` into the block's progress file, then arm the
  lock with `state-report.sh --task <block-id> --set-phase implement`.
- **Verify.** `<plugin-root>/bin/block-verify.sh <block-id>` is green before the MR, and `## Evidence` is
  written by you, never by a subagent. A block red twice is `failed`: spawn nothing new and ask the human
  through `_shared/blocked-question.md`.
- **Acceptance.** The parent's `## Acceptance` rerun verbatim over the session branch, then `crap`, `format`
  and `arch-build`.
- **Duplication.** `git diff origin/<base>...<branch> > <harness>/review.diff`, then
  `<plugin-root>/bin/dup-check.sh <harness>/review.diff <worktree>`, never a task id; its output verbatim under
  `## Duplication`; the reviewer judges the candidates, nobody is spawned per candidate.
- **Review.** A `factory-reviewer` over the whole diff, its verdict in the progress file, then
  `<plugin-root>/bin/mr-open.sh <T-NNN>` for the parent. `changes needed` gets one fix block and one more
  review.
- **Knowledge review.** Once per session on the parent, never per block.

## Stacked MRs

Every block is one reviewable functionality with its own MR (ADR-0057), cut from the last block it depends on. `<plugin-root>/bin/block-merge.sh <block-id> --verify` proves the merge into the session branch
and commits nothing; `<plugin-root>/bin/block-mr.sh <block-id>` opens the block MR into that base and records
it with `state-report.sh --task <block-id> --mr-url`. A conflict is a cut defect: rebase the later block and run it again.

`<plugin-root>/bin/mr-watch.sh <T-NNN>` prints one line per forge event, armed through the Monitor tool; on
`merged` it retargets the children and sets the block done. On `changes-requested` set the block
`changes_requested`, spawn one implement subagent with the threads as acceptance, then
`<plugin-root>/bin/restack.sh <T-NNN> <block-id>`, whose exit 3 is a question for the human. On `new-comments`
read the threads with `mr-watch.sh <T-NNN> --comments <block-id>` first and answer each one on its own terms: a
thread asking for a code change is that same fix round on the block branch, a question is answered on the MR by
hand, since `forge.sh` only reads, and a thread asking for work outside the block's acceptance is a new draft
block with `depends_on` on that block, never a fix round: an `architect-review` cut-check over that one block,
then `<plugin-root>/bin/task-new.sh --parent`, and the verdict removed afterwards as decompose does.

A block waiting on its open MR does not hold the stack: the later blocks are worked on past it, and only when
every remaining block is a `review` with an `mr_url` does step 11 list the open MRs as `<block> <mr-url> ->
<base>` and ask the human to review and merge them. The session may end while the MRs wait.

## Identity and refusals

`owner:` is the `factory@<host>:<session_id>` of the Session identity line
`<plugin-root>/bin/session-start.sh` prints. `<plugin-root>/bin/policy-guard.sh` carries the fix in its deny
message.

## The monitor lane

`factory herd <T-NNN>` runs this same flow with every work step as an interactive session in a herdr tab
instead of a subagent, and this session only dispatching, watching and gating: `references/herd.md`.

## The quick lane

A green task of low complexity, or an explicit `--quick`: `references/solve-quick.md`.
