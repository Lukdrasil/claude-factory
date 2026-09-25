#!/bin/sh
# rearm-check.sh, the Stop hook that re-arms a herd's watcher (agent-org plan 3.1, 3.7, R4): scoped by the cwd (a
# parent worktree with herdr units is that herd; the state clone is every parent with a `request:` that is
# in_progress or review, has a block in flight, or has an open step record; anywhere else nothing); exit 2 with one herd-list line
# `<request> <priority> <T-id> <repo> <status>` per herd that no unfinished entry of `background_tasks`, of any
# type, watches with herd-watch.sh; never with stop_hook_active; at most twice per session through `.harness-rearm-<sid>`;
# nothing written in the state clone.
set -u
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
mkdir -p "$state/repos/cf/tasks" "$tmp/elsewhere"
printf 'cf: {url: x, default_branch: main, alias: CF, path: "%s/clone"}\n' "$tmp" > "$state/repos.yml"
task() { # <id> <status> <request> [<priority>]
  {
    printf -- '---\nid: %s\nrepo: cf\nstatus: %s\nrequest: %s\n' "$1" "$2" "$3"
    [ -z "${4:-}" ] || printf 'priority: %s\n' "$4"
    printf -- '---\n\n# Goal\nfeat(cf): %s\n' "$1"
  } > "$state/repos/cf/tasks/$1-x.md"
}
req=R-20260925-1
task T-CF-3 in_progress "$req" P1
task T-CF-4 ready "$req"
task T-CF-4-01 in_progress "$req"
task T-CF-5 in_progress null P0
task T-CF-6 ready "$req" P1
task T-CF-6-01 ready "$req"
task T-CF-7 done "$req" P1
task T-CF-8 review "$req" P3
git init -q "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
git -C "$state" add -A
git -C "$state" commit -q -m init

# the parent worktrees the monitor made: T-CF-3 and T-CF-7 with a herdr-tabs record, T-CF-6 without one
for t in T-CF-3 T-CF-6 T-CF-7 T-CF-4-01; do mkdir -p "$work/cf/$t"; done
for t in T-CF-3 T-CF-7; do
  mkdir -p "$work/cf/.harness/$t"
  printf '%s-lead tab-1 pane-1\n' "$t" > "$work/cf/.harness/$t/herdr-tabs"
done

mon() { # <T-id>: a Monitor task running herd-watch.sh on that herd
  printf '{"id":"b%s","type":"monitor","status":"running","description":"herd %s","command":"sh /p/bin/herd-watch.sh %s --interval 60"}' "$1" "$1" "$1"
}
stop() { # <cwd> <session id> <background_tasks JSON array> [<stop_hook_active>] -> rc on line 1, stderr after
  out=$( (cd "$1" && printf '{"session_id":"%s","hook_event_name":"Stop","stop_hook_active":%s,"background_tasks":%s}' \
    "$2" "${4:-false}" "$3" | WORK_DIR="$work" sh "$bin/rearm-check.sh" 2>&1 >/dev/null); printf '\n%s' $?)
  printf '%s\n' "${out##*
}"
  printf '%s' "${out%
*}"
}
rc() { printf '%s\n' "$1" | head -n1; }
err() { printf '%s\n' "$1" | sed 1d; }

# --- elsewhere: nothing ------------------------------------------------------------------
r=$(stop "$tmp/elsewhere" s1 '[]')
is 'elsewhere exits 0' 0 "$(rc "$r")"
is 'elsewhere prints nothing' '' "$(err "$r")"

# --- the state clone: every live herd of a request ---------------------------------------
r=$(stop "$state" s2 '[]')
e=$(err "$r")
is 'the state clone with no watcher exits 2' 2 "$(rc "$r")"
has 'an in_progress parent is listed as a herd-list line' "$req P1 T-CF-3 cf in_progress" "$e"
has 'a parent with a block in flight is listed, priority P2 by default' "$req P2 T-CF-4 cf ready" "$e"
has 'a parent in review is listed' "$req P3 T-CF-8 cf review" "$e"
lacks 'a parent without a request is not a herd of the CEO' 'T-CF-5' "$e"
lacks 'a ready parent with no block in flight is not listed' 'T-CF-6' "$e"
lacks 'a done parent is not listed' 'T-CF-7' "$e"
lacks 'a block is never a herd of its own' 'T-CF-4-01' "$e"
has 'the message names herd-watch.sh and the Monitor tool' yes \
  "$(printf '%s' "$e" | grep -q 'herd-watch.sh' && printf '%s' "$e" | grep -q 'Monitor' && echo yes)"

r=$(stop "$state" s3 "[$(mon T-CF-3)]")
e=$(err "$r")
is 'one herd watched, the others not: exit 2' 2 "$(rc "$r")"
lacks 'the watched herd is not listed' 'T-CF-3 ' "$e"
has 'an unwatched herd still is' "$req P2 T-CF-4 cf ready" "$e"

r=$(stop "$state" s4 "[$(mon T-CF-3),$(mon T-CF-4),$(mon T-CF-8)]")
is 'every herd watched exits 0' 0 "$(rc "$r")"
is 'and prints nothing' '' "$(err "$r")"

r=$(stop "$state" s5 '[{"id":"b1","type":"monitor","status":"running","description":"herd-watch.sh T-CF-3"},{"id":"b2","type":"monitor","status":"running","description":"herd-watch.sh T-CF-4"},{"id":"b3","type":"monitor","status":"running","description":"sh herd-watch.sh T-CF-8 --interval 60"}]')
is 'a monitor naming herd-watch.sh in its description counts' 0 "$(rc "$r")"

