# factory solve

One problem end to end, in this one session: you hand over a task and the flow runs triage, grill, plan-check,
decompose, the blocks and the MR without being asked for the next step. You are the coordinator, not the
executor: gates and verification are yours, every line of code comes from a subagent in its own worktree, and a
subagent's report is a claim you rerun.

## Start

`<owner>` below is the owner string `factory@<host>:<session_id>` of the Session identity line, and `<state>` is
`$WORK_DIR/state`. The factory needs a forge: an `origin` on GitHub or GitLab and `gh` or `glab` logged in, since
every block and the task end in an MR.

`factory solve <the task in words> [--repo <key>]` starts a task:

1. **Intake.** The repository is `--repo`, else the registered clone of the cwd (the `Factory context for repo
   <key>` line of the session start), else the only key in `<state>/repos.yml`; ask through `_shared/ask.md`
   only when two or more fit. Write `<plugin-root>/bin/task-template.sh task` to `/tmp/factory-intake-<slug>.md`
   and fill it in:
   - frontmatter: `repo: <key>`; `branch: feat/<new-id>-<slug>` with `<slug>` a few kebab-case words of the goal
     (task-new.sh puts the id in); a first `tier`, `archetype` and `complexity` per `_shared/tiers.md`, which
     triage revisits; `issue:` the forge issue URL the human named, else `null`; `created:` today.
   - `# Goal`: a Conventional Commits MR title of the change.
   - `## Context`: the task in your own words. `## Internal`: the task as the human gave it, verbatim, and the
     tier and complexity lines; the `triage:`, forge issue, title, milestone, comments and attachments lines go
     unless a forge issue is the source, and so does `## Issue update`.
   - `## Acceptance`: the runnable command the task names, else the `test` binding of
     `<state>/repos/<key>/toolset.md`. `## Out of scope`: what the task excludes, or `none`.
   Completion: the draft has no `<...>` placeholder left.
2. **Create.** `<plugin-root>/bin/task-new.sh --repo <key> --state <state> --file <draft>`. Completion: it printed
   the id, and that id is the `<T-id>` of the loop.
3. **Lane.** A task at `tier: green` and `complexity: low` goes on in the quick lane (`references/solve-quick.md`),
   any other in the loop.

`factory solve <T-id>` resumes a task the state already has: first reclaim it and every block that is not done or
closed, `<plugin-root>/bin/state-report.sh --task <id> --owner <owner> --no-status`, then the loop.

## The loop

Run `<plugin-root>/bin/solve-next.sh <T-id>`, do what it prints, verify its `Completion:` line yourself, and run
it again, until step 16. It reads the state, so its step is the one the state asks for, and every step opens
with `state-push.sh`, which carries the local state commits to the state root. Do not stop between steps and do
not ask whether to go on: the flow stops only at the human's gates.

| gate | step | what the human does |
|---|---|---|
| a related issue | 3 | yes or no to linking or creating the forge issue (`_shared/investigate.md`) |
| grill rounds | 4 | answers each round (`skills/grill/SKILL.md`) |
| spec-critic | 6 | yes or no to the edits of a red block (`skills/decompose/SKILL.md`) |
| plan approval | 9 | one confirm over the parent and its blocks (`references/approve.md`) |
| a blocked or failed block | 11 | picks an option of its `## Question` (`_shared/blocked-question.md`) |
| the task MR | 14 | reviews and merges it on the forge |

Step 3, triage, runs `_shared/investigate.md` and then decides `archetype`, `tier` and `complexity` again from
what it found, one sentence of why each in `## Context`.

## After the task MR

Step 16 ends the loop with the task MR open and its URL in the parent's `mr_url`. Arm
`<plugin-root>/bin/mr-watch.sh <T-id> --finish --interval 300` through the Monitor tool, description
`mr-watch.sh <T-id>`, `timeout_ms` at its maximum, and arm it again whenever it expires (the Stop hook
`rearm-check.sh` reminds you). `<T-id> merged` is the human's merge, and the watcher then runs
`references/done.md` itself: `task-done.sh` and `state-push.sh`, with no ask. `<T-id> done` ends the Monitor:
report the task done to the user with every `<T-id> skipped:` line that followed it. `<T-id> finish-failed
<reason>` is retried on the next pass; show the reason to the user. A `changes-requested` or `new-comments` line on the
task MR is one more round:

1. The fix as a new block, written the way Block MRs below write a block for work outside a block's acceptance
   (cut-check, `task-new.sh --parent`), approved with the human's yes (`references/approve.md`), then worked
   through step 11 like any block.
2. Once it is merged, remove `## Evidence`, `## Duplication` and `## Review` from the parent's progress file and
   report it (`state-report.sh --task <T-id> --no-status`), so solve-next.sh runs steps 12 to 13 again.
3. `<plugin-root>/bin/mr-open.sh <T-id>` updates the task MR's description with the new block.

The session may end while the MR waits: the next session start runs `<plugin-root>/bin/review-sweep.sh`, which
finishes every task whose task MR was merged meanwhile, and `factory done <T-id>` still closes one by hand.

## The worktree rule

`<plugin-root>/bin/worktree-add.sh <task-id>` creates the worktree and branch for the parent and every block
and writes `branch:` through `state-report.sh --task <id> --branch`. No product command runs in the user's clone, and no
worktree means no spawn.

