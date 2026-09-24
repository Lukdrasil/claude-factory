#!/bin/sh
# One block task file per proposal of a grilled plan, derived instead of hand-written (the `decompose` skill,
# step 3). The mapping is 1:1 and mechanical by contract (skills/architect-review/references/cut-check.md
# item 1, skills/decompose/references/fields.md), so the model reviews the result instead of typing it.
#
#   decompose.sh <plan-ready.md> --out <dir> [--state <dir>]
#                                            the state clone; default $WORK_DIR/state, else what the cwd
#                                            resolves to, else the plan's own ancestors
#
# The files land as <out>/<NN>-<slug>.md in the shape `task-template.sh block` prints, and one manifest line
# per proposal goes to stdout, ascending: `<N> <file> <depends_on ordinals, or ->`. The ordinals stay
# ordinals; only the writer that assigns ids can turn them into `depends_on`.
#
# Exit 0: the manifest on stdout, nothing else.
# Exit 1: the reason on stderr and nothing written: no plan, an unreadable plan, no --out, a plan-lint.sh
# refusal (passed through), a proposal missing goal, acceptance, tier, archetype or complexity, a
# `design:` naming a member no `## Program design` heading owns, or a proposal other than a research one with
# `design: none` whose `design:` names no member, which would be a block with no ``### `path` `` heading.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'decompose: %s\n' "$1" >&2; exit 1; }

plan='' out='' state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || die "--out needs a value"; out=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$plan" ] || die "one plan at a time"; plan=$1; shift ;;
  esac
done
[ -n "$plan" ] || die "usage: decompose.sh <plan-ready.md> --out <dir> [--state <dir>]"
[ -f "$plan" ] || die "no such plan: $plan"
[ -r "$plan" ] || die "cannot read the plan: $plan"
[ -n "$out" ] || die "--out <dir> is required"

here=$(pwd)
case "$plan" in /*|[A-Za-z]:/*) planabs=$plan ;; *) planabs="$here/$plan" ;; esac
planabs=$(norm_path "$planabs")

# see: block-brief.sh, the same resolution, with one more fallback: the plan itself sits at
# see: <state>/repos/<key>/plans/<slug>-plan-ready.md, so its ancestors name the clone when nothing else does
if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    state=$(resolve_state_dir "$here")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$here/$state" ;; esac
    if [ ! -d "$state/repos" ]; then
      up=${planabs%/*}; up=${up%/*}; up=${up%/*}; up=${up%/*}
      [ -d "$up/repos" ] && state=$up
    fi
  fi
fi
state=$(norm_path "$state")

"$(dirname -- "$0")/plan-lint.sh" "$plan" >/dev/null || exit 1

repo=$(sed -n '1,/^---[ \t]*$/!d; s/^repo:[ \t]*//p' "$plan" | head -n1)
ptask=$(sed -n '1,/^---[ \t]*$/!d; s/^task:[ \t]*//p' "$plan" | head -n1)
[ -n "$repo" ] || die "the plan has no frontmatter \`repo:\`"

# invariant: task_of reads the shell variable $state, it takes no state argument
forge=''
if [ -n "$ptask" ] && [ "$ptask" != none ]; then
  src=$(task_of "$ptask" || :)
  [ -n "$src" ] && forge=$(sed -n 's/^- forge issue:[ \t]*//p' "$src" | head -n1)
fi

case "$planabs" in
  "$state"/*) rel=${planabs#"$state"/} ;;
  *) rel="repos/$repo/plans/${planabs##*/}" ;;
esac

# E (2026-09-22, MR !412): a proposal's `goal:` is written straight into the block's `# Goal`, and that line is
# the MR title the block will open. The check runs over the plan before any file is written, so a plan whose
# goals cannot be titles leaves nothing behind, the way every other refusal here does. Triage and research
# goals never become titles.
goals=$(awk '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  /^##[ \t]+Proposed tasks[ \t]*$/ { ps = 1; next }
  /^##[ \t]/ { if (ps && have) { print arch "\t" goal; have = 0 } ; ps = 0; next }
  !ps { next }
  /^###[ \t]/ { if (have) print arch "\t" goal; arch = ""; goal = ""; have = 1; next }
  /^-[ \t]*goal:/ { g = $0; sub(/^-[ \t]*goal:[ \t]*/, "", g); goal = trim(g); next }
  /^-[ \t]*archetype:/ { a = $0; sub(/^-[ \t]*archetype:[ \t]*/, "", a); sub(/[ \t,].*$/, "", a); arch = trim(a); next }
  END { if (ps && have) print arch "\t" goal }
' "$plan")
badgoals=$(printf '%s\n' "$goals" | while IFS="$(printf '\t')" read -r garch ggoal; do
    [ -n "$ggoal" ] || continue
    case "$garch" in triage|research) continue ;; esac
    reason=$(mr_title_check "$ggoal" "$repo") || printf 'the `goal:` of a proposal cannot be the MR title it becomes: %s (`%s`)\n' "$reason" "$ggoal"
  done)
