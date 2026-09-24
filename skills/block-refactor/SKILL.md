---
name: block-refactor
description: Refactoring in a standalone session: green baseline, small steps against unchanged tests, WIP push, self-reporting progress and status into the state repo. Started with the path to the task file.
---

# block-refactor

Plugin root: `${CLAUDE_PLUGIN_ROOT}`.

Change the structure of the code as the task describes, not its behaviour, and finish in status `review`. The argument is the task file's absolute path in the state
clone; read all of it, it is a self-contained spec (P4).

## Session contract

Spawned as a block subagent by a `factory solve` coordinator, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md`
replaces this section and steps 1, 8 and 9 below; the brief says which you are. As a session, read
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/session-contract.md` before step 1 and follow it, with the files
it names (`rules.md`, `progress-and-push.md`, `knowledge-review.md`, `delegation.md`). `mr_url` set in the
frontmatter means `${CLAUDE_PLUGIN_ROOT}/skills/_shared/refinement.md` (ADR-0031) replaces the procedure.

Deltas: Toolset commands (ADR-0039) here are `build`, `test`, `test-filter <expr>`, `format`,
`find-refs <symbol>`, `hotspots`, `arch-build`. `worker-explorer` fans out for references and hotspots;
never delegate a test-file edit.

**Do not edit the tests.** Behaviour does not change, so the unchanged suite is the only thing proving it.
The one permitted test change is following a rename through; a changed expectation is a behaviour change and
belongs in `blocked`.

## Procedure

1. **Claim the task, then snapshot.** The claim is one command, and the exact one, so nobody has to read
   `state-report.sh` to find it:

   ```sh
   sh ${CLAUDE_PLUGIN_ROOT}/bin/state-report.sh --task <id> --set-status in_progress --owner factory@<host>:<session_id>
   ```

   `factory@<host>:<session_id>` is the owner string of your SessionStart identity line, verbatim; the
   owner-based Stop lookup finds this task only under it. The command is the same whether the task is still
   `ready` or was already claimed `in_progress` for you under a `pending-<id>` owner. Then write the progress
   snapshot and run `state-report.sh --task <id>` again: done when the first heartbeat is in.
2. **Green baseline.** Run toolset `test` before touching anything and record the result. Already red means
   the refactor has nothing to lean on: `blocked`.
3. Pick the targets with toolset `hotspots` when the repo binds it, worst-ranked first and only inside the
   task's scope; a high rank outside it never widens it (ADR-0014).
4. Refactor in small steps, each in the stack's idiom
   (`${CLAUDE_PLUGIN_ROOT}/skills/modern-idioms/SKILL.md`), the whole suite green after each, then a WIP
   push. A step the suite cannot verify is too big.
5. Change the public API only where `# Goal` says so.
6. Run the command from `## Acceptance` verbatim, never edited.
7. **Architecture model** (issue #297), the contract's `## Architecture model`, only if the diff changed
   the architecture: a moved module, split component or reversed dependency did, rearranging inside one
   component did not.
8. Knowledge review, then deliver per the contract's `## Output`.
9. Self-report `review`.

Do not tidy the surroundings; the diff holds only what follows from `# Goal`.

## Implement phase (ADR-0030)

A progress file with a `## Handoff` section means the tests phase ran before you: confirm its baseline and
characterization tests by running the suite, then carry on at step 3. **Do not edit the tests** covers them
too. The Stop hook refuses a session that touched a test file with no `## Test deviations` line for it: one
line per file, the file and the rename it followed through.

## As a block subagent

Steps 2 to 7, then the report of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md`. A WIP push is a
commit on the block branch. A refactor block hands over **no new tests**.
