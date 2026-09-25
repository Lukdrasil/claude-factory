#!/bin/sh
# decompose.sh over a throwaway state clone: three proposals become three block files, the frontmatter is the
# proposal's own values, each design section carries exactly the members the proposal names, the manifest
# repeats the plan's ordinals, the source task's forge issue is copied over, and a plan with an open gap
# ledger row is refused without writing anything. The terms and the locked tag are carried into the context, and
# the ledger's `deps` column does not move the `state` plan-lint reads. T-253: the sub-bullet `steps:` of a
# proposal become the block's `## Checklist`, plan-lint refuses a missing or malformed `steps:`, and
# block-brief.sh carries the checklist outside the design.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

state="$tmp/state"
mkdir -p "$state/repos/demo/plans" "$state/repos/demo/tasks" "$tmp/out"
printf 'demo: { path: %s }\n' "$tmp/demo" > "$state/repos.yml"

cat > "$state/repos/demo/tasks/T-005-demo.md" <<'EOF'
---
id: T-005
repo: demo
status: ready
---

# Goal
feat(demo): export the rows

## Internal
- forge issue: https://example.test/i/1
EOF

plan="$state/repos/demo/plans/x-plan-ready.md"
cat > "$plan" <<'EOF'
---
repo: demo
task: T-005
created: 2026-09-20
---

# Spec
The rows should leave the box as a file.

## Terms
- **stream**: one ordered sequence of rows from one source. Avoid: feed, channel

## Decisions
- [locked] csv, not xlsx: the consumer is a shell pipeline, the human chose it; rejected: xlsx, no shell reader
- one writer per stream: no buffering across streams

## Program design
The sketch approved in the design round.

### `src/export/exporter.py` (new)
def export_rows(rows, fh)
  Writes every row of the stream into the open handle.
def write_header(fh)
  Writes the column header once, before the first row.

### `src/export/cli.py` (new)
def run_export(args)
  Parses the arguments and drives the exporter.

## Proposed tasks

### 1. Research the export formats available today
- tier: green, reading only
- archetype: research
- complexity: low, one afternoon
- depends_on: []
- goal: research(export): survey the formats the consumers already read
- context: the consumers are shell pipelines, see the decisions below
- acceptance: `test -f research/export-formats.md`
- docs: none
- design: none
- out of scope: writing any exporter code

### 2. Write the exporter core
- tier: yellow, new module
- archetype: feature
- complexity: medium, two files
- depends_on: [1]
- goal: feat(export): write the rows of a stream into an open handle
- context: the module is new, nothing imports it yet
- acceptance: `pytest tests/test_exporter.py`
- docs: docs/export.md
- design: `src/export/exporter.py` export_rows, `src/export/cli.py` run_export
- steps:
  - a
  - b
- out of scope: the column header

### 3. Fix the header writer
- tier: green, one function
- archetype: bugfix
- complexity: low, one function
- depends_on: [2]
- goal: fix(export): write the column header once before the first row
- context: the header belongs to the same module as the row writer
- acceptance: `pytest tests/test_header.py`
- docs: none
- design: `src/export/exporter.py` write_header
- steps: none
- out of scope: the cli

## Out of scope
No xlsx, and no streaming over the network.

## Gap ledger
| # | type | question | deps | state | answer |
|---|---|---|---|---|---|
| 1 | decision | csv or xlsx | - | closed | csv |
| 2 | decision | one writer per stream | 1 | closed | yes |
EOF

