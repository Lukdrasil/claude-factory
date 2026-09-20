# The fields

`<plugin-root>/bin/decompose.sh` fills the skeleton of `task-template.sh block` by these rules; read this when
a generated file looks wrong, to tell a plan defect from a script defect:

- `tier`, `archetype`, `complexity` - copied 1:1 from the plan's proposal. The grill made those decisions
  against `<plugin-root>/skills/_shared/tiers.md` and you do not remake them here. For a `red` tier, remind
  the human that spec-critic comes before the flip to `ready`.
- `runtime` - `default`, until the task needs its own isolation or image.
- `depends_on` - only ids of tasks from this batch or already existing ones, no cycles. Dispatch waits for
  their `done`.
- `branch` - the prefix per archetype (`feat/`, `fix/`, `refactor/`, `research/`) plus the slug, written
  without the id; `task-new.sh` inserts the id it assigns after the prefix. A triage task has no branch.
- `# Goal`, `## Context`, `## Acceptance` - what must be true when the task is done, never how the
  environment is configured. Name the command, never its binding: the binding is regenerated per dispatch
  while a task body is immutable.
- `## Context` names the plan it came from by its full path, so the architect gate can find the verdict, and
  carries the `Design (approved in the grill):` block verbatim.
- `## Docs` - the grill's `docs:` answer for this proposal, copied verbatim. Do not invent one the grill did
  not make; with nothing to carry over, write `none`.
- `- forge issue:` - the url the source task carries, copied onto **every** block. It is the join key the
  MR description and the issue are paired on, so without it the issue never learns the work exists. With no
  forge issue on the source task, the line and the whole `## Internal` section are omitted; never an empty one.
