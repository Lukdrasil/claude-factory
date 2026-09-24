# hooks.json, why it looks the way it does

`hooks.json` carries no prose of its own: Claude Code validates the whole file, not only the `hooks`
object, and warns `unknown key "//" ignored` for a comment key at the top level (2.1.234 refuses `//Stop`
*inside* `hooks` outright, and the plugin then fails to load, seen 2026-09-04). Everything
that used to sit in that key lives here instead.

- The file is the policy layer for `bypassPermissions`, the deterministic twin of the rules the skills
  state in prose (v1: ADR-0009, BACKLOG E4.3/E4.4).
- The guard hooks (`policy-guard.sh`, `architect-gate.sh`) waive only the cwd rule outside `WORK_DIR`
  (ADR-0049). A cwd under `WORK_DIR` that is no task worktree, such as `WORK_DIR/state` or `WORK_DIR/<key>`,
  may write only inside that top-level directory. The session hooks, `SessionStart`, `PreCompact`, the PreToolUse
  tripwire, run everywhere.
- `attribution-gate.sh` runs on `Bash` as well as the write tools: a commit, a tag and a forge command
  carry their text in the command, an MR description and a progress file in a file. On `Bash` it also
  resolves the files the command reads - `--description-file`, `--body-file`, `git commit -F`, `-f key=@path`,
  `$(cat path)`, a `< path` redirect - and scans those, and it matches a git verb through `-C dir` and
  `-c k=v` options; on a write it watches a path that looks like a message or a body and any text carrying an
  MR-body marker or a Conventional Commits first line. A source file mentioning a banned phrase still passes.
- The Stop hooks that write the state clone are chained from `self-report-check.sh`: both write into the same
  state clone, so `bin/session-stats.sh` runs from the end of `self-report-check.sh` rather than beside it over
  one git index. `rearm-check.sh` is the second Stop hook and writes nothing there: in a parent worktree whose
  units run in herdr, and in the state clone for every parent of a request that is in flight, it exits 2 with
  one herd-list line per herd that no `monitor` entry of the hook's `background_tasks` watches with
  `herd-watch.sh <T-id>`, so a CEO or lead whose Monitor expired, or that was restarted, arms it again. Never
  when `stop_hook_active` is true, at most twice per session (its counter `.harness-rearm-<sid>` sits in the
  stamp directory, outside the state clone).
- `session-start.sh` warns when the running plugin root looks older than this repo: `bin/attribution-gate.sh`
  missing from it, a `.claude-plugin/plugin.json` version other than the installed one, or, for a dev checkout,
  a HEAD other than the installed `gitCommitSha`. The installed cache is keyed by that version, so a merged PR
  that does not bump it never reaches a session (incident C, 2026-09-22: three PRs shipped nothing while the
  cache sat at 0.12.0). Bump the version in `.claude-plugin/plugin.json` with any change to the hooks.
- Capacity (agent-org plan 3.3): `capacity.sh --hook pretooluse` on `Agent` denies a subagent whose role is
  at its cap in factory.yml `capacity:` and otherwise writes a pending lease; `--hook subagentstart` turns the
  oldest pending lease of that session and role into the agent's own; `--hook subagentstop` releases it. The
  leases live in `<state>/.capacity/` under their own lock, never the state lock. A role outside the table, a
  factory.yml without `capacity:`, a missing state clone or any error of the script lets the call through with
  nothing printed.
- `playbook-inject.sh --hook` on `SubagentStart` hands the subagent the playbook of its role for the repo key of
  its cwd, `repos/<key>/agents/<role>/playbook.md` in the state clone, as `additionalContext`, or nothing.
- No key other than `hooks` belongs in the file, and no key inside `hooks` may be anything but an event
  name. `tests/hooks-wiring.test.sh` enforces both, that the capacity and playbook hooks sit on their events,
  and the Stop order with `rearm-check.sh` calling no state writer.

## policy-guard rules

The Bash rules of `bin/policy-guard.sh` that T-228 changed, and the issue label rule T-254 added.
`tests/policy-guard.test.sh` replays each one, together with every deny they keep.

- **Segments.** A command is judged one segment at a time, and a segment ends at `;`, `|`, `&` or a line
  break outside quotes only. A `&&` inside a printf argument or a commit message is data. Heredoc bodies are
  dropped before any scan, the push checks included, unless the body is fed to `sh`, `bash`, `zsh` or `eval`.
