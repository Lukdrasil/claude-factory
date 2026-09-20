#!/bin/sh
# decompose.sh over a throwaway state clone: three proposals become three block files, the frontmatter is the
# proposal's own values, each design section carries exactly the members the proposal names, the manifest
# repeats the plan's ordinals, the source task's forge issue is copied over, and a plan with an open gap
# ledger row is refused without writing anything.
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

## Decisions
- csv, not xlsx: the consumer is a shell pipeline, the human chose it
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
- out of scope: the cli

## Out of scope
No xlsx, and no streaming over the network.

## Gap ledger
| # | type | question | state | answer |
|---|---|---|---|---|
| 1 | decision | csv or xlsx | closed | csv |
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
has 'the runtime is the default'     "$f2" 'runtime: default'
has 'depends_on is left empty'       "$f3" 'depends_on: []'
has 'plan_hash is null'              "$f2" 'plan_hash: null'
has 'the goal is the proposal goal'  "$f2" 'feat(export): write the rows of a stream into an open handle'
has 'the plan is named in context'   "$f2" 'From the plan `repos/demo/plans/x-plan-ready.md`'
has 'the decisions are carried over' "$f2" '- csv, not xlsx: the consumer is a shell pipeline, the human chose it'
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
sed 's/^| 1 | decision | csv or xlsx | closed | csv |/| 1 | decision | csv or xlsx | open | |/' "$plan" > "$bad"
badout="$tmp/badout"
if sh "$bin/decompose.sh" "$bad" --out "$badout" --state "$state" >/dev/null 2>"$tmp/err2"; then
  printf 'FAIL an open gap ledger row is refused\n'; fail=1
else
  printf 'PASS an open gap ledger row is refused\n'
fi
grep -q 'gap ledger' "$tmp/err2"; check 'the plan-lint reason reaches stderr' $?
[ ! -d "$badout" ] || [ -z "$(ls -A "$badout")" ]; check 'the refusal writes nothing' $?

exit $fail
