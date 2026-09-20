#!/bin/sh
# Sourced by the hooks and the task scripts, never run: which tasks a session owns, one frontmatter field of a
# task file, one string field of the hook stdin, and which registered repo a cwd belongs to. task_of /
# owned_task_ids read the state clone the caller put in $state, the way self-report-check.sh and
# session-stats.sh always did.

# the file is chosen by the `id:` line, not by an `<id>-*.md` glob: with hierarchical ids a child `T-005-01-…`
# sorts before its parent `T-005-…` (`0` < a letter) and the glob would hand back the wrong task.
task_of() { grep -lx "id: $1" "$state"/repos/*/tasks/*.md 2>/dev/null | head -n1; }

# the tasks whose `owner:` ends in this session's id — `factory@<host>:<session_id>`, the whole id after the
# last colon (ADR-0050); one id per line, sorted
owned_task_ids() { # <session id>
  esc=$(printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g')
  grep -l "^owner:[[:space:]]*[^[:space:]]*:$esc[[:space:]]*\$" "$state"/repos/*/tasks/*.md 2>/dev/null \
    | xargs -r sed -n 's/^id:[[:space:]]*//p' 2>/dev/null | sed 's/[[:space:]]*#.*//' | sort -u
}

# a block that runs as one implement agent with red-first TDD inside, instead of a tests phase and an implement
# phase: green, or yellow at complexity low. spawn-plan.sh, solve-next.sh and block-brief.sh decide the phase
# by this one rule.
single_phase() { # <tier> <complexity>
  [ "$1" = green ] || { [ "$1" = yellow ] && [ "$2" = low ]; }
}

# one frontmatter field of a task file, rewritten in place: the line is replaced when the key is already there
# (a trailing ` # comment` kept) and inserted just above the closing `---` when it is not. T-007 review: a
# `sed -i 's/^owner:.*/…/'` is a silent no-op on a task whose frontmatter carries no `owner:` line at all, so
# both writers of a task field — task-done.sh and state-report.sh — go through this one helper.
setf() { # <file> <key> <value>
  node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  const [k,v]=process.argv.slice(1);const L=s.replace(/\r\n/g,"\n").split("\n");let end=-1;
  for(let i=1;i<L.length;i++)if(L[i].trimEnd()==="---"){end=i;break}
  if(end<0){process.stdout.write(s);return}
  for(let i=1;i<end;i++){const c=L[i].indexOf(":");if(c<0||/^\s/.test(L[i]))continue;const n=L[i].slice(0,c);if(n.trim()!==k)continue;
    const cm=L[i].slice(c+1).split(" #");L[i]=cm.length>1?`${n}: ${v} #${cm.slice(1).join(" #")}`:`${n}: ${v}`;process.stdout.write(L.join("\n"));return}
  L.splice(end,0,`${k}: ${v}`);process.stdout.write(L.join("\n"))})' "$2" "$3" < "$1" > "$1.tmp" && mv -f "$1.tmp" "$1"
}

# one commit in a state clone, scoped to the paths it is given — the three local writers (task-new.sh,
# task-approve.sh, state-report.sh) commit exactly the files they wrote and never whatever else the clone had
# lying around. The identity fallback is for a worker image with no git identity configured; nothing to commit
# is success, not a failure. Returns non-zero when git refuses, and the caller maps that to its own exit code.
state_commit() { # <state> <message> [paths…]
  sc_state=$1
  sc_msg=$2
  shift 2
  git -C "$sc_state" add -- "$@" || return 1
  if git -C "$sc_state" diff --cached --quiet -- "$@"; then return 0; fi
  if [ -n "$(git -C "$sc_state" config user.email || :)" ]; then
    git -C "$sc_state" commit -q -m "$sc_msg" -- "$@"
  else
    git -C "$sc_state" -c user.name=harness -c user.email=harness@localhost commit -q -m "$sc_msg" -- "$@"
  fi
}

