---
name: decompose
description: Turns a grilled plan-ready.md into draft tasks through the dashboard Task API or the local task-new script. Use at the end of a grilling session, when the spec should become work.
---

# decompose

Trigger: a `plan-ready.md` the grill finished. Cut it into blocks and write them `status: draft`;
approval and `plan_hash` are a human's job.

## Input

`repos/<repo-key>/plans/<slug>-plan-ready.md` in the state clone, read in full. With no path, ask which.

| section of plan-ready.md | what you take from it |
|---|---|
| frontmatter `repo:` | `repo` and the `<repo-key>` prefix |
| frontmatter `task:` | the source task to recommend closing at the end |
| `## Proposed tasks` | one block per proposal; `tier`, `archetype`, `complexity`, `docs` and `acceptance` map 1:1 into frontmatter and sections |
| `## Program design` | the members a proposal's `design:` names, verbatim into `## Context` under `Design (approved in the grill):`. Proposals with no design section is a plan not grilled through: stop and ask |
| `## Decisions` | what a fresh session would not guess, into `## Context` |
| `## Out of scope` | into each task it applies to |
| `## Gap ledger` | a finished grill has no open row; an open one stops you |

## Preconditions

- A state clone. `DASHBOARD_URL` set selects the Task API and needs `DASHBOARD_API_TOKEN`; unset, tasks go
  locally through `${CLAUDE_PLUGIN_ROOT}/bin/task-new.sh`. Both routes: `references/writing.md`.
- `<repo-key>` is in `repos.yml`, or stop: a task with no registry entry is undispatchable.
- Acceptance is a runnable command on every proposal. If one is missing, ask; never invent it.

## Steps

1. Cut the spec into blocks: one block is one functionality a developer reviews in one sitting, about 300
   changed lines, one branch, one MR into the block it depends on, a self-contained spec for a fresh session.
   Three to six blocks is the shape; twelve is the cap, and a plan that wants more is two plans.
2. Give a shared fixture (a test-DB helper, a fake clock) to exactly one block, the earliest; the others
   `depends_on` it and name it in their `## Context`. Two blocks that each invent one collide.
3. Print the skeleton with `sh ${CLAUDE_PLUGIN_ROOT}/bin/task-template.sh block` and fill one temporary file
   per block, in topological order, per `references/fields.md`. Do not compute ids and do not renumber the
   proposals.
4. Run the `cut-check` invocation of `architect-review` over the temporary files, per `references/writing.md`.
5. Write the tasks, rewriting `depends_on` from the plan's ordinals to the returned ids, per
   `references/writing.md`, then delete the verdict file and push that deletion.
6. Show the human one line per block: id, title, tier, archetype, depends_on, file path.
7. Recommend closing the source task; that flip is a human's.

**Done when** every block exists as `status: draft`, `repos/<repo-key>/verdicts/<slug>.md` is gone from the
state repo, and the human has the list.

Never write `status: ready`, never fill `plan_hash`, `owner` or `mr_url`, never edit another task, never
commit by hand.