fail=0
check() { # <what> <test result as command already run: 0 ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
has() { # <what> <file> <pattern>
  grep -qF -- "$3" "$2"; check "$1" $?
}

out="$tmp/out"
manifest=$(sh "$bin/decompose.sh" "$plan" --out "$out" --state "$state" 2>"$tmp/err")
rc=$?
check 'the script exits 0' $rc
[ "$rc" -eq 0 ] || { cat "$tmp/err"; exit 1; }

n=$(ls "$out" | wc -l | tr -d '[:space:]')
[ "$n" = 3 ]; check 'three files are written' $?

f1="$out/01-research-the-export-formats-available-today.md"
f2="$out/02-write-the-exporter-core.md"
f3="$out/03-fix-the-header-writer.md"
[ -f "$f1" ] && [ -f "$f2" ] && [ -f "$f3" ]; check 'the file names are <NN>-<slug>.md' $?
[ -f "$f2" ] || { ls "$out"; exit 1; }

has 'the id is a placeholder'        "$f2" 'id: T-000'
has 'the repo is copied'             "$f2" 'repo: demo'
has 'a feature gets feat/'           "$f2" 'branch: feat/write-the-exporter-core'
has 'a bugfix gets fix/'             "$f3" 'branch: fix/fix-the-header-writer'
has 'research gets research/'        "$f1" 'branch: research/research-the-export-formats-available-today'
has 'the status is draft'            "$f2" 'status: draft'
has 'the tier is copied'             "$f2" 'tier: yellow'
has 'the archetype is copied'        "$f2" 'archetype: feature'
has 'the complexity is copied'       "$f2" 'complexity: medium'
[ "$(awk '/^---$/ { n++; next } n == 1 { sub(/:.*/, ""); print } n == 2 { exit }' "$f2" | sort | tr '\n' ' ')" = \
  'archetype attempt branch complexity created depends_on id mr_url owner plan_hash repo status tier ' ]
check 'the frontmatter holds exactly the task keys' $?
has 'the attempt count starts at 0'  "$f2" 'attempt: 0'
has 'depends_on is left empty'       "$f3" 'depends_on: []'
has 'plan_hash is null'              "$f2" 'plan_hash: null'
has 'the goal is the proposal goal'  "$f2" 'feat(export): write the rows of a stream into an open handle'
has 'the plan is named in context'   "$f2" 'From the plan `repos/demo/plans/x-plan-ready.md`'
has 'the decisions are carried over' "$f2" '- [locked] csv, not xlsx: the consumer is a shell pipeline, the human chose it'
has 'the terms are carried over'     "$f2" '- **stream**: one ordered sequence of rows from one source. Avoid: feed, channel'
has 'the acceptance keeps backticks' "$f2" '`pytest tests/test_exporter.py`'
has 'the docs value is carried over' "$f2" 'docs/export.md'
has 'the plan-level out of scope'    "$f2" 'No xlsx, and no streaming over the network.'
has 'the forge issue is copied'      "$f2" '- forge issue: https://example.test/i/1'
has 'the attempts section is last'   "$f2" '## Attempts'

design() { awk '/^Design \(approved in the grill\):/ { on = 1; next } on && /^## / { exit } on { print }' "$1"; }

d2=$(design "$f2")
printf '%s\n' "$d2" | grep -qF 'def export_rows(rows, fh)'; check 'block 2 owns export_rows' $?
printf '%s\n' "$d2" | grep -qF 'def run_export(args)'; check 'block 2 owns run_export' $?
printf '%s\n' "$d2" | grep -qF 'Writes every row of the stream into the open handle.'; check 'block 2 keeps the description' $?
printf '%s\n' "$d2" | grep -qF '### `src/export/exporter.py` (new)'; check 'block 2 keeps both headings' $?
printf '%s\n' "$d2" | grep -qF '### `src/export/cli.py` (new)'; check 'block 2 keeps the second heading' $?
printf '%s\n' "$d2" | grep -qF 'write_header'; [ $? -ne 0 ]; check 'block 2 has no member of block 3' $?

d3=$(design "$f3")
printf '%s\n' "$d3" | grep -qF 'def write_header(fh)'; check 'block 3 owns write_header' $?
printf '%s\n' "$d3" | grep -qF 'export_rows'; [ $? -ne 0 ]; check 'block 3 has no member of block 2' $?
printf '%s\n' "$d3" | grep -qF 'cli.py'; [ $? -ne 0 ]; check 'block 3 drops the heading it owns nothing in' $?

d1=$(design "$f1")
[ "$(printf '%s\n' "$d1" | grep -c .)" = 1 ] && printf '%s\n' "$d1" | grep -qx 'none'
check 'design: none writes the single line none' $?
grep -qF '## Internal' "$f1"; check 'the research block also gets the forge issue' $?

printf '%s\n' "$manifest" | grep -qx "1 $f1 -"; check 'the manifest has block 1 with no deps' $?
printf '%s\n' "$manifest" | grep -qx "2 $f2 1"; check 'the manifest carries the ordinal deps' $?
printf '%s\n' "$manifest" | grep -qx "3 $f3 2"; check 'the manifest is in ascending order' $?
[ "$(printf '%s\n' "$manifest" | grep -c .)" = 3 ]; check 'the manifest is the only output' $?

bad="$state/repos/demo/plans/open-plan-ready.md"
sed 's/^| 2 | decision | one writer per stream | 1 | closed | yes |/| 2 | decision | one writer per stream | 1 | open | |/' "$plan" > "$bad"
badout="$tmp/badout"
if sh "$bin/decompose.sh" "$bad" --out "$badout" --state "$state" >/dev/null 2>"$tmp/err2"; then
  printf 'FAIL an open gap ledger row is refused\n'; fail=1
else
  printf 'PASS an open gap ledger row is refused\n'
fi
grep -q 'gap ledger' "$tmp/err2"; check 'the plan-lint reason reaches stderr' $?
[ ! -d "$badout" ] || [ -z "$(ls -A "$badout")" ]; check 'the refusal writes nothing' $?

# F10 (T-228): a proposal whose `design:` owns no member under a heading became a block with no
# ``### `path` `` heading, which dag-check refused only after the cut reached the human. The fourth proposal
# leaves proposals 1 to 3 as they are, so plan-lint passes and the refusal can only come from decompose.
headless() { # <label> <design value>
  hp="$state/repos/demo/plans/headless-$1-plan-ready.md"
  hout="$tmp/headless-$1"
  awk -v design="$2" '
    /^## Out of scope/ {
      print "### 4. Pin LF line endings"
      print "- tier: green, one config file"
      print "- archetype: feature"
      print "- complexity: low, one file"
      print "- depends_on: []"
      print "- goal: feat(export): pin lf line endings for the exporter files"
      print "- context: the exporter files are checked out on two platforms"
      print "- acceptance: `sh tests/eol.sh`"
      print "- docs: none"
      print "- design: " design
      print "- steps: none"
      print "- out of scope: the exporter code"
      print ""
    }
    { print }
  ' "$plan" > "$hp"
  sh "$bin/plan-lint.sh" "$hp" >/dev/null 2>&1; check "$1: plan-lint accepts the plan" $?
  sh "$bin/decompose.sh" "$hp" --out "$hout" --state "$state" >/dev/null 2>"$tmp/herr"
  [ $? -eq 1 ]; check "$1: a block with no path heading is refused with exit 1" $?
  grep -qE 'proposal 4|Pin LF line endings' "$tmp/herr"; check "$1: the refusal names the block" $?
  [ ! -d "$hout" ] || [ -z "$(ls -A "$hout")" ]; check "$1: the refusal writes nothing" $?
}
headless none-with-prose 'none, a config file and a test with no code surface'
headless file-only '`src/export/cli.py`'
headless bare-none-on-a-feature 'none'