# E3 (2026-09-07): two solve sessions in one standalone state clone reported at the same time, and git's index
# lock is not a transaction — one report's `add` rode in the other's commit. The whole critical section of
# state-report.sh (read the committed status, write, commit, push) runs under one lock per state clone: flock on
# <git-dir>/factory-state.lock where flock exists, otherwise a mkdir spin on <git-dir>/factory-state.lockdir with
# the holder's pid and start time inside, taken over once it is 120 s old (a session that died mid-report).
# STATE_LOCK_WAIT (default 30) is the wait in seconds. Returns 1 on a timeout, 2 when the lock path cannot be made;
# state_unlock is safe to call when nothing is held, so a caller can hang it on `trap … EXIT`.
STATE_LOCK_HELD=''
state_lock() { # <state>
  sl_gd=$(git -C "$1" rev-parse --path-format=absolute --git-dir 2>/dev/null) || sl_gd="$1/.git"
  [ -d "$sl_gd" ] || return 2
  sl_wait=${STATE_LOCK_WAIT:-30}
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$sl_gd/factory-state.lock" || return 2
    flock -w "$sl_wait" 9 || { exec 9>&-; return 1; }
    STATE_LOCK_HELD=fd
    return 0
  fi
  sl_dir="$sl_gd/factory-state.lockdir"
  sl_n=0
  until mkdir "$sl_dir" 2>/dev/null; do
    sl_since=$(cat "$sl_dir/since" 2>/dev/null || :)
    case "$sl_since" in *[!0-9]*) sl_since='' ;; esac
    if [ -n "$sl_since" ] && [ $(( $(date +%s) - sl_since )) -ge 120 ]; then rm -rf "$sl_dir"; continue; fi
    sl_n=$((sl_n + 1))
    [ "$sl_n" -lt "$sl_wait" ] || return 1
    sleep 1
  done
  printf '%s\n' "$$" > "$sl_dir/pid"
  date +%s > "$sl_dir/since"
  STATE_LOCK_HELD=$sl_dir
}
state_unlock() {
  case "$STATE_LOCK_HELD" in
    '') ;;
    fd) exec 9>&- ;;
    *) rm -rf "$STATE_LOCK_HELD" ;;
  esac
  STATE_LOCK_HELD=''
}

# one flat string field of the hook stdin (session_id, cwd, transcript_path) without a JSON parser; a Windows
# path arrives with `\\` and possibly `\/`, both unescaped here
hook_field() { # <json> <field>
  printf '%s' "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed 's/\\\\/\\/g; s/\\\//\//g'
}

# a path the way both sides of a comparison see it: forward slashes, no trailing slash, a lower-case drive letter
# and `x/..` collapsed. T-003: a Windows path is what makes it necessary — `D:\src\repo`, `D:/src/repo` and
# `d:/src/repo/` are one directory, and a comparison that spells them differently lets through the write it meant
# to deny. Every step runs only when there is something to do, so an ordinary POSIX path spawns no process.
norm_path() {
  n=$1
  case "$n" in *\\*) n=$(printf '%s' "$n" | tr '\\' '/') ;; esac
  while :; do case "$n" in ?*/) n=${n%/} ;; *) break ;; esac; done
  case "$n" in
    *..*) while :; do
            nq=$(printf '%s' "$n" | sed -E 's#/[^/]+/\.\.(/|$)#\1#')
            [ "$nq" = "$n" ] && break
            n=$nq
          done ;;
  esac
  case "$n" in [A-Z]:/*|[A-Z]:) n=$(printf '%s' "$n" | cut -c1 | tr '[:upper:]' '[:lower:]')${n#?} ;; esac
  printf '%s' "$n"
}

# norm_path into a variable, skipping the subshell for a path already in that spelling — a command substitution
# would fork exactly the process the cases inside norm_path avoid.
norm_into() { # <variable name> <path>
  case "$2" in
    *\\*|[A-Za-z]:*|*..*|?*/) eval "$1=\$(norm_path \"\$2\")" ;;
    *) eval "$1=\$2" ;;
  esac
}