- **cd tracking.** An allowlist. A `cd` replaces the cwd the later segments are judged against only when the
  whole command has this shape: one or more leading segments `cd <path>`, where the path is absolute, `~`,
  `~/x` or empty (through `$HOME`), with no option, then simple commands. Every separator is `&&`, and a `|`
  appears only inside a later segment. Outside quotes there is no `(`, `)`, `$(`, backtick, `;`, `||`,
  background `&` or line break. No word is `pushd`, `popd`, `builtin`, `command`, `eval`, `source` or `exec`,
  no segment starts with `.`, and no assignment (`CDPATH=` included) is prefixed to a `cd`. In every other
  shape the cwd stays the hook's, and the target of every `cd` or `pushd` seen, even behind `builtin`,
  `command`, `eval`, `exec` or an assignment, joins a set of bases. A relative target is denied when it is a
  protected target under any base. A `cd` to an existing path whose resolved spelling (`pwd -P`) differs from its
  text, such as a symlink, ends the shape for the rest of the command, and the hook cwd stays among the bases.
  A `cd` the guard cannot resolve (a relative path, `-`, a variable, `..`, a quoted path, a target containing `)`, a bare `pushd` or `popd`) turns the shape off for the rest of the
  command, keeps the hook cwd among the bases, and denies a relative write target: a redirect target, an
  in-place editor's operand containing a `/`, or the file operand of `sed -i`/`perl -i`. A command word is
  never one. An absolute target is judged as any absolute target.
- **Redirect targets.** The word after a `>`, `>>`, `2>` or `&>` outside quotes is a write target. A `>`
  inside a quoted span is data, a `\"` or `\'` outside quotes is an escaped character that opens no span, and
  a `\"` inside `"…"` does not close it. An ANSI-C span `$'…'` closes only at an unescaped `'`, so `\'` inside
  it is data, and it opens only after an odd run of `$`: in `$$'…'` the `$$` is the PID and the quote is plain. `>&N`, `>&-`, `>(`, `=>`, `<>` and `->` name no file, while `>&word` writes the file `word`. A
  target quoted as a whole (`> "README.md"` or `> $'README.md'`) is judged without its quotes. A bare `~` or `~/x` is expanded through `$HOME` and
  denied when `HOME` is unset, while a quoted `"~/x"` is relative to the cwd, as the shell writes it.
- **In-place editors.** The tokens of `sed -i`, `perl -i`, `tee`, `patch` and `git checkout|restore` are read
  with quoted spans removed, so the pieces of a quoted script are never write targets, and a target that starts
  with `$` is skipped, as for a redirect. The first operand of `sed -i` and `perl -i` without `-e` is the
  script, quoted or not, and is skipped. The last operand is judged as a file even when it does not exist yet.
  A `~` or `~/x` token is expanded through `$HOME` and denied when `HOME` is unset.
- **Reads into blocks.** The session that owns a parent task (its `owner:`) may run `git -C <block worktree>
  log|diff|status|show`, `cat` and `ls` in the worktrees of that parent's blocks. A block session may `cat`
  its own brief, `.harness/<parent>/brief-<block>.md`. A segment holding `$(`, a backtick, `<(` or `>(` runs a
  command of its own and is never a read. Nothing else changes: a write into a block, a read by any other
  session and a read of a sibling's brief stay denied.
- **Pinned lease.** `git push --force-with-lease[=<branch>[:<sha>]] [-u] origin <branch>` is allowed on the
  session's own task branch. The parent's owner pushes the parent branch as `git -C <parent worktree> push
  --force-with-lease=<branch>:<sha> origin <branch>`, where `<branch>` is that task's `branch:`. A lease on
  the default branch or on any other branch is denied.
- **State-clone commits.** In `$WORK_DIR/state`, reached by the cwd, a `cd` or `-C`, `git commit` must name
  at least one path after `--`, and `-a`/`--all` is denied. A quoted `-C` directory counts, and so does one
  spelled `~/…`. Every path is a file: `.`, `:/`, a path ending in `/` and an existing directory are denied.
  `git add` stays allowed.
- **Issue label.** A segment with `gh issue create` or `glab issue create` is denied unless `--label` or `-l`
  carries `ai-drafted` as one comma-separated value, quoted or bare, after a space or `=`. The deny names
  `bin/issue-create.sh`, which adds the label.
