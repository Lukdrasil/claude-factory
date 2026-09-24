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
  carry their text in the command, an MR description and a progress file in a file. On `Bash` it also
  resolves the files the command reads - `--description-file`, `--body-file`, `git commit -F`, `-f key=@path`,
  `$(cat path)`, a `< path` redirect - and scans those, and it matches a git verb through `-C dir` and
  `-c k=v` options; on a write it watches a path that looks like a message or a body and any text carrying an
  MR-body marker or a Conventional Commits first line. A source file mentioning a banned phrase still passes.
- `Stop` has exactly one hook. Both Stop scripts write into the same state clone, so `bin/session-stats.sh`
  is chained from the end of `self-report-check.sh` rather than running beside it over one git index.
- `session-start.sh` warns when the running plugin root looks older than this repo: `bin/attribution-gate.sh`
  missing from it, a `.claude-plugin/plugin.json` version other than the installed one, or, for a dev checkout,
  a HEAD other than the installed `gitCommitSha`. The installed cache is keyed by that version, so a merged PR
  that does not bump it never reaches a session (incident C, 2026-09-22: three PRs shipped nothing while the
  cache sat at 0.12.0). Bump the version in `.claude-plugin/plugin.json` with any change to the hooks.
- No key other than `hooks` belongs in the file, and no key inside `hooks` may be anything but an event
  name. `tests/hooks-wiring.test.sh` enforces both.

## policy-guard rules

The Bash rules of `bin/policy-guard.sh` that T-228 changed. `tests/policy-guard.test.sh` replays each one,
together with every deny they keep.

- **Segments.** A command is judged one segment at a time, and a segment ends at `;`, `|`, `&` or a line
  break outside quotes only. A `&&` inside a printf argument or a commit message is data. Heredoc bodies are
  dropped before any scan, the push checks included, unless the body is fed to `sh`, `bash`, `zsh` or `eval`.
- **cd tracking.** `cd <abs>`, `cd`, `cd ~` and `cd ~/x` (through `$HOME`) move the cwd that later segments of
  the same command are judged against. After a `cd` the guard cannot resolve (a relative path, `-`, a
  variable, `..`, a quoted path), a relative write target and an in-place write are denied. An absolute
  target still passes.
- **In-place editors.** The tokens of `sed -i`, `perl -i`, `tee`, `patch` and `git checkout|restore` are read
  with quoted spans removed, so the pieces of a quoted script are never write targets, and a target that starts
  with `$` is skipped, as for a redirect. The last operand of `sed -i` and `perl -i` is judged as a file even
  when it does not exist yet.
- **Reads into blocks.** The session that owns a parent task (its `owner:`) may run `git -C <block worktree>
  log|diff|status|show`, `cat` and `ls` in the worktrees of that parent's blocks. A block session may `cat`
  its own brief, `.harness/<parent>/brief-<block>.md`. Nothing else changes: a write into a block, a read by
  any other session and a read of a sibling's brief stay denied.
- **Pinned lease.** `git push --force-with-lease[=<branch>[:<sha>]] [-u] origin <branch>` is allowed on the
  session's own task branch. The parent's owner pushes the parent branch as `git -C <parent worktree> push
  --force-with-lease=<branch>:<sha> origin <branch>`, where `<branch>` is that task's `branch:`. A lease on
  the default branch or on any other branch is denied.
- **State-clone commits.** In `$WORK_DIR/state`, reached by the cwd, a `cd` or `-C`, `git commit` must name
  its paths after `--`, and `-a`/`--all` is denied. `git add` stays allowed.
