#!/bin/sh
# The musts of a grill, checked over the plan it ends with instead of restated in prose (slim-harness M6).
#
#   plan-lint.sh <plan-ready.md>
#
# It reads one plan-ready.md and names every violation of the rules the grill cannot leave open:
#
#   a gap ledger row whose `state` is not `closed`
#   a proposal whose `acceptance:` is not a backticked command
#   a proposal with no `docs:` line
#   a `## Program design` member named in no proposal, or named in two
#   a `tier`, `archetype` or `complexity` outside the allowed values, or missing
#   a `red` proposal with no `## Quality scenarios` row
#
# invariant: under a `### `path`` heading of `## Program design`, a line that ends with a full stop is one of
# invariant: the at most two sentences describing the member above it, and every other non-blank line is a
# invariant: member signature. That is the shape the grill's design round writes and plan-ready.md shows.
#
# invariant: a proposal names a member when the member's name stands in its `design:` value bounded by
# invariant: non-identifier characters and not followed by a dot, so `IExporter.ExportAsync` names
# invariant: `ExportAsync` and `src/Export/IExporter.cs` names neither, a slash being a boundary that does
# invariant: not open a name.
#
# Exit 0: `plan ok: N proposals` on stdout.
# Exit 1: every violation on stderr, one per line, or the plan could not be read.
set -eu

die() { printf 'plan-lint: %s\n' "$1" >&2; exit 1; }

[ $# -ge 1 ] || die "usage: plan-lint.sh <plan-ready.md>"
[ $# -eq 1 ] || die "one plan at a time: plan-lint.sh <plan-ready.md>"
[ -f "$1" ] || die "no such plan: $1"

out=$(awk '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function bad(m) { viol[++nv] = m }
  function member_name(s,   t, n, a, i, last) {
    t = s
    sub(/\(.*$/, "", t)
    n = split(t, a, /[^A-Za-z0-9_]+/)
    last = ""
    for (i = 1; i <= n; i++) if (a[i] != "") last = a[i]
    return last
  }
  function named(hay, needle,   i, left, right, rest) {
    rest = hay
    while ((i = index(rest, needle)) > 0) {
      left = (i == 1) ? "" : substr(rest, i - 1, 1)
      right = substr(rest, i + length(needle), 1)
      if (left !~ /[A-Za-z0-9_\/]/ && right !~ /[A-Za-z0-9_.\/]/) return 1
      rest = substr(rest, i + length(needle))
    }
    return 0
  }
  function enum(prop, key, value, allowed,   n, a, i) {
    if (value == "") { bad("proposal " prop " has no " key); return }
    n = split(allowed, a, "|")
    for (i = 1; i <= n; i++) if (value == a[i]) return
    bad("proposal " prop " has " key " `" value "`, not one of " allowed)
  }
  function first_word(v,   a, n) {
    n = split(v, a, /[ \t,;]+/)
    return n ? a[1] : ""
  }

  /^## / {
    sec = trim(substr($0, 4))
    design_file = ""
    next
  }

  sec == "Program design" && /^### / {
    design_file = $0
    sub(/^### /, "", design_file)
    gsub(/`/, "", design_file)
    sub(/ \(.*$/, "", design_file)
    next
  }

  sec == "Program design" && design_file != "" {
    line = trim($0)
    if (line == "") next
    if (line ~ /\.$/) next
    mname[++nm] = member_name(line)
    mfile[nm] = design_file
    next
  }

  sec == "Proposed tasks" && /^### / {
    prop = trim(substr($0, 5))
    np++
    ptitle[np] = prop
    next
  }

  sec == "Proposed tasks" && np > 0 && /^[-*][ \t]/ {
    line = trim($0)
    sub(/^[-*][ \t]+/, "", line)
    c = index(line, ":")
    if (c == 0) next
    key = trim(substr(line, 1, c - 1))
    value = trim(substr(line, c + 1))
    if (key == "tier") ptier[np] = first_word(value)
    else if (key == "archetype") parch[np] = first_word(value)
    else if (key == "complexity") pcomp[np] = first_word(value)
    else if (key == "acceptance") { pacc[np] = value; hasacc[np] = 1 }
    else if (key == "docs") hasdocs[np] = 1
    else if (key == "design") pdesign[np] = value
    next
  }

  sec == "Quality scenarios" && /^\|/ {
    if ($0 ~ /^\|[ \t|:-]*\|[ \t|:-]*$/) next
    qsline++
    next
  }

  sec == "Gap ledger" && /^\|/ {
    if ($0 ~ /^\|[ \t|:-]*\|[ \t|:-]*$/) next
    gaprow++
    if (gaprow == 1) next
    n = split($0, cell, "|")
    row = trim(cell[2])
    state = (n >= 5) ? trim(cell[5]) : ""
    if (state != "closed") bad("gap ledger row " row " has state `" state "`, not `closed`")
    next
  }

  END {
    if (np == 0) bad("the plan has no proposal under `## Proposed tasks`")
    for (p = 1; p <= np; p++) {
      enum(p, "tier", ptier[p], "green|yellow|red")
      enum(p, "archetype", parch[p], "feature|bugfix|refactor|research")
      enum(p, "complexity", pcomp[p], "low|medium|high")
      if (!hasacc[p]) bad("proposal " p " has no `acceptance:`")
      else if (pacc[p] !~ /^`[^`]+`/) bad("proposal " p " has an `acceptance:` that is not a backticked command: " pacc[p])
      if (!hasdocs[p]) bad("proposal " p " has no `docs:`")
      if (ptier[p] == "red" && qsline < 2)
        bad("proposal " p " is red and the plan has no `## Quality scenarios` row")
    }
    for (m = 1; m <= nm; m++) {
      owners = 0
      for (p = 1; p <= np; p++) if (named(pdesign[p], mname[m])) owners++
      if (owners == 0) bad("`" mfile[m] "` member `" mname[m] "` is named in no proposal `design:`")
      else if (owners > 1) bad("`" mfile[m] "` member `" mname[m] "` is named in " owners " proposals, and a member belongs to exactly one")
    }
    for (i = 1; i <= nv; i++) print "V " viol[i]
    print "N " np
  }
' "$1")

violations=$(printf '%s\n' "$out" | sed -n 's/^V //p')
if [ -n "$violations" ]; then
  printf '%s\n' "$violations" | sed 's/^/plan-lint: /' >&2
  exit 1
fi
printf 'plan ok: %s proposals\n' "$(printf '%s\n' "$out" | sed -n 's/^N //p')"