# the harness reports a task the Monitor tool started as `local_bash`: any type counts, a finished task does not
r=$(stop "$state" s6 '[{"id":"b1","type":"local_bash","status":"running","description":"herd-watch.sh T-CF-3","command":"sh /p/bin/herd-watch.sh T-CF-3 --interval 60"}]')
lacks 'a running local_bash task naming herd-watch.sh watches its herd' 'T-CF-3 ' "$(err "$r")"
r=$(stop "$state" s12 '[{"id":"b1","type":"local_bash","status":"completed","command":"sh herd-watch.sh T-CF-3"},{"id":"b2","type":"monitor","status":"killed","command":"sh herd-watch.sh T-CF-3"}]')
has 'a finished task watches nothing' "$req P1 T-CF-3 cf in_progress" "$(err "$r")"

r=$(stop "$state" s7 "[$(mon T-CF-30)]")
has 'a watcher of T-CF-30 does not watch T-CF-3' "$req P1 T-CF-3 cf in_progress" "$(err "$r")"

r=$(stop "$state" s8 '[{"id":"b1","type":"monitor","status":"running","description":"mr-watch T-CF-3","command":"sh mr-watch.sh T-CF-3"}]')
has 'a monitor without herd-watch.sh does not count' "$req P1 T-CF-3 cf in_progress" "$(err "$r")"

# --- stop_hook_active, the per-session budget, nothing in the state clone ---------------
r=$(stop "$state" s9 '[]' true)
is 'stop_hook_active true exits 0' 0 "$(rc "$r")"
is 'stop_hook_active true prints nothing' '' "$(err "$r")"

is 'first block of a session' 2 "$(rc "$(stop "$state" s10 '[]')")"
is 'second block of the same session' 2 "$(rc "$(stop "$state" s10 '[]')")"
is 'a third Stop of the same session passes' 0 "$(rc "$(stop "$state" s10 '[]')")"
is 'another session starts its own count' 2 "$(rc "$(stop "$state" s11 '[]')")"
is 'the CEO counter sits in the git dir of the state clone' 2 "$(cat "$state/.git/.harness-rearm-s10" 2>/dev/null)"
is 'and nothing lands in the factory root' '' "$(ls -A "$work" | grep 'harness-rearm')"
is 'the state clone stays clean' '' "$(git -C "$state" status --porcelain)"

# --- a parent worktree: that herd only ---------------------------------------------------
r=$(stop "$work/cf/T-CF-3" p1 '[]')
e=$(err "$r")
is 'a parent worktree with no watcher exits 2' 2 "$(rc "$r")"
has 'it lists its own herd' "$req P1 T-CF-3 cf in_progress" "$e"
lacks 'and no other' 'T-CF-4|T-CF-8' "$e"
is 'its counter sits in the stamp directory of the task' 1 "$(cat "$work/cf/.harness/T-CF-3/.harness-rearm-p1" 2>/dev/null)"
is 'a parent worktree whose herd is watched exits 0' 0 "$(rc "$(stop "$work/cf/T-CF-3" p2 "[$(mon T-CF-3)]")")"
is 'a parent worktree with no herdr unit is no herd' 0 "$(rc "$(stop "$work/cf/T-CF-6" p3 '[]')")"
is 'a done parent needs no watcher' 0 "$(rc "$(stop "$work/cf/T-CF-7" p4 '[]')")"
is 'a block worktree is no herd' 0 "$(rc "$(stop "$work/cf/T-CF-4-01" p5 '[]')")"
is 'the state clone stays clean after the worktree stops' '' "$(git -C "$state" status --porcelain)"

# --- the state clone: a parent in the pre-approval chain (triage, chart, grill, decompose) ----
# an open step record in `.harness/<T-id>/herdr-tabs` is a herd; a closed one, or a block's record, is not
task T-CF-9 draft "$req" P1
task T-CF-2 draft "$req"
mkdir -p "$work/cf/.harness/T-CF-9" "$work/cf/.harness/T-CF-2"
printf 'T-CF-9-triage tab-8 pane-8 sid-8\nT-CF-9-triage tab-8 closed\nT-CF-9-grill tab-9 pane-9\n' \
  > "$work/cf/.harness/T-CF-9/herdr-tabs"
printf 'T-CF-2-chart tab-7 pane-7\nT-CF-2-chart tab-7 closed\nT-CF-2-01 tab-6 pane-6\n' \
  > "$work/cf/.harness/T-CF-2/herdr-tabs"
r=$(stop "$state" c1 "[$(mon T-CF-3),$(mon T-CF-4),$(mon T-CF-8)]")
e=$(err "$r")
is 'a parent with an open step record and no watcher exits 2' 2 "$(rc "$r")"
has 'it is listed as a herd-list line' "$req P1 T-CF-9 cf draft" "$e"
lacks 'a parent whose step records are closed is not listed' 'T-CF-2 ' "$e"
is 'a watched chain parent exits 0' 0 "$(rc "$(stop "$state" c2 "[$(mon T-CF-3),$(mon T-CF-4),$(mon T-CF-8),$(mon T-CF-9)]")")"

# --- what the hook cannot read lets the Stop through ------------------------------------
out=$( (cd "$state" && printf 'not json' | WORK_DIR="$work" sh "$bin/rearm-check.sh" >/dev/null 2>&1); echo $?)
is 'unreadable hook JSON exits 0' 0 "$out"
out=$( (cd "$state" && printf '{"hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[]}' \
  | WORK_DIR="$work" sh "$bin/rearm-check.sh" >/dev/null 2>&1); echo $?)
is 'no session id exits 0' 0 "$out"

exit $fail
