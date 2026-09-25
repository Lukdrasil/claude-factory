# Investigate

Runs before the tier decision of every `feature`, `bugfix` and `refactor` task, never for `research` or `ops`.

1. `<plugin-root>/bin/investigate.sh <repo-dir> <symbol> [--toolset <toolset.md>]` prints the recon: the
   inventory, the toolset's `find-refs` hits, the `scout` questions.
2. Hand that block to a `triage-analyst` as its brief. Never a live database and never a live call:
   that is a `decision` gap for the grill.
3. File its report, the five sections `<plugin-root>/bin/task-template.sh investigation` prints, under 400
   words, at `$WORK_DIR/state/repos/<key>/research/<id>-investigation.md`, the absolute path in the state clone
   and never under the product clone the session runs in, and paste its `## Investigation` into the draft's
   `## Context`. A code-changing draft without that section is incomplete, whatever its tier says.
4. Search the repo's open issues before anyone plans: spawn `issue-finder` with the problem text (the draft's
   `# Goal` and `## Context`, and the request as the human gave it when the draft has a `request:`) instead of a
   diff. Write its lines under `## Related issues` in the draft, after `## Context`, or `none`. The CEO reads
   that section: it offers to link one issue (`issue: <url>` on the parent) or, with `none` and no `issue:`
   yet, to create one with `<plugin-root>/bin/issue-create.sh`, which labels it `ai-drafted`; either is one
   confirm ask through `_shared/ask.md`, never done without the yes.
