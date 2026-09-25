#!/bin/sh
# The dispatch queue of the leads: the approved parents a lead may be started for, best first. Read-only, nothing
# is written, nothing is committed; session-monitor.sh --queue takes the lines from the top while capacity allows.
#
#   queue-next.sh [--max N] [--state <dir>]
#
# One line per parent, `<T-id> <key> <priority> <request>`, for a parent that is `ready`, has a `request:`, has
# `owner: null` (the lead claims it, the queue claims nothing), has no open `<T-id>-lead` tab record
# (herdr-tabs.sh state), and whose every depends_on is done: `done` or `closed`, or archived. An id with no task
# file at all is not done. A parent with open blocks also needs one block whose own depends_on are all done.
#
# PLAN 3.2 [XR] 4 (DECISIONS D20): a lead that ended because every remaining block waited on another parent
# leaves its parent `in_progress` (setting it back to `ready` is a human gate) and those blocks `blocked`. Such a
# parent is in the queue too, whatever its owner (the new lead reclaims it with `state-report.sh --owner`), when
# it has a `request:`, no open `<T-id>-lead` tab record, and one runnable block again: a block that is neither
# done nor closed and whose every depends_on is done or archived. Same line, same order.
#
# The priority printed is the effective one: the best of the parent's own (`P2` when it has none) and that of
# every open task depending on it, directly or through another open task, so a P0 request waiting on a P3 parent
# lifts it. The id order of sort_ids (legacy ids, then alias ids) breaks a tie. --max N prints the first N.
#
# Exit 0 with the lines, or nothing when no parent is dispatchable; 1 on bad usage.
set -eu

max='' state=''
here=$(dirname -- "$0")
die() { printf 'queue-next: %s\n' "$1" >&2; exit 1; }
usage='usage: queue-next.sh [--max N] [--state <dir>]'

while [ $# -gt 0 ]; do
  case "$1" in
    --max|--state)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --max) max=$2 ;; --state) state=$2 ;; esac
      shift 2 ;;
    *) die "unknown argument '$1'; $usage" ;;
  esac
done
case "$max" in '') ;; 0*|*[!0-9]*) die "--max takes a number of 1 or more, not '$max'" ;; esac

. "$here/lib-tasks.sh"

if [ -z "$state" ]; then state=$(resolve_state_dir "$PWD"); fi
case "$state" in /*|[A-Za-z]:/*) ;; *) state="$PWD/$state" ;; esac
state=$(printf '%s' "$state" | sed 's:/*$::')
[ -d "$state/repos" ] || die "$state is not a state clone, pass --state <dir>"

set --
while IFS= read -r f; do [ -z "$f" ] || set -- "$@" "$f"; done <<EOF
$(task_files --all)
EOF
[ $# -gt 0 ] || exit 0

# invariant: one awk over every task file, live and archived; the frontmatter is flat `key: value`
# (task-new.sh writes it), depends_on the inline list `[a, b]` dag-check.sh reads.
# invariant: the priority is relaxed along the dependent edges once per task at most, so a depends_on cycle
# ends the loop instead of spinning.
awk -v prefix="$state/repos/" '
  function rank(p) { return p == "P0" ? 0 : p == "P1" ? 1 : p == "P3" ? 3 : 2 }
  function nul(v) { return v == "" || v == "null" }
  function flush(   i, m, d) {
    if (id == "" || (id in seen)) return
    seen[id] = 1; n++
    ids[n] = id; key[id] = k; st[id] = f["status"]; req[id] = f["request"]; own[id] = f["owner"]
    live[id] = !arch
    fin[id] = arch || f["status"] == "done" || f["status"] == "closed"
    eff[id] = rank(f["priority"])
    d = f["depends_on"]; gsub(/[][,"'"'"']/, " ", d)
    m = split(d, a, /[ \t]+/); nd[id] = 0
    for (i = 1; i <= m; i++) if (a[i] != "") { nd[id]++; dep[id, nd[id]] = a[i] }
  }
  FNR == 1 {
    flush(); split("", f); id = ""; fm = 0
    rest = substr(FILENAME, length(prefix) + 1); k = rest; sub(/\/.*$/, "", k)
    arch = index(rest, "/archive/") > 0
  }
  FNR == 1 && /^---[ \t\r]*$/ { fm = 1; next }
  fm && /^---[ \t\r]*$/ { fm = 0; next }
  fm {
    c = index($0, ":"); if (c < 2 || $0 ~ /^[ \t#]/) next
    name = substr($0, 1, c - 1); if (name in f) next
    v = substr($0, c + 1); sub(/[ \t]+#.*$/, "", v); gsub(/^[ \t]+|[ \t\r]+$/, "", v)
    f[name] = v; if (name == "id") id = v
    next
  }
  function done_all(t,   i) {
    for (i = 1; i <= nd[t]; i++) if (!((dep[t, i]) in fin) || !fin[dep[t, i]]) return 0
    return 1
  }
  END {
    flush()
    for (r = 0; r < n; r++) {
      changed = 0
      for (x = 1; x <= n; x++) {
        t = ids[x]; if (fin[t]) continue
        for (i = 1; i <= nd[t]; i++) {
          d = dep[t, i]
          if ((d in eff) && eff[t] < eff[d]) { eff[d] = eff[t]; changed = 1 }
        }
      }
      if (!changed) break
    }
    for (x = 1; x <= n; x++) {
      t = ids[x]
      if (!live[t] || fin[t] || t !~ /^T-([A-Z]+-)?[0-9]+$/) continue
      if (nul(req[t])) continue
      if (st[t] == "ready") { if (!nul(own[t]) || !done_all(t)) continue }
      else if (st[t] != "in_progress") continue
      open = 0; runnable = 0
      for (y = 1; y <= n; y++) {
        b = ids[y]
        if (!live[b] || fin[b] || index(b, t "-") != 1 || substr(b, length(t) + 2) !~ /^[0-9]+$/) continue
        open = 1; if (done_all(b)) { runnable = 1; break }
      }
      if (open && !runnable) continue
      if (st[t] == "in_progress" && !runnable) continue
      print t, key[t], "P" eff[t], req[t]
    }
  }' "$@" \
  | sort_ids \
  | awk '{ b[$3] = b[$3] $0 "\n" } END { printf "%s%s%s%s", b["P0"], b["P1"], b["P2"], b["P3"] }' \
  | { n=0
      while read -r id k prio req; do
        [ "$(sh "$here/herdr-tabs.sh" state "$id-lead" --state "$state" 2>/dev/null || :)" != open ] || continue
        printf '%s %s %s %s\n' "$id" "$k" "$prio" "$req"
        n=$((n + 1))
        [ -z "$max" ] || [ "$n" -lt "$max" ] || break
      done; }