if [ -n "$badgoals" ]; then
  printf '%s\n' "$badgoals" | sed 's/^/decompose: /' >&2
  exit 1
fi

mkdir -p "$out"
result=$(awk -v outdir="$out" -v repo="$repo" -v rel="$rel" -v forge="$forge" \
             -v today="$(date +%Y-%m-%d)" '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function bad(m) { viol[++nv] = m }

  # see: plan-lint.sh, the member-naming rule of the design round, applied here to the same two questions
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
  function first_word(v,   a, n) { n = split(v, a, /[ \t,;]+/); return n ? a[1] : "" }
  function slug_of(title,   n, a, i, s) {
    n = split(title, a, /[ \t]+/)
    s = ""
    for (i = 1; i <= n && i <= 6; i++) s = s " " a[i]
    s = tolower(s)
    gsub(/[^a-z0-9]+/, "-", s)
    sub(/^-+/, "", s); sub(/-+$/, "", s)
    return s
  }
  function prefix_of(arch) {
    if (arch == "feature") return "feat"
    if (arch == "bugfix") return "fix"
    return arch
  }
  # invariant: the converse of named(): every member-shaped term of a `design:` value must be a member some
  # invariant: heading owns. A term carrying a slash, or spelling a heading path or its basename, is a file
  # invariant: reference; a term with neither an underscore, an inner case change nor a parenthesis is prose.
  function check_design(p,   v, n, a, i, t, cand, dot) {
    v = pdesign[p]
    if (v == "" || tolower(v) == "none") return
    gsub(/`/, " ", v)
    n = split(v, a, /[ \t,;]+/)
    for (i = 1; i <= n; i++) {
      t = a[i]
      sub(/^[(]+/, "", t); sub(/[.,;:)]+$/, "", t)
      if (t == "" || index(t, "/") > 0 || (t in isfile)) continue
      cand = t
      sub(/\(.*$/, "", cand)
      while ((dot = index(cand, ".")) > 0) cand = substr(cand, dot + 1)
      if (cand == "" || cand in isfile) continue
      if (cand !~ /_/ && cand !~ /[a-z][A-Z]/ && index(t, "(") == 0) continue
      if (!(cand in ismember))
        bad("proposal " pn[p] " names `" cand "` in its `design:` and no `## Program design` heading owns it")
    }
  }

  NR == 1 && /^---[ \t]*$/ { infm = 1; next }
  infm && /^---[ \t]*$/ { infm = 0; next }
  infm { next }

  /^## / { sec = trim(substr($0, 4)); design_file = ""; next }

  sec == "Decisions" && /^[-*][ \t]/ { dec[++nd] = $0; next }
  sec == "Terms" && /^[-*][ \t]/ { term[++nt] = $0; next }

  sec == "Program design" && /^### / {
    hline[++nh] = $0
    f = $0
    sub(/^### /, "", f); gsub(/`/, "", f); sub(/ \(.*$/, "", f)
    f = trim(f)
    isfile[f] = 1
    base = f; sub(/^.*\//, "", base); isfile[base] = 1
    design_file = f
    curm = 0
    next
  }
  sec == "Program design" && design_file != "" {
    line = trim($0)
    if (line == "") next
    if (line ~ /\.$/) { if (curm) mdesc[curm] = mdesc[curm] $0 "\n"; next }
    mraw[++nm] = $0
    mhead[nm] = nh
    mname[nm] = member_name(line)
    mdesc[nm] = ""
    ismember[mname[nm]] = 1
    curm = nm
    next
  }

  sec == "Proposed tasks" && /^### / {
    head = trim(substr($0, 5))
    np++
    num = head; sub(/[^0-9].*$/, "", num)
    title = head; sub(/^[0-9]+\.?[ \t]*/, "", title)
    pn[np] = (num == "") ? np : num + 0
    ptitle[np] = title
    next
  }
  sec == "Proposed tasks" && np > 0 && insteps && /^[ \t]+[-*][ \t]/ {
    s = trim($0); sub(/^[-*][ \t]+/, "", s); pstep[np, ++nstep[np]] = s; next
  }
  sec == "Proposed tasks" && np > 0 && /^[-*][ \t]/ {
    insteps = 0
    line = trim($0)
    sub(/^[-*][ \t]+/, "", line)
    c = index(line, ":")
    if (c == 0) next
    key = trim(substr(line, 1, c - 1))
    value = trim(substr(line, c + 1))
    if (key == "tier") ptier[np] = first_word(value)
    else if (key == "archetype") parch[np] = first_word(value)
    else if (key == "complexity") pcomp[np] = first_word(value)
    else if (key == "acceptance") pacc[np] = value
    else if (key == "docs") pdocs[np] = value
    else if (key == "design") pdesign[np] = value
    else if (key == "goal") pgoal[np] = value
    else if (key == "context") pctx[np] = value
    else if (key == "out of scope") poos[np] = value
    else if (key == "depends_on") pdep[np] = value
    else if (key == "steps") insteps = 1
    next
  }

  sec == "Out of scope" { oos[++no] = $0; next }

  END {
    if (np == 0) bad("the plan has no proposal under `## Proposed tasks`")
    for (p = 1; p <= np; p++) {
      if (pgoal[p] == "") bad("proposal " pn[p] " has no `goal:`")
      if (pacc[p] == "") bad("proposal " pn[p] " has no `acceptance:`")
      if (ptier[p] == "") bad("proposal " pn[p] " has no `tier:`")
      if (parch[p] == "") bad("proposal " pn[p] " has no `archetype:`")
      if (pcomp[p] == "") bad("proposal " pn[p] " has no `complexity:`")
      check_design(p)
      if (parch[p] == "research" && tolower(pdesign[p]) == "none") continue
      owned = 0
      for (m = 1; m <= nm && !owned; m++) if (named(pdesign[p], mname[m])) owned = 1
      if (!owned) bad("proposal " pn[p] " (" ptitle[p] ") names no `## Program design` member, so its block would have no ``### `path` `` heading")
    }
    if (nv > 0) {
      for (i = 1; i <= nv; i++) print "E " viol[i]
      exit 0
    }

    while (no > 0 && trim(oos[no]) == "") no--
    ostart = 1
    while (ostart <= no && trim(oos[ostart]) == "") ostart++

    for (p = 1; p <= np; p++) {
      slug = slug_of(ptitle[p])
      f = sprintf("%s/%02d-%s.md", outdir, pn[p], slug)
      print "---" > f
      print "id: T-000" > f
      print "repo: " repo > f
      print "branch: " prefix_of(parch[p]) "/" slug > f
      print "status: draft" > f
      print "tier: " ptier[p] > f
      print "archetype: " parch[p] > f
      print "complexity: " pcomp[p] > f
      print "runtime: default" > f
      print "depends_on: []" > f
      print "parallel_group: null" > f
      print "attempt: 0" > f
      print "max_attempts: 3" > f
      print "plan_hash: null" > f
      print "owner: null" > f
      print "mr_url: null" > f
      print "created: " today > f
      print "---" > f
      print "" > f
      print "# Goal" > f
      print pgoal[p] > f
      print "" > f
      print "## Context" > f
      print "From the plan `" rel "`" > f
      if (pctx[p] != "") print pctx[p] > f
      if (nt > 0) {
        print "" > f
        print "Terms (from the grill):" > f
        for (i = 1; i <= nt; i++) print term[i] > f
      }
      if (nd > 0) {
        print "" > f
        print "Decisions (from the grill):" > f
        for (i = 1; i <= nd; i++) print dec[i] > f
      }
      print "" > f
      print "Design (approved in the grill):" > f
      if (tolower(pdesign[p]) == "none" || pdesign[p] == "") {
        print "none" > f
      } else {
        for (h = 1; h <= nh; h++) {
          shown = 0
          for (m = 1; m <= nm; m++) {
            if (mhead[m] != h || !named(pdesign[p], mname[m])) continue
            if (!shown) { print hline[h] > f; shown = 1 }
            print mraw[m] > f
            if (mdesc[m] != "") printf "%s", mdesc[m] > f
          }
        }
      }
      print "" > f
      print "## Acceptance" > f
      print pacc[p] > f
      print "" > f
      print "## Docs" > f
      print (pdocs[p] == "" ? "none" : pdocs[p]) > f
      print "" > f
      print "## Out of scope" > f
      if (poos[p] != "") print poos[p] > f
      if (no >= ostart) {
        print "" > f
        print "Whole spec:" > f
        for (i = ostart; i <= no; i++) print oos[i] > f
      }
      if (nstep[p] > 0) {
        print "" > f
        print "## Checklist" > f
        for (i = 1; i <= nstep[p]; i++) print "- [ ] " pstep[p, i] > f
      }
      if (forge != "") {
        print "" > f
        print "## Internal" > f
        print "- forge issue: " forge > f
      }
      print "" > f
      print "## Attempts" > f
      close(f)

      deps = pdep[p]
      gsub(/[^0-9,]/, "", deps)
      gsub(/,+/, ",", deps); sub(/^,/, "", deps); sub(/,$/, "", deps)
      print "M " pn[p] " " f " " (deps == "" ? "-" : deps)
    }
  }
' "$plan")

errors=$(printf '%s\n' "$result" | sed -n 's/^E //p')
if [ -n "$errors" ]; then
  printf '%s\n' "$errors" | sed 's/^/decompose: /' >&2
  # why: awk writes the files after its own validation, so the directory has to exist before it runs, and a
  # why: refusal that left it empty takes it away again: nothing written means nothing left behind
  rmdir "$out" 2>/dev/null || :
  exit 1
fi
printf '%s\n' "$result" | sed -n 's/^M //p'
