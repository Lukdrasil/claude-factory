#!/bin/sh
# rearm-check.sh, the Stop hook that re-arms a herd's watcher (herdr research R4): only inside herdr (HERDR_TAB_ID
# set) and only with WORK_DIR/state a clone; the herds of the session are the parents whose
# `<WORK_DIR>/<key>/.harness/<T-id>/herd-monitor` holds this $HERDR_TAB_ID and that are not done, closed or
# archived; exit 2 with one `<T-id> <repo> <status>` line per herd that no unfinished entry of
# `background_tasks`, of any type, names with herd-watch.sh and its id; never with stop_hook_active; at most twice
# per session through `.harness-rearm-<sid>` in the state clone's git dir; nothing written in the state clone.
# The solo lane, inside herdr or not: a parent this session owns in review with an mr_url and no unfinished entry
# naming mr-watch.sh or herd-watch.sh with its id is one `<T-id> <repo> review` line and the mr-watch --finish hint.
set -u
unset WORK_DIR HERDR_ENV HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_PANE_ID FACTORY_ROLE FACTORY_UNIT
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
pass() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
is() { # <label> <want> <got>
  if [ "$2" = "$3" ]; then pass "$1"; else bad "$1 (want '$2', got '$3')"; fi
}
has() { # <label> <fixed text> <haystack>
  if printf '%s\n' "$3" | grep -qxF -- "$2"; then pass "$1"; else bad "$1 (no line '$2' in: $3)"; fi
}
lacks() { # <label> <regex> <haystack>
  if printf '%s\n' "$3" | grep -qE -- "$2"; then bad "$1 ('$2' found in: $3)"; else pass "$1"; fi
}

work="$tmp/work"
state="$work/state"
mkdir -p "$state/repos/cf/tasks" "$state/repos/demo/tasks" "$tmp/elsewhere"
printf 'cf: {url: x, default_branch: main, alias: CF, path: "%s/clone"}\ndemo: {url: y, path: "%s/demo"}\n' \
  "$tmp" "$tmp" > "$state/repos.yml"
task() { # <key> <id> <status> [<tasks dir>]
  d=${4:-$state/repos/$1/tasks}
  mkdir -p "$d"
  printf -- '---\nid: %s\nrepo: %s\nstatus: %s\n---\n\n# Goal\nfeat(%s): %s\n' "$2" "$1" "$3" "$1" "$2" > "$d/$2-x.md"
}
task cf T-CF-3 in_progress
task cf T-CF-4 ready
task cf T-CF-4-01 in_progress
task cf T-CF-7 done
task cf T-CF-8 review
task cf T-CF-9 in_progress
task cf T-CF-10 in_progress "$state/repos/cf/archive/2026-09/tasks"
task cf T-CF-11 closed
task cf T-CF-13 in_progress
task demo T-201 blocked

# the herd-monitor files session-monitor.sh --task left behind: this session's tab for most, another tab's for
# T-CF-9, none for T-CF-13, one under a block id and one for a parent with no task file
monitor() { # <key> <T-id> <tab id>
  mkdir -p "$work/$1/.harness/$2"
  printf '%s\n' "$3" > "$work/$1/.harness/$2/herd-monitor"
}
for t in T-CF-3 T-CF-4 T-CF-7 T-CF-8 T-CF-10 T-CF-11 T-CF-4-01 T-CF-12; do monitor cf "$t" tab-mon; done
monitor cf T-CF-9 tab-other
monitor demo T-201 tab-mon

mon() { # <T-id>: a Monitor task running herd-watch.sh on that herd
  printf '{"id":"b%s","type":"monitor","status":"running","description":"herd %s","command":"sh /p/bin/herd-watch.sh %s --interval 60"}' "$1" "$1" "$1"
}
tab=tab-mon
stop() { # <session id> <background_tasks JSON array> [<stop_hook_active>] -> rc on line 1, stderr after
  out=$( (cd "$tmp/elsewhere" && printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":%s,"background_tasks":%s}' \
    "$1" "${3:-false}" "$2" | HERDR_TAB_ID=$tab WORK_DIR="$work" sh "$bin/rearm-check.sh" 2>&1 >/dev/null); printf '\n%s' $?)
  printf '%s\n' "${out##*
}"
  printf '%s' "${out%
*}"
}
rc() { printf '%s\n' "$1" | head -n1; }
err() { printf '%s\n' "$1" | sed 1d; }

