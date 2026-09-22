# hooks.json — why it looks the way it does

`hooks.json` carries no prose of its own: Claude Code validates the whole file, not only the `hooks`
object, and warns `unknown key "//" ignored` for a comment key at the top level (2.1.234 refuses `//Stop`
*inside* `hooks` outright, and the plugin then fails to load — seen on the worker 2026-09-04). Everything
that used to sit in that key lives here instead.

- The file is the policy layer for `bypassPermissions` — the deterministic twin of the rules the skills
  state in prose (v1: ADR-0009, BACKLOG E4.3/E4.4).
- The guard hooks (`policy-guard.sh`, `architect-gate.sh`) waive only the cwd rule outside `WORK_DIR`
  unless `HARNESS_WORKER=1` (ADR-0049). The session hooks — `SessionStart`, `PreCompact`, the PreToolUse
  tripwire — run everywhere.
- `attribution-gate.sh` runs on `Bash` as well as the write tools: a commit, a tag and a forge command
  carry their text in the command, an MR description and a progress file in a file. It scans only those,
  so a source file mentioning any of the banned phrases passes.
- `Stop` has exactly one hook. Both Stop scripts write into the same state clone, so `bin/session-stats.sh`
  is chained from the end of `self-report-check.sh` rather than running beside it over one git index.
- `session-start.sh` warns when the running plugin root looks older than this repo: `bin/attribution-gate.sh`
  missing from it, a `.claude-plugin/plugin.json` version other than the installed one, or, for a dev checkout,
  a HEAD other than the installed `gitCommitSha`. The installed cache is keyed by that version, so a merged PR
  that does not bump it never reaches a session (incident C, 2026-09-22: three PRs shipped nothing while the
  cache sat at 0.12.0). Bump the version in `.claude-plugin/plugin.json` with any change to the hooks.
- No key other than `hooks` belongs in the file, and no key inside `hooks` may be anything but an event
  name. `tests/hooks-wiring.test.sh` enforces both.
