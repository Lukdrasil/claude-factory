# Investigate

Runs before the tier decision of every `feature`, `bugfix` and `refactor` task, never for `research` or `ops`.

1. `<plugin-root>/bin/investigate.sh <repo-dir> <symbol> [--toolset <toolset.md>]` prints the recon: the
   inventory, the toolset's `find-refs` hits, the `worker-explorer` questions.
2. Hand that block to a `factory-investigator` as its brief. Never a live database and never a live call:
   that is a `decision` gap for the grill.
3. File its report, the five sections `<plugin-root>/bin/task-template.sh investigation` prints, under 400
   words, at `repos/<key>/research/<id>-investigation.md`, and paste its `## Investigation` into the draft's
   `## Context`. A code-changing draft without that section is incomplete, whatever its tier says.