# --- what is no herdr monitor, or no clone: nothing ---------------------------------------
r=$(stop s0 '[]')
is 'a state dir that is no clone exits 0' 0 "$(rc "$r")"
is 'and prints nothing' '' "$(err "$r")"

git init -q "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
git -C "$state" add -A
git -C "$state" commit -q -m init

out=$( (cd "$tmp/elsewhere" && printf '{"session_id":"n1","stop_hook_active":false,"background_tasks":[]}' \
  | WORK_DIR="$work" sh "$bin/rearm-check.sh" 2>&1; echo "rc=$?") )
is 'no HERDR_TAB_ID exits 0 and prints nothing' 'rc=0' "$out"
out=$( (cd "$tmp/elsewhere" && printf '{"session_id":"n2","stop_hook_active":false,"background_tasks":[]}' \
  | HERDR_TAB_ID='' WORK_DIR="$work" sh "$bin/rearm-check.sh" 2>&1; echo "rc=$?") )
is 'an empty HERDR_TAB_ID exits 0 and prints nothing' 'rc=0' "$out"
out=$( (cd "$state" && printf '{"session_id":"n3","stop_hook_active":false,"background_tasks":[]}' \
  | HERDR_TAB_ID=tab-mon sh "$bin/rearm-check.sh" 2>&1; echo "rc=$?") )
is 'no WORK_DIR exits 0 and prints nothing' 'rc=0' "$out"
out=$( (cd "$tmp/elsewhere" && printf '{"session_id":"n4","stop_hook_active":false,"background_tasks":[]}' \
  | HERDR_TAB_ID=tab-mon WORK_DIR="$tmp/elsewhere" sh "$bin/rearm-check.sh" 2>&1; echo "rc=$?") )
is 'a WORK_DIR with no state clone exits 0 and prints nothing' 'rc=0' "$out"

# --- the herds of this tab ------------------------------------------------------------------
r=$(stop s2 '[]')
e=$(err "$r")
is 'herds with no watcher exit 2' 2 "$(rc "$r")"
has 'an in_progress parent is listed as <T-id> <repo> <status>' 'T-CF-3 cf in_progress' "$e"
has 'a ready parent is listed' 'T-CF-4 cf ready' "$e"
has 'a parent in review is listed' 'T-CF-8 cf review' "$e"
has 'a herd of another repo is listed with its key' 'T-201 demo blocked' "$e"
lacks 'a done parent is not listed' 'T-CF-7 ' "$e"
lacks 'a closed parent is not listed' 'T-CF-11 ' "$e"
lacks 'an archived parent is not listed' 'T-CF-10 ' "$e"
lacks 'the herd of another tab id is not listed' 'T-CF-9 ' "$e"
lacks 'a parent with no herd-monitor is not listed' 'T-CF-13 ' "$e"
lacks 'a block is never a herd of its own' 'T-CF-4-01' "$e"
lacks 'a herd-monitor with no task file is not listed' 'T-CF-12' "$e"
has 'the message names herd-watch.sh and the Monitor tool' yes \
  "$(printf '%s' "$e" | grep -q 'herd-watch.sh <T-id> --interval 60' && printf '%s' "$e" | grep -q 'Monitor' && echo yes)"

r=$(tab=tab-other; stop o1 '[]')
e=$(err "$r")
is 'the other tab has its own herd: exit 2' 2 "$(rc "$r")"
has 'the other tab lists its herd' 'T-CF-9 cf in_progress' "$e"
lacks 'and none of this tab' 'T-CF-3 |T-CF-4 |T-CF-8 |T-201 ' "$e"
r=$(tab=tab-none; stop o2 '[]')
is 'a tab with no herd exits 0' 0 "$(rc "$r")"
is 'and prints nothing' '' "$(err "$r")"

# --- the watchers ---------------------------------------------------------------------------
r=$(stop s3 "[$(mon T-CF-3)]")
e=$(err "$r")
is 'one herd watched, the others not: exit 2' 2 "$(rc "$r")"
lacks 'the watched herd is not listed' 'T-CF-3 ' "$e"
has 'an unwatched herd still is' 'T-CF-4 cf ready' "$e"

r=$(stop s4 "[$(mon T-CF-3),$(mon T-CF-4),$(mon T-CF-8),$(mon T-201)]")
is 'every herd watched exits 0' 0 "$(rc "$r")"
is 'and prints nothing' '' "$(err "$r")"