## The gates you own

- **Triage.** `<plugin-root>/bin/investigate.sh <repo-dir> <symbol>` gathers the recon a `triage-analyst`
  judges into the parent's `## Context`.
- **Grill.** `<plugin-root>/bin/plan-lint.sh <plan-ready.md>` comes back clean before the cut.
- **Cut.** `<plugin-root>/bin/dag-check.sh <parent-id>` exits 0 over the block drafts, bodies from
  `<plugin-root>/bin/task-template.sh <kind>`. When one block builds a mechanism another block's document must
  reach, both acceptances name it. A recut needs a fresh cut-check verdict, which `task-new.sh --parent` demands.
- **Spawn.** `<plugin-root>/bin/spawn-plan.sh <T-id>` prints the agent, the model and the brief per block of
  the wave, `<plugin-root>/bin/block-brief.sh <block-id> --agent <name> --phase <phase>` prints the whole
  brief and `<plugin-root>/bin/model-for.sh` picks the model. The brief is the subagent's whole input: it
  binds to `_shared/block-subagent.md`, never to the session contract. A green block, or a yellow one at
  complexity low, runs as one implement agent with red-first TDD inside: its first commit is the red tests
  alone, and you check that commit out and run them red yourself before you arm `phase: implement`. Every
  other block gets a tests phase first. A skeleton block declares the new surface and leaves an existing body alone; its gate is
  `arch-build`.
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
- **Review.** A `code-reviewer` over the whole diff and the `architecture-auditor` once on the whole task diff
  against the base, their verdicts in the progress file, then `<plugin-root>/bin/mr-open.sh <T-id>` for the
  parent: the task MR into the base branch with the normal pipeline and a `## Blocks` list of every block MR
  with its link and risk. `changes needed` gets one fix block and one more review. Step 14 is the human's
  review and merge of that MR.
- **Knowledge review.** Once per session on the parent, never per block.

## Block MRs

Every block is one reviewable functionality with its own MR (ADR-0057) into the task's work branch
`feat/<T-id>-<slug>`. `worktree-add.sh <block-id>` cuts a block from the work branch when its wave starts and
records `base:` as that branch; every block of a wave is merged before the next wave starts, so no block needs
another block's branch and nothing is stacked.

1. After the tests and the implement phase, `<plugin-root>/bin/block-verify.sh <block-id>`, then a
   `code-reviewer` and an `architecture-auditor` on the block diff: you save the reviewer's final message as
   `.harness/<block-id>/review.md` (it has no Write tool), the auditor writes `.harness/<block-id>/arch.md` or
   answers `skipped` without `docs/architecture/`.
2. `<plugin-root>/bin/block-mr.sh <block-id>` builds the description from the two reports (what changed, the
   risk with its reasons, the verification that ran, the review verdict), opens the MR into the work branch with
   the pipeline skipped by the repo's MR class, and records it with `state-report.sh --task <block-id>
   --mr-url`.
3. `<plugin-root>/bin/block-mr-merge.sh <block-id>` merges it, pulls the parent worktree `--ff-only`, removes
   the block's worktree and sets the block done: step 11's automatic merges. It needs the block in `review` and
   refuses a `changes needed` verdict (exit 1). A high risk does not stop it: the MR, the risk and the review
   are recorded as `## Merged` in the block's progress file. Class C prints `<block> auto-merge
   <url>`; rerun it once the forge merged.

`<plugin-root>/bin/block-merge.sh <block-id> --verify` still proves a merge without committing. A task whose
blocks were stacked before this flow keeps its stack: each MR into the block it depends on, a conflict a cut
defect (rebase the later block and run it again).

`<plugin-root>/bin/mr-watch.sh <T-id>` prints one line per forge event, armed through the Monitor tool; on
`merged` it sets the block done and, in a legacy stack, retargets the children. On `changes-requested` set the
block `changes_requested`, spawn one implement subagent with the threads as acceptance, then, in a legacy stack
only, `<plugin-root>/bin/restack.sh <T-id> <block-id>`, whose exit 3 is a question for the human. On `new-comments`
read the threads with `mr-watch.sh <T-id> --comments <block-id>` first and answer each one on its own terms: a
thread asking for a code change is that same fix round on the block branch, a question is answered on the MR by
hand, since `forge.sh` only reads, and a thread asking for work outside the block's acceptance is a new draft
block with `depends_on` on that block, never a fix round: an `architect-review` cut-check over that one block,
then `<plugin-root>/bin/task-new.sh --parent`, and the verdict removed afterwards as decompose does.

The task MR is the one the human reviews and merges (step 14); the session may end while it waits.

## Identity and refusals

`owner:` is the `factory@<host>:<session_id>` of the Session identity line
`<plugin-root>/bin/session-start.sh` prints. `<plugin-root>/bin/policy-guard.sh` carries the fix in its deny
message.

## The herd lane

`factory herd <T-id>` runs this same flow with every step that writes as an interactive session in a herdr tab,
and this session only dispatching, watching and gating: `references/herd.md`.

## The quick lane

Step 3 of Start, a triage that ends at `tier: green` and `complexity: low`, or an explicit `--quick`:
`references/solve-quick.md`.
