---
name: block-research
description: A research task in a worker session: reading without changing code, a report into research/, self-reporting into the state repo. Started by the controller with the task file path.
---

# block-research

Answer the question in the task and finish in status `review` with a report in the state repo. **No code
changes, no MR** (ADR-0016), except under the handoff below. The argument is the task file's path in the
state clone, read in full.

## Skill handoff

`## Context` naming `- skill: architecture-docs` hands the procedure to that skill, its
`## Task mode (no human)` delta included; the mechanics below stay. The policy-guard carve-out for `docs/**`
and `CONTEXT.md` applies only then.

## Preconditions

- cwd is the product repo clone, **read-only** except under the handoff. You write only
  `../state/repos/<key>/progress/<id>.md` and `../state/repos/<key>/research/<id>-<slug>.md`.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/rules.md`,
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/progress-and-push.md` and
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/delegation.md` hold; verify a subagent's citations before they enter
  the report.

## Procedure

1. **Claim the task, then snapshot.** The claim is one command, and the exact one, so nobody has to read
   `state-report.sh` to find it:

   ```sh
   sh ${CLAUDE_PLUGIN_ROOT}/bin/state-report.sh --task <id> --set-status in_progress --owner factory@<host>:<session_id>
   ```

   `factory@<host>:<session_id>` is the owner string of your SessionStart identity line, verbatim; the
   owner-based Stop lookup finds this task only under it. The command is the same whether the task is still
   `ready` or was already claimed `in_progress` for you under a `pending-<id>` owner. Then write the progress
   snapshot and run `state-report.sh --task <id>` again: that heartbeat is your only liveness signal, so repeat it after every answered
   sub-question and before any long search (ADR-0009).
2. Cut `# Goal` into sub-questions under `## Remaining`, then answer them one at a time. The source of truth
   is the **code**, documentation only a supplement. Every claim carries a `path/file.ext:line` or a SHA.
3. Write the report to `../state/repos/<key>/research/<id>-<slug>.md`. A human reads it later (ADR-0025), so
   it has to make sense a year from now: a one-sentence answer in bold, then `## Question`,
   `## Findings`, `## Conclusion and recommendation`, `## Left open`. **Under 800 words**, a finding one
   claim plus its reference, the conclusion under 100 words. Leave out the search that found it and what you
   rejected. Describing data flow, logic or architecture, put a ```mermaid fence inline in `## Findings`
   beside the passage it illustrates; the types are in `references/diagrams.md`. No images.
4. **Presentation HTML**, only when `# Goal` or `## Acceptance` asks for one: spawn `report-preview` with
   the report's absolute path; it writes the same path with `.html`. Check the file exists and is
   self-contained, then commit it with the report. Without that request **no HTML is generated**.
5. Run `## Acceptance` if it is a command, else do literally what it asks. Never edit it.
6. Knowledge review per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/knowledge-review.md`; research proposes no
   ADRs, so only lessons remain.
7. Self-report `review`, `mr_url` still `null`. **You create no MR** (ADR-0016).

Research pointing at work on the code does not do it: the follow-up belongs in
`## Conclusion and recommendation`.

## Self-report

| status | when |
|---|---|
| `review` | acceptance is met, the report is in `repos/<key>/research/`, its path under `## Evidence` |
| `blocked` | a human decision is needed; `${CLAUDE_PLUGIN_ROOT}/skills/_shared/blocked-question.md` |
| `failed` | acceptance is unreachable; `state-report.sh --attempts "<N>, <model>, <why>"` |

Never write `done`, `ready`, `in_progress` or `stalled`.
Report per `${CLAUDE_PLUGIN_ROOT}/skills/_shared/progress-and-push.md`: status and progress file through
`state-report.sh`, the report and the `.html` next to it committed and pushed as the new files they are.