# F29 (sim, 2026-09-25): the grill left a plan whose goal could not be an MR title, and only decompose.sh
# refused it, after plan-check had signed that plan hash. plan-lint runs the same title check.
lp="$state/repos/demo/plans/long-goal-plan-ready.md"
awk '/^- goal: feat/ && !d { print "- goal: A new index module in the tags repo that keeps a tag index of note ids and writes it atomically as a versioned JSON file for callers"; d = 1; next } { print }' "$plan" > "$lp"
sh "$bin/plan-lint.sh" "$lp" >/dev/null 2>"$tmp/lgerr"
[ $? -eq 1 ]; check 'plan-lint refuses a goal that cannot be the MR title' $?
grep -q 'MR title' "$tmp/lgerr"; check 'the refusal says it is the MR title' $?

# --- T-253: the steps of a proposal become the block's `## Checklist` --------------------------------
section() { # <file> <heading>: the non-blank lines under the heading, up to the next `## `
  awk -v h="$2" '$0 == h { on = 1; next } on && /^## / { exit } on && NF { print }' "$1"
}
lineof() { # <file> <exact line>: the number of its first occurrence, empty when absent
  grep -nxF -- "$2" "$1" | head -n1 | cut -d: -f1
}

[ "$(section "$f2" '## Checklist')" = "$(printf '%s\n%s' '- [ ] a' '- [ ] b')" ]
check 'the sub-bullet steps a, b become - [ ] a and - [ ] b under ## Checklist' $?
oos=$(lineof "$f2" '## Out of scope'); cl=$(lineof "$f2" '## Checklist')
int=$(lineof "$f2" '## Internal'); att=$(lineof "$f2" '## Attempts')
[ -n "$cl" ] && [ "$oos" -lt "$cl" ] && [ "$cl" -lt "$int" ] && [ "$cl" -lt "$att" ]
check '## Checklist sits after ## Out of scope and before ## Internal and ## Attempts' $?
[ "$(grep -cxF -- '- [ ] a' "$f2")" = 1 ]; check 'a step is written once' $?
grep -qxF '## Checklist' "$f3"; [ $? -ne 0 ]; check 'steps: none yields no ## Checklist' $?
grep -qxF '## Checklist' "$f1"; [ $? -ne 0 ]; check 'a research proposal without steps: yields no ## Checklist' $?

# a step is copied whole: a `*` bullet, a colon that could read as a proposal key, a `;` inside a command
tricky='docs: regenerate the table, then run `sh bin/x.sh; echo ok`'
tp="$state/repos/demo/plans/tricky-plan-ready.md"
awk -v t="$tricky" '$0 == "  - b" { print "  * " t; next } { print }' "$plan" > "$tp"
tout="$tmp/tricky"
sh "$bin/decompose.sh" "$tp" --out "$tout" --state "$state" >/dev/null 2>"$tmp/terr"
check 'tricky steps: decompose exits 0' $?
tf2="$tout/02-write-the-exporter-core.md"
if [ -f "$tf2" ]; then
  [ "$(section "$tf2" '## Checklist')" = "$(printf '%s\n%s' '- [ ] a' "- [ ] $tricky")" ]
  check 'a * step with a colon and a ; is one checklist line, verbatim' $?
  [ "$(section "$tf2" '## Docs')" = 'docs/export.md' ]
  check 'a step reading like a key does not overwrite the proposal docs:' $?
