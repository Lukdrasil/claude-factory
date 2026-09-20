---
name: spec-critic
description: A second pair of eyes on a draft task before approval, read with a clean context like a fresh session and reported as proposed edits. Use on tier yellow or red, before a human flips a draft to ready.
---

# spec-critic

Trigger: a draft task at `tier: yellow` or `tier: red`, before the flip to `ready`; not a green task, which
costs more than it gives. You criticise the **spec, not the code**:

> Would a fresh session, given only this file and the generated `CLAUDE.md`, get all the way to a finished result?

## Preconditions

- The argument is the path to the task file, `repos/<repo-key>/tasks/<id>-<slug>.md`. With no path, ask.
- The task is `status: draft`, or stop: after the flip `plan_hash` holds the spec, and an edit puts the task
  out of sync with the approved version.
- **Keep your context clean**: do not read the grill transcript or the plan. What the task leaves out
  because "everyone knows it from the grill" is the finding this skill exists for.
- cwd is a clone of the state repo. You implement nothing, and read the product repo only to judge a
  reference in `## Context`.

## Steps

1. Read the whole task once, as a fresh session would, noting whatever is unclear; that first impression does
   not come back.
2. Walk the five axes, each finding written as a **proposed edit** in concrete text. A finding without one is
   an opinion.
3. Close what the code can close, a stale or missing reference, with `path/file.ext:line`; a finding that is
   a choice stays a question.
4. Show the human the report of `references/report.md`, write the agreed edits into the task file, commit
   and push. Without agreement, edit nothing.
5. Say what happens next: the flip to `ready` and `plan_hash` are a human's, in the dashboard.

As the `spec-critic` subagent you stop after step 3: the report is your final message, back to the calling
session.

## The five axes

| axis | what you look for |
|---|---|
| self-containment | what a fresh session would not know in its first minute: an unreferenced "existing solution", a grill decision missing from the task |
| acceptance | is `## Acceptance` runnable and does it decide done/not-done alone, rather than "check that the export works" |
| dependencies | does `depends_on` match what the task reads and writes, with no cycle |
| out of scope | is the boundary written down in `## Out of scope`, or only assumed |
| docs | does the task change **public behaviour or architecture**, an endpoint, a CLI flag, a config key, a module, an external integration, and does `## Docs` reflect that? An internal-only change with no `## Docs` is **not** a finding: absent means `none` |

**Done when** every axis is walked and every finding carries a proposed edit; a clean axis is silence and a
clean draft gets a short `OK`.