# T-003: the one layout rule the guard, the Stop hook and session-stats share. Two shapes, one implementation
# (ADR-0049): the worker's <root>/<task-id>/… and the standalone <root>/<key>/<task-id>/…, where <task-id> is
# `T-NNN` (a session worktree) or `T-NNN-NN` (a block worktree). Given a path (the guard's write target) or a cwd
# (a hook) plus the work root, it sets
#   LO_POSTURE  worker | standalone
#   LO_TASK     the task id
#   LO_OWN      the session's work dir LO_STATE  the state clone   LO_STAMP  the per-session stamp directory
# and returns 1 when the path is not under the root at all. The worker layout keeps exactly the directories it
# always had: LO_OWN = <root>/<task-id>, LO_STATE = <own>/state, LO_STAMP = <own>.
is_task_id() { case "$1" in T-[0-9][0-9][0-9]|T-[0-9][0-9][0-9]-[0-9][0-9]) return 0 ;; *) return 1 ;; esac; }

resolve_layout() { # <path> <work root>
  LO_POSTURE=''; LO_TASK=''; LO_OWN=''; LO_STATE=''; LO_STAMP=''
  [ -n "${2:-}" ] || return 1
  # T-003: both sides in the one spelling, so that a Windows path and a work root written the other way round
  # (or with a trailing slash) still compare as the same directory
  norm_into lo_p "$1"; norm_into lo_root "$2"
  case "$lo_p" in "$lo_root"/?*) lo_rest=${lo_p#"$lo_root"/} ;; *) return 1 ;; esac
  lo_s1=${lo_rest%%/*}
  lo_s2=${lo_rest#*/}
  if [ "$lo_s2" = "$lo_rest" ]; then lo_s2=''; else lo_s2=${lo_s2%%/*}; fi
  if [ -n "$lo_s2" ] && is_task_id "$lo_s2" && ! is_task_id "$lo_s1"; then
    LO_POSTURE=standalone; LO_TASK=$lo_s2
    LO_OWN="$lo_root/$lo_s1/$lo_s2"; LO_STATE="$lo_root/state"; LO_STAMP="$lo_root/$lo_s1/.harness/$lo_s2"
  else
    LO_POSTURE=worker; LO_TASK=$lo_s1
    LO_OWN="$lo_root/$lo_s1"; LO_STATE="$lo_root/$lo_s1/state"; LO_STAMP="$lo_root/$lo_s1"
  fi
  return 0
}

# the same rule for a hook, which is handed no target path: the work root is $WORK_DIR when the cwd is under it,
# and otherwise the cwd's own two trailing segments — a standalone session's environment need not carry WORK_DIR.
resolve_cwd_layout() { # <cwd>
  resolve_layout "$1" "${WORK_DIR:-}" && return 0
  lo_d=${1%/*}
  resolve_layout "$1" "${lo_d%/*}"
}

# the state clone of a session, the one rule state-report.sh, self-report-check.sh and session-stats.sh share:
# the sibling `../state` of the product clone when that is a clone itself, the standalone layout's $WORK_DIR/state
# when the cwd is a work dir of it (ADR-0049) — and otherwise the cwd, which is where a triage session sits
# (ADR-0018). `../state` first: the worker layout's sibling clone (ADR-0018) wins over the standalone rule.
resolve_state_dir() { # <cwd>
  if [ -d "$1/../state/.git" ]; then printf '%s' ../state; return 0; fi
  if resolve_cwd_layout "$1" && [ "$LO_POSTURE" = standalone ]; then printf '%s' "$LO_STATE"; return 0; fi
  if in_registered_clone "$1" >/dev/null; then printf '%s' "$WORK_DIR/state"; return 0; fi
  printf '%s' .
}

# why: a factory coordinator (ADR-0049) runs in the registered clone itself, outside $WORK_DIR, where neither the
# worker's sibling `../state` nor the standalone layout resolves and the cwd is no state clone either. Without
# this case the Stop chain and the PreCompact hook look for its tasks under the product clone and find none.
# Prints the registry key and returns 0 only when $WORK_DIR/state is a clone as well.
in_registered_clone() { # <cwd>
  [ -d "${WORK_DIR:-}/state/.git" ] || return 1
  rc_key=$(repo_key_of_cwd "$1")
  [ -n "$rc_key" ] || return 1
  printf '%s' "$rc_key"
}

# the layout of a session that is reporting for a known task: resolve_cwd_layout's standalone answer where the cwd
# is a work dir under $WORK_DIR, and otherwise the coordinator's own standalone posture, whose work dir is the
# registered clone, whose state clone is $WORK_DIR/state and whose stamps sit in $WORK_DIR/<key>/.harness/<task-id>/,
# the same stamp directory the task's own worker session would use. It falls back to resolve_cwd_layout, so every
# posture the resolver already reported stays what it was.
resolve_session_layout() { # <cwd> <task id>
  resolve_cwd_layout "$1" && [ "$LO_POSTURE" = standalone ] && return 0
  if is_task_id "${2:-}" && rs_key=$(in_registered_clone "$1"); then
    rs_top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || rs_top=$1
    LO_POSTURE=standalone; LO_TASK=$2
    LO_OWN=$(norm_path "$rs_top"); LO_STATE="$WORK_DIR/state"; LO_STAMP="$WORK_DIR/$rs_key/.harness/$2"
    return 0
  fi
  resolve_cwd_layout "$1"
}

# every clone registered with a `path:` in $WORK_DIR/state/repos.yml, one `<key><TAB><path>` per line (ADR-0013
# revision; T-006 writes it, the readers do nothing without it)
repo_clone_paths() {
  [ -f "${WORK_DIR:-}/state/repos.yml" ] || return 0
  awk '
    /^[A-Za-z0-9_-]+:/ { key = $1; sub(/:$/, "", key) }
    /path:/ && key != "" {
      p = $0; sub(/.*path:[ \t]*/, "", p); sub(/[ \t]*[,}].*$/, "", p); sub(/[ \t]+#.*$/, "", p)
      gsub(/^["'"'"']|["'"'"']$/, "", p); if (p != "") print key "\t" p
    }' "$WORK_DIR/state/repos.yml"
}