r=$(stop s5 '[{"id":"b1","type":"monitor","status":"running","description":"herd-watch.sh T-CF-3"},{"id":"b2","type":"monitor","status":"running","description":"herd-watch.sh T-CF-4"},{"id":"b3","type":"monitor","status":"running","description":"sh herd-watch.sh T-CF-8 --interval 60"},{"id":"b4","type":"monitor","status":"running","description":"herd-watch.sh T-201"}]')
is 'a monitor naming herd-watch.sh in its description counts' 0 "$(rc "$r")"

# the harness reports a task the Monitor tool started as `local_bash`: any type counts, a finished task does not
r=$(stop s6 '[{"id":"b1","type":"local_bash","status":"running","description":"herd-watch.sh T-CF-3","command":"sh /p/bin/herd-watch.sh T-CF-3 --interval 60"}]')
lacks 'a running local_bash task naming herd-watch.sh watches its herd' 'T-CF-3 ' "$(err "$r")"
r=$(stop s12 '[{"id":"b1","type":"local_bash","status":"completed","command":"sh herd-watch.sh T-CF-3"},{"id":"b2","type":"monitor","status":"killed","command":"sh herd-watch.sh T-CF-3"},{"id":"b3","type":"monitor","status":"failed","command":"sh herd-watch.sh T-CF-3"},{"id":"b4","type":"monitor","status":"stopped","command":"sh herd-watch.sh T-CF-3"}]')
has 'a finished task watches nothing' 'T-CF-3 cf in_progress' "$(err "$r")"

r=$(stop s7 "[$(mon T-CF-30)]")
has 'a watcher of T-CF-30 does not watch T-CF-3' 'T-CF-3 cf in_progress' "$(err "$r")"
r=$(stop s13 "[$(mon T-CF-4-01)]")
has 'a watcher of a block id does not watch its parent' 'T-CF-4 cf ready' "$(err "$r")"

r=$(stop s8 '[{"id":"b1","type":"monitor","status":"running","description":"mr-watch T-CF-3","command":"sh mr-watch.sh T-CF-3"}]')
has 'a monitor without herd-watch.sh does not count' 'T-CF-3 cf in_progress' "$(err "$r")"

# --- stop_hook_active, the per-session budget, nothing in the state clone ------------------
r=$(stop s9 '[]' true)
is 'stop_hook_active true exits 0' 0 "$(rc "$r")"
is 'stop_hook_active true prints nothing' '' "$(err "$r")"
is 'stop_hook_active spends none of the budget' '' "$(cat "$state/.git/.harness-rearm-s9" 2>/dev/null)"

is 'first block of a session' 2 "$(rc "$(stop s10 '[]')")"
is 'second block of the same session' 2 "$(rc "$(stop s10 '[]')")"
r=$(stop s10 '[]')
is 'a third Stop of the same session passes' 0 "$(rc "$r")"
is 'and prints nothing' '' "$(err "$r")"
is 'another session starts its own count' 2 "$(rc "$(stop s11 '[]')")"
is 'the counter sits in the git dir of the state clone' 2 "$(cat "$state/.git/.harness-rearm-s10" 2>/dev/null)"
is 'a watched Stop spends none of the budget' '' "$(cat "$state/.git/.harness-rearm-s4" 2>/dev/null)"
is 'and nothing lands in the factory root' '' "$(ls -A "$work" | grep 'harness-rearm')"
is 'nor beside the herd-monitor' '' "$(find "$work/cf/.harness" -name '.harness-rearm-*')"
is 'the state clone stays clean' '' "$(git -C "$state" status --porcelain)"

