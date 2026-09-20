---
name: block-tests
description: The tests phase of a two-phase implementation task (ADR-0030, red tier or yellow above low complexity): the blast radius covered green, new behaviour as red tests, a handoff for the implement phase.
---

# block-tests

Prepare the test contract: blast-radius behaviour covered green, new behaviour as red tests. Finish in
`tests_ready` with the branch pushed and a `## Handoff` in the progress file: another session implements and
gets only what you pushed. The argument is the task file's path in the state clone; read all of it (P4).

## Preconditions

- cwd is the task worktree on the branch from the frontmatter, the state clone in `../state`, the progress
  file `../state/repos/<key>/progress/<id>.md`; otherwise self-report `failed`.
- Toolset (ADR-0039): `build`, `test`, `test-filter <expr>`, `find-refs <symbol>`; one the repo lacks is a
  note in the handoff, not a failure.
- `${CLAUDE_PLUGIN_ROOT}/skills/_shared/rules.md`,
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/progress-and-push.md` and
  `${CLAUDE_PLUGIN_ROOT}/skills/_shared/delegation.md` hold; rerun every delivered test yourself. Spawned as
  a block subagent, `${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md` replaces those three and steps
  1, 6 and 7.

## Procedure

1. Snapshot and `state-report.sh`, the first heartbeat.
2. **Analysis and blast radius.** How far the change reaches: files, modules, public APIs `## Acceptance`
   rests on, with the reasoning, into the progress file as you go.
3. **Green baseline.** The existing tests over the blast radius under
   `${CLAUDE_PLUGIN_ROOT}/skills/_shared/test-budget.md`, recorded. Already red is `blocked`.
4. **Characterization tests.** Cover blast-radius behaviour the existing tests miss, green straight away, or
   the implement phase cannot tell what it broke.
5. **Red tests.** The new behaviour from `# Goal` and `## Acceptance` as failing tests, each run to confirm
   it fails **for the right reason**, missing functionality and not a typo, the reason into the handoff.
   Files exempt under `${CLAUDE_PLUGIN_ROOT}/skills/_shared/test-exemptions.md` get none, here or in step 4;
   they go under `Notes` as `exempt`. Never edit acceptance.
6. **Handoff.** `git push -u origin <branch>`, rewrite the progress file, append the filled-in section
   `sh ${CLAUDE_PLUGIN_ROOT}/bin/task-template.sh handoff` prints. Push first, the next phase clones fresh.
7. Self-report `tests_ready`.

**You do not change production code**, only tests and their scaffolding. A spec untestable without one is a
handoff note; an ambiguity is `blocked`. No MR and no knowledge review here.

## Self-report

| status | when |
|---|---|
| `tests_ready` | the branch is pushed, `## Handoff` is written, the red run is under `## Evidence` |
| `blocked` | a human decision is needed; `${CLAUDE_PLUGIN_ROOT}/skills/_shared/blocked-question.md` |
| `failed` | the contract could not be built; `state-report.sh --attempts "<N>, <model>, <why>"` |

Never `review`; `## Remaining` lists what the handoff still misses.

## As a block subagent

Steps 2 to 5, the tests committed on the block branch, then the report of
`${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md` with the filled-in `## Handoff`. The coordinator
reruns the red tests first.