else
  cat "$tmp/terr"; printf 'FAIL tricky steps: no block 2 written\n'; fail=1
fi

# --- T-253: plan-lint and the `steps:` rule --------------------------------------------------------
sh "$bin/plan-lint.sh" "$plan" >/dev/null 2>"$tmp/lerr"; rc=$?
check 'plan-lint accepts the plan, a research proposal without steps: included' $rc
[ "$rc" -eq 0 ] || cat "$tmp/lerr"

refused() { # <label> <proposal number> <awk program turning the good plan into the bad one>
  rp="$state/repos/demo/plans/steps-$1-plan-ready.md"
  awk "$3" "$plan" > "$rp"
  sh "$bin/plan-lint.sh" "$rp" >/dev/null 2>"$tmp/rerr"
  [ $? -eq 1 ]; check "plan-lint refuses $1" $?
  grep -q 'steps' "$tmp/rerr" && grep -q "proposal $2" "$tmp/rerr"
  check "$1: the refusal names steps and proposal $2" $?
}
refused 'a feature proposal with no steps' 2 '/^- steps:$/ || /^  - [ab]$/ { next } { print }'
refused 'an empty - steps: with no sub-bullet' 2 '/^  - [ab]$/ { next } { print }'
refused 'inline step text' 2 '/^- steps:$/ { print "- steps: wire the exporter into the cli"; next } /^  - [ab]$/ { next } { print }'
refused 'none followed by sub-bullets' 2 '/^- steps:$/ { print "- steps: none"; next } { print }'
refused 'a bugfix proposal with no steps' 3 '/^- steps: none$/ { next } { print }'
refused 'a refactor proposal with no steps' 3 '/^- archetype: bugfix$/ { print "- archetype: refactor"; next } /^- steps: none$/ { next } { print }'
refused 'inline step text on a research proposal' 1 '{ print } /^- design: none$/ { print "- steps: read the docs" }'

# --- T-253: block-brief.sh carries the checklist, outside the design ------------------------------
brieftask() { # <id> <with checklist: 1 or 0>
  {
    printf -- '---\nid: %s\nrepo: demo\nbranch: null\nstatus: ready\ntier: yellow\narchetype: feature\n' "$1"
    printf 'complexity: medium\ndepends_on: []\n---\n\n# Goal\nfeat(export): %s\n\n## Context\nctx\n\n' "$1"
    printf 'Design (approved in the grill):\n### `src/export/exporter.py` (new)\ndef export_rows(rows, fh)\n'
    printf '  Writes every row of the stream into the open handle.\n\n'
    printf '## Acceptance\n`pytest tests/test_exporter.py`\n\n## Docs\nnone\n\n## Out of scope\nthe header line\n'
    if [ "$2" = 1 ]; then printf '\n## Checklist\n- [ ] a\n- [ ] b\n'; fi
    printf '\n## Attempts\n'
  } > "$state/repos/demo/tasks/$1.md"
}
brieftask T-006-01 1
brieftask T-006-02 0
for ph in tests implement; do
  bf="$tmp/brief-$ph.md"
  sh "$bin/block-brief.sh" T-006-01 --state "$state" --phase "$ph" > "$bf" 2>/dev/null
  check "$ph: block-brief.sh exits 0" $?
  [ "$(section "$bf" '## Checklist')" = "$(printf '%s\n%s' '- [ ] a' '- [ ] b')" ]
  check "$ph: the brief prints the task's ## Checklist verbatim" $?
  [ "$(grep -cxF -- '- [ ] a' "$bf")" = 1 ]; check "$ph: the brief prints the checklist once" $?
  dl=$(lineof "$bf" '  Writes every row of the stream into the open handle.')
  cl=$(lineof "$bf" '## Checklist'); al=$(lineof "$bf" '## Acceptance')
  [ -n "$dl" ] && [ -n "$cl" ] && [ -n "$al" ] && [ "$dl" -lt "$cl" ] && [ "$cl" -lt "$al" ]
  check "$ph: the checklist sits after the design and before ## Acceptance" $?
  grep -qxF 'the header line' "$bf"; [ $? -ne 0 ]; check "$ph: the out of scope stays out of the brief" $?
done
sh "$bin/block-brief.sh" T-006-02 --state "$state" --phase tests > "$tmp/brief-none.md" 2>/dev/null
check 'a task with no checklist still briefs with exit 0' $?
grep -qxF '## Checklist' "$tmp/brief-none.md"; [ $? -ne 0 ]; check 'a task with no checklist briefs none' $?

exit $fail