# --- the solo lane: a task MR of this session waits on the human's merge --------------------
solo() { # <key> <id> <status> <owner sid> <mr_url>
  printf -- '---\nid: %s\nrepo: %s\nstatus: %s\nowner: factory@h:%s\nmr_url: %s\n---\n\n# Goal\nfeat(%s): %s\n' \
    "$2" "$1" "$3" "$4" "$5" "$1" "$2" > "$state/repos/$1/tasks/$2-x.md"
}
solo demo T-301 review solo1 https://forge.test/mr/31
solo demo T-302 review solo1 null
solo demo T-303 in_progress solo1 https://forge.test/mr/33
solo demo T-304 review other https://forge.test/mr/34
solo demo T-301-01 review solo1 https://forge.test/mr/35
mw() { # <T-id>: a Monitor task running mr-watch.sh on that task
  printf '{"id":"m%s","type":"local_bash","status":"running","description":"mr-watch.sh %s","command":"sh /p/bin/mr-watch.sh %s --finish --interval 300"}' "$1" "$1" "$1"
}
nostop() { # <session id> <background_tasks JSON array>: the Stop outside herdr, with a fresh budget
  rm -f "$state/.git/.harness-rearm-$1"
  out=$( (cd "$tmp/elsewhere" && printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":false,"background_tasks":%s}' \
    "$1" "$2" | WORK_DIR="$work" sh "$bin/rearm-check.sh" 2>&1 >/dev/null); printf '\n%s' $?)
  printf '%s\n' "${out##*
}"
  printf '%s' "${out%
*}"
}
r=$(nostop solo1 '[]')
e=$(err "$r")
is 'an unwatched task MR of this session blocks the Stop outside herdr' 2 "$(rc "$r")"
has 'it is listed as <T-id> <repo> review' 'T-301 demo review' "$e"
lacks 'a parent with no mr_url is not listed' 'T-302 ' "$e"
lacks 'a parent not in review is not listed' 'T-303 ' "$e"
lacks 'a task of another session is not listed' 'T-304 ' "$e"
lacks 'a block is never listed' 'T-301-01' "$e"
has 'the message names mr-watch.sh --finish and the Monitor tool' yes \
  "$(printf '%s' "$e" | grep -q 'mr-watch.sh <T-id> --finish --interval 300' && printf '%s' "$e" | grep -q 'Monitor' && echo yes)"
lacks 'and no herd text outside herdr' 'herd-watch' "$e"
r=$(nostop solo1 "[$(mw T-301)]")
is 'a running mr-watch.sh on it lets the Stop through' 0 "$(rc "$r")"
r=$(nostop solo1 '[{"id":"h","type":"monitor","status":"running","command":"sh herd-watch.sh T-301 --interval 60"}]')
is 'a running herd-watch.sh on it counts too' 0 "$(rc "$r")"
r=$(nostop solo1 "[$(mw T-3010)]")
is 'a watcher of T-3010 does not watch T-301' 2 "$(rc "$r")"
r=$(nostop solo1 '[{"id":"m","type":"local_bash","status":"completed","command":"sh mr-watch.sh T-301 --finish"}]')
is 'a finished mr-watch.sh watches nothing' 2 "$(rc "$r")"
rm -f "$state/.git/.harness-rearm-solo1"
r=$( (cd "$tmp/elsewhere" && printf '{"session_id":"solo1","stop_hook_active":false,"background_tasks":[]}' \
  | HERDR_TAB_ID=tab-mon WORK_DIR="$work" sh "$bin/rearm-check.sh" 2>&1 >/dev/null) )
has 'inside herdr the solo task is listed beside the herds' 'T-301 demo review' "$r"
has 'and the herds still are' 'T-CF-3 cf in_progress' "$r"
r=$(nostop other '[]')
has 'the owner of the other task is asked for it alone' 'T-304 demo review' "$(err "$r")"
lacks 'and not for the tasks of solo1' 'T-301 ' "$(err "$r")"
rm -f "$state/repos/demo/tasks/T-30"*-x.md "$state/.git/.harness-rearm-solo1" "$state/.git/.harness-rearm-other"

# --- the role is no scope any more --------------------------------------------------------
is 'a session with a FACTORY_ROLE is asked the same' 2 "$(rc "$(FACTORY_ROLE=pass; export FACTORY_ROLE; stop r1 '[]')")"

# --- what the hook cannot read lets the Stop through ---------------------------------------
out=$( (cd "$tmp/elsewhere" && printf 'not json' | HERDR_TAB_ID=tab-mon WORK_DIR="$work" sh "$bin/rearm-check.sh" >/dev/null 2>&1); echo $?)
is 'unreadable hook JSON exits 0' 0 "$out"
out=$( (cd "$tmp/elsewhere" && printf '{"hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[]}' \
  | HERDR_TAB_ID=tab-mon WORK_DIR="$work" sh "$bin/rearm-check.sh" >/dev/null 2>&1); echo $?)
is 'no session id exits 0' 0 "$out"
is 'a session id that is no file name exits 0' 0 "$(rc "$(stop 'a/b' '[]')")"

exit $fail
