---
name: block-review
description: A review task in a worker session: judging a branch or MR diff against acceptance and writing a report into the progress file. Started by the controller after dispatch with the path to the task file.
---

# block-review

Judge the change the task names and finish in status `review` with a report in the progress file. **No
code change, no MR of your own**: a fix is a follow-up task (ADR-0014).

## Preconditions

- cwd is the clone under review, **read-only**; you write only `../state/repos/<key>/progress/<id>.md`.
- The toolset section of `CLAUDE.md` (ADR-0039) binds `build`, `test`, `test-filter <expr>`,
  `find-refs <symbol>`. One it lacks is a note under `### Verified`, not a failure.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/rules.md` and
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/delegation.md` hold; a subagent never writes a finding.

## Procedure

1. **Claim the task, then snapshot.** The claim is one command, and the exact one, so nobody has to read
   `state-report.sh` to find it:

   ```sh
   sh ${CLAUDE_PLUGIN_ROOT}/bin/state-report.sh --task <id> --set-status in_progress --owner factory@<host>:<session_id>
   ```

   `factory@<host>:<session_id>` is the owner string of your SessionStart identity line, verbatim; the
   owner-based Stop lookup finds this task only under it. The command is the same whether the task is still
   `ready` or was already claimed `in_progress` for you under a `pending-<id>` owner. Then write the progress
   snapshot and run `state-report.sh --task <id>` again: that heartbeat is your only liveness signal, so repeat it at every milestone and
   before a long run (ADR-0009).
2. `git fetch origin && git checkout <branch>`; the diff is `git diff origin/<base>...HEAD`, `<base>` being
   `default_branch` for `<key>` in `../state/repos.yml`. Read the MR with
   `${CLAUDE_PLUGIN_ROOT}/bin/forge.sh mr <mr_url>`; a description not matching it is a finding.
3. Judge against the source task's `## Acceptance` and `## Out of scope`, never your own. A `- mr: <url>`
   source with no task runs `${CLAUDE_PLUGIN_ROOT}/skills/mr-review/SKILL.md` instead of steps 2 to 5.
4. Go through the diff file by file along seven axes, in this order, detail in
   `${CLAUDE_PLUGIN_ROOT}/skills/block-review/references/axes.md`:
   - **acceptance**: does it do what the task asked, verified by a test?
   - **correctness**: missing cases, silent failure, broken invariants.
   - **security**: external input, authorization, secrets in the repo.
   - **test quality**: hollow assertions, mocks testing mocks, the test files diffed against the tests
     phase.
   - **docs**: public behaviour or architecture that a doc or the architecture model describes while it
     stayed unchanged.
   - **craft**: idioms and comment lines, each hit a suggestion.
   - **scope**: something from `## Out of scope` in the diff, or a missing piece of the assignment.

   The source of truth is the **code**, the MR description a supplement.
5. Every finding carries a `path/file.ext:line` or a SHA and says what to do. Unsupported is no finding;
   one without a fix is an opinion.
6. Run your own `## Acceptance`, never edited, under `${CLAUDE_PLUGIN_ROOT}/skills/_shared/test-budget.md`.
7. Append the report to the progress file, **under 400 words**, a clean check silent:

   ```markdown
   ## Report

   ### Verdict
   `ok` | `changes needed` - one sentence why.

   ### Findings
   - **[blocking|suggestion]** `path/file.ext:line` - what is wrong and what to do about it.

   ### Verified
   - `<command>` -> exit `<n>`, `<the key output line>`
   ```

8. Knowledge review per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/knowledge-review.md`.
9. Self-report per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/progress-and-push.md`, `mr_url` untouched. You
   neither create nor merge an MR (P5).



| status | when |
|---|---|
| `review` | acceptance is met and the report exists, **even on a `changes needed` verdict** |
| `blocked` | you need a human decision; question per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/blocked-question.md` |
| `failed` | acceptance unreachable; `state-report.sh --task <id> --attempts "<N>, <model>, <why>"` |

Never write `done`, `ready`, `in_progress` or `stalled`.