# the key in $WORK_DIR/state/repos.yml whose `path:` is the clone this cwd is in — its toplevel, or the main
# clone when the cwd is a worktree made from it (ADR-0049). Prints nothing when there is no registry or no match.
repo_key_of_cwd() { # <cwd>
  [ -f "${WORK_DIR:-}/state/repos.yml" ] || return 0
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=''
  clone=''
  case "$common" in */.git) clone=$(norm_path "${common%/.git}") ;; esac
  top=$(norm_path "$top")
  repo_clone_paths | while IFS="$(printf '\t')" read -r key p; do
    p=$(norm_path "$p")
    if [ "$p" = "$top" ] || { [ -n "$clone" ] && [ "$p" = "$clone" ]; }; then printf '%s\n' "$key"; break; fi
  done
}

# The MR title is the task's `# Goal` line, and the forge takes it as written: Conventional Commits
# (`type(scope): subject`) so the release tooling can read the semver bump off it, and at most 130 characters
# so no forge truncates it. Both MR scripts check it before they call the forge, so a goal that cannot be a
# title is a task defect caught here and not a bad title on the forge.
mr_title_check() { # <title> -> 0, or the reason on stdout and 1
  n=$(printf '%s' "$1" | wc -m | tr -d '[:space:]')
  if [ "$n" -gt 130 ]; then
    printf 'the title is %s characters and the cap is 130\n' "$n"
    return 1
  fi
  if printf '%s' "$1" | grep -Eq '^(feat|fix|chore|docs|refactor|test|perf|build|ci)(\([a-z0-9._/-]+\))?!?: .+'; then
    return 0
  fi
  printf '%s\n' 'the title is not Conventional Commits; write it as `type(scope): subject` with type one of feat, fix, chore, docs, refactor, test, perf, build, ci'
  return 1
}
