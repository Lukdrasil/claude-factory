#!/bin/sh
# One block proved green or red (T-128-03): runs the test files the block's own diff changed and the repo's
# `crap` binding when the toolset declares one, then prints a four-line report the coordinator pastes without
# reading any run output. The runs' own stdout and stderr never reach this script's stdout.
#
#   block-verify.sh <block-id> [--worktree <dir>] [--state <dir>] [--base <ref>]
#
# The state clone is --state, else $WORK_DIR/state, else resolve_state_dir of the cwd. The block's task file is
# found by its `id:` line, and the repo key is the directory under <state>/repos/ that holds it. The worktree is
# --worktree, else $WORK_DIR/<key>/<block-id>. The base is --base, else `git merge-base <parent branch> HEAD`
# in the worktree, the parent branch being the `branch:` of the parent task and the parent id the block id
# without its last segment. It is the merge base and not the branch itself because that ref moves as sibling
# blocks merge into it, which would pull their test files into this block's run set; the bare ref is used only
# when the worktree knows no merge base for it.
#
# The run set is `git diff --name-only <base>` filtered by the `test-globs` frontmatter of
# <state>/repos/<key>/toolset.md, read with the same awk snippet and the same `**` to `*` rewrite
# policy-guard.sh uses, and matched with the same repo-relative plus leading-slash `case` pair. A changed
# `*.test.sh` runs as `timeout 10m sh <file>`; a changed `*Tests.cs` runs through the toolset's `test-filter`
# binding with <expr> substituted by the file's base name; that binding carries the `timeout` policy-guard.sh
# demands of every `dotnet test` (toolsets/dotnet.md); with no `test-filter` binding it is not run. A changed
# `*.test.js` or `*.spec.js` of a toolset whose `stack:` is node runs as `timeout 10m node --test <file>`. Any
# other changed test file runs through the `test-filter` binding when that binding takes `<file>`, with the
# repo-relative path substituted, else through the plain `test` binding, which runs the whole suite and so runs
# once per verify however many files fell back to it; a toolset with neither leaves the file not counted and
# not run. `timeout` is spelled as a bare word so PATH resolves it. A file the block deleted is not run either:
# only a test file present on disk can be run. An empty diff is the same as a diff with no test file in it,
# which is red.
#
# The one exception is a **documentation block**: a non-empty diff whose every path ends in `.md`. No document
# is asserted by a test in any repo this runs against, so such a block can never change a test file, and the
# zero-tests rule would redden every documentation cut by construction. A markdown-only diff is therefore green
# on zero tests, reported as `tests: 0 run, 0 passed, 0 failed (markdown-only diff)`. One non-markdown path in
# the diff takes the exception away: a block that touches code is judged as any other block, and an empty diff
# stays red, because a block that changed nothing has proved nothing.
#
# That diff form is the plain one, not `<base>...HEAD`, on purpose: it compares the *working tree* against
# <base>, so an uncommitted merge staged by `block-merge.sh --verify` can be verified before it is committed,
# which is what lets the merge queue commit only on green. The trade is that a worktree carrying uncommitted
# unrelated edits contributes them to the run set, where the three-dot form would have ignored them; on the
# clean worktree of the normal per-block use the two forms are identical.
#
# Prints on stdout exactly:
#
#     block: T-NNN-NN
#     tests: <n> run, <n> passed, <n> failed
#     crap:  <value> | over <threshold>: <method> <value>, ... | not bound (repos/<key>/toolset.md)
#     verdict: green | red
#
# The same four lines go to `<root>/<key>/.harness/<block-id>/verify.txt` when the worktree sits under
# $WORK_DIR, which is where block-mr.sh reads the verification that ran.
# Two spaces after `crap:` line the value up with the one on the `tests:` line. The verdict is green only when
# at least one test ran (or the diff is markdown-only, above), none failed and no method of the `crap` run is
# over the threshold, so zero tests on a diff that carries code is red and so is one method over the threshold
# (T-163). The threshold is `crap-threshold:` in the toolset
# frontmatter, 8 when it declares none; a toolset with no `crap` binding keeps the line as a note and cannot
# redden anything. The `coverage` binding, when there is one, runs first as a script of its own under its own
# timeout; then the `crap` binding runs as a script under `timeout 10m` with the block's changed source files as
# its arguments and `<scope>` replaced by "$@" (the stack's source extensions when `stack:` names one, else
# every changed file that is no test, document or config file). No source file changed means no crap run and
# the line `no source file changed`, green. A run that prints nothing, or exits non-zero with no method row
# over the threshold, is red with its exit and the last line of its stderr. A method row of the run is a line whose first field carries a member separator (`.`, `:` or
# `#`) and whose last field is a number, so a summary line is not read as a method. Exit 0 on green, 1 on red
# with the first failing command, at most the last 30 lines of that run's output and every over-threshold
# method on stderr, never the whole log.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'block-verify: %s\n' "$1" >&2; exit 1; }

id='' worktree='' state='' base=''
while [ $# -gt 0 ]; do
  case "$1" in
    --worktree) [ $# -ge 2 ] || die "--worktree needs a value"; worktree=$2; shift 2 ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    --base) [ $# -ge 2 ] || die "--base needs a value"; base=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$id" ] || die "one block id at a time"; id=$1; shift ;;
  esac
done
[ -n "$id" ] || die "usage: block-verify.sh <block-id> [--worktree <dir>] [--state <dir>] [--base <ref>]"

if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    state=$(resolve_state_dir "$(pwd)")
  fi
fi

task=$(task_of "$id" || :)
[ -n "$task" ] || die "no task file for block id '$id' under $state/repos/*/tasks/"
key=${task#"$state"/repos/}; key=${key%%/*}

# see: bin/block-merge.sh, the same reader for the first `branch:` of a task's frontmatter
branch_of() { # <task file>
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit }
    /^branch:[[:space:]]*/ { sub(/^branch:[[:space:]]*/, ""); sub(/[[:space:]]+#.*$/, ""); sub(/[[:space:]]+$/, ""); print; exit }' "$1" \
    | sed 's/^["'\'']//; s/["'\'']$//'
}

# see: toolsets/dotnet.md, the command table whose binding cell is wrapped in backticks; the reader is
# see: toolset_binding of lib-tasks.sh, shared with solve-next.sh --auto
binding_of() { toolset_binding "$@"; }

if [ -z "$worktree" ]; then
  [ -n "${WORK_DIR:-}" ] || die "no --worktree and no \$WORK_DIR to resolve the default worktree of '$id'"
  worktree="$WORK_DIR/$key/$id"
fi
[ -d "$worktree" ] || die "the worktree of block '$id' is not a directory: $worktree"

if [ -z "$base" ]; then
  parent=${id%-*}
  ptask=$(task_of "$parent" || :)
  [ -n "$ptask" ] || die "no --base and no parent task '$parent' to take the base branch from"
  pbranch=$(branch_of "$ptask")
  [ -n "$pbranch" ] || die "the parent task '$parent' declares no branch: to use as the base"
  # why: the parent branch ref moves as sibling blocks merge into it, and diffing against the moved ref pulls
  # why: their test files into this block's run set and reddens a block that never touched them; the merge base
  # why: is the commit this worktree was cut from and does not move.
  # warn: a parent branch the worktree does not know yet has no merge base, so the bare ref stays the fallback.
  base=$(git -C "$worktree" merge-base "$pbranch" HEAD 2>/dev/null || :)
  [ -n "$base" ] || base=$pbranch
fi

toolset="$state/repos/$key/toolset.md"
globs=''
if [ -f "$toolset" ]; then
  globs=$(awk '/^test-globs:[[:space:]]*$/ { g=1; next }
       g && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/"/, ""); print; next }
       g { exit }' "$toolset")
fi
[ -n "$globs" ] || globs='**/tests/**
**/*Tests.*'
pats=$(printf '%s' "$globs" | sed 's|\*\*|*|g')

# warn: unquoted $pats in a `for` list is field split *and* pathname expanded, so without `set -f` the globs
# warn: are replaced by the files of the cwd and every path stops matching
is_test_path() { # <repo-relative path>
  set -f
  for pat in $pats; do
    case "$1" in $pat) set +f; return 0 ;; esac
    case "/$1" in $pat) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git -C "$worktree" diff --name-only "$base" > "$tmp/changed" 2>"$tmp/giterr" \
  || die "git diff $base failed in $worktree: $(cat "$tmp/giterr")"

# see: the documentation-block exception of this script's header. `grep -qv` answers "some line is not a .md
# see: path", so an empty diff leaves docs_only at 0 and stays red, and one code path in the diff clears it.
docs_only=0
if [ -s "$tmp/changed" ] && ! grep -qv '\.md$' "$tmp/changed"; then docs_only=1; fi

filter_binding=$(binding_of "$toolset" test-filter)
test_binding=$(binding_of "$toolset" test)
stack=''
if [ -f "$toolset" ]; then
  stack=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit }
    /^stack:[[:space:]]*/ { sub(/^stack:[[:space:]]*/, ""); sub(/[[:space:]].*$/, ""); print; exit }' "$toolset")
fi
run=0; passed=0; failed=0; first_failure=''
: > "$tmp/first-out"

run_one() { # <command>: runs it in the worktree and counts it
  set +e
  ( cd "$worktree" && eval "$1" ) >"$tmp/out" 2>&1
  status=$?
  set -e
  run=$((run + 1))
  if [ "$status" -eq 0 ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    if [ -z "$first_failure" ]; then
      first_failure=$1
      tail -n 30 "$tmp/out" > "$tmp/first-out"
    fi
  fi
}

# the plain `test` binding runs the whole suite, so the files that fall back to it share one run after the loop
whole_suite=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  is_test_path "$f" || continue
  [ -f "$worktree/$f" ] || continue
  cmd=''
  case "$f" in
    *.test.sh) cmd="timeout 10m sh $f" ;;
    *Tests.cs)
      [ -n "$filter_binding" ] || continue
      expr=${f##*/}; expr=${expr%.cs}
      cmd=$(printf '%s' "$filter_binding" | sed "s|<expr>|$expr|g")
      ;;
  esac
  if [ -z "$cmd" ]; then
    case "$stack:$f" in
      node:*.test.js|node:*.spec.js) cmd="timeout 10m node --test $f" ;;
    esac
  fi
  if [ -z "$cmd" ]; then
    case "$filter_binding" in
      *'<file>'*) cmd=$(printf '%s' "$filter_binding" | sed "s|<file>|$f|g") ;;
      *) [ -z "$test_binding" ] || whole_suite=1; continue ;;
    esac
  fi
  run_one "$cmd"
done < "$tmp/changed"
[ "$whole_suite" -eq 0 ] || run_one "$test_binding"

crap_binding=$(binding_of "$toolset" crap)
crap_over=''
threshold=8
if [ -n "$crap_binding" ]; then
  t=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit }
    /^crap-threshold:[[:space:]]*/ { sub(/^crap-threshold:[[:space:]]*/, ""); sub(/[[:space:]].*$/, ""); print; exit }' \
    "$toolset")
  case "$t" in ''|*[!0-9.]*) ;; *) threshold=$t ;; esac
  # why: `timeout 10m DOTNET_ROLL_FORWARD=Major dotnet-crap ...` never ran: timeout takes a command, not an
  # why: assignment, exited 127 into /dev/null and the empty run read green. The binding runs as a script of
  # why: its own under timeout, so an assignment, a pipe or a && in the cell all run as the toolset wrote them.
  # why: `<scope>` is the block's own changed source files (crap-loop.md: the task's diff, never the repo), and
  # why: `coverage` runs first when the toolset binds it, since crap reads what coverage wrote
  # the scope is the block's changed source files: the stack's own source extensions when the toolset names
  # a stack, else every changed file that is neither a test, a document nor a build or config file. The
  # paths are handed to the script as its arguments and `<scope>` becomes "$@", so a path with a space, a
  # quote or a dollar is one argument and never shell
  : > "$tmp/scope"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$worktree/$f" ] || continue
    is_test_path "$f" && continue
    case "$stack" in
      dotnet) case "$f" in *.cs) ;; *) continue ;; esac ;;
      node) case "$f" in *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs) ;; *) continue ;; esac ;;
      python) case "$f" in *.py) ;; *) continue ;; esac ;;
      *) case "$f" in *.md|*.json|*.yml|*.yaml|*.toml|*.xml|*.txt|*.lock|*.csproj|*.sln|*.props|*.targets|*.config|*.editorconfig|*.gitignore|*.gitattributes) continue ;; esac ;;
    esac
    printf '%s\n' "$f" >> "$tmp/scope"
  done < "$tmp/changed"
  coverage_binding=$(binding_of "$toolset" coverage)
  crap_status=0
  if [ ! -s "$tmp/scope" ]; then
    # why: a block that changed no source file has no method to score, and a tool given no path scores the
    # why: whole repo, which is out of scope (ADR-0014) and would redden a test-only block on old code
    crap='no source file changed'
    : > "$tmp/crap"
  else
    # why: `timeout 10m DOTNET_ROLL_FORWARD=Major dotnet-crap ...` never ran: timeout takes a command, not an
    # why: assignment, exited 127 into /dev/null and the empty run read green. The binding runs as a script of
    # why: its own, so an assignment, a pipe or a && in the cell all run as the toolset wrote them. Coverage
    # why: runs first, on its own and under its own timeout (the dotnet row carries 15m), since crap reads
    # why: what coverage wrote; the 10m of the crap run is the crap run alone
    if [ -n "$coverage_binding" ]; then
      printf '%s\n' "$coverage_binding" > "$tmp/coverage.sh"
      set +e
      ( cd "$worktree" && sh "$tmp/coverage.sh" ) >"$tmp/coverage.out" 2>"$tmp/crap.err"
      cov_status=$?
      set -e
      [ "$cov_status" -eq 0 ] || crap_status=97
    fi
    if [ "$crap_status" -eq 0 ]; then
      printf '%s\n' "$(printf '%s' "$crap_binding" | sed 's|<scope>|"$@"|g')" > "$tmp/crap.sh"
      set +e
      ( cd "$worktree" && xargs_scope=$(cat "$tmp/scope") && set -f && IFS='
' && set -- $xargs_scope && unset IFS && timeout 10m sh "$tmp/crap.sh" "$@" ) >"$tmp/crap" 2>"$tmp/crap.err"
      crap_status=$?
      set -e
    else
      : > "$tmp/crap"
    fi
    crap=$(head -n1 "$tmp/crap")
  fi
  # why: a run that printed nothing, or that failed, proved nothing: it is red with its reason, never a green
  # why: gate; a tool that exits non-zero on a method over its threshold is red by that exit too, with the
  # why: rows it printed when they parse
  if [ -s "$tmp/scope" ] && { [ -z "$crap" ] || [ "$crap_status" -ne 0 ]; }; then
    case "$crap_status" in
      97) crap="coverage failed: $(tail -n1 "$tmp/crap.err" 2>/dev/null)" ;;
      0) crap="no value: $(tail -n1 "$tmp/crap.err" 2>/dev/null)" ;;
      *) crap="exit $crap_status: $(tail -n1 "$tmp/crap.err" 2>/dev/null)" ;;
    esac
    crap_over="(the crap run) $crap"
  fi
  # see: a method row is `<Type>.<Member> ... <value>`, pipes and all, so a summary line that happens to end
  # see: in a number ("Analyzed 123 files") is not one: the name has to carry a member separator
  rows_over=$(awk -v t="$threshold" '
    { gsub(/\|/, " ") }
    NF < 2 { next }
    $NF !~ /^[0-9]+([.][0-9]+)?$/ { next }
    $1 !~ /^[A-Za-z_][A-Za-z0-9_]*[.:#]/ { next }
    $NF + 0 > t + 0 { print $1, $NF }' "$tmp/crap")
  if [ -n "$rows_over" ]; then
    # a non-zero exit with rows over the threshold is those rows, the exit being the tool's own threshold
    crap_over=$rows_over
    crap_status=0
  fi
  if [ -n "$crap_over" ] && [ "$crap_status" -eq 0 ] && [ -n "$(head -n1 "$tmp/crap")" ]; then
    joined='' over=0
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      over=$((over + 1))
      [ "$over" -le 5 ] || continue
      if [ -z "$joined" ]; then joined=$row; else joined="$joined, $row"; fi
    done <<CRAP_ROWS
$crap_over
CRAP_ROWS
    [ "$over" -le 5 ] || joined="$joined, and $((over - 5)) more"
    crap="over $threshold: $joined"
  fi
else
  crap="not bound (repos/$key/toolset.md)"
fi

if { [ "$run" -gt 0 ] || [ "$docs_only" -eq 1 ]; } && [ "$failed" -eq 0 ] && [ -z "$crap_over" ]; then
  verdict=green
else
  verdict=red
fi

# warn: `set -e` is on, so this stays an `if`: a failing `[ ... ] && [ ... ] && note=...` chain is a failing
# warn: statement and would exit the script instead of leaving the note empty
note=''
if [ "$docs_only" -eq 1 ] && [ "$run" -eq 0 ]; then note=' (markdown-only diff)'; fi

{
  printf 'block: %s\n' "$id"
  printf 'tests: %s run, %s passed, %s failed%s\n' "$run" "$passed" "$failed" "$note"
  printf 'crap:  %s\n' "$crap"
  printf 'verdict: %s\n' "$verdict"
} > "$tmp/report"
cat "$tmp/report"
# see: 3.4 of the agent-org plan, block-mr.sh puts the last report into the block MR as the verification that
# see: ran, from `<root>/<key>/.harness/<block>/verify.txt` beside review.md and arch.md; a worktree outside
# see: $WORK_DIR has no such folder and keeps the report on stdout only
if resolve_layout "$worktree/verify.txt" "${WORK_DIR:-}"; then
  mkdir -p "${LO_STAMP%/*}/$id" && cp "$tmp/report" "${LO_STAMP%/*}/$id/verify.txt" \
    || printf 'block-verify: the report could not be written to %s\n' "${LO_STAMP%/*}/$id/verify.txt" >&2
fi

if [ "$verdict" = green ]; then
  exit 0
fi
if [ -n "$first_failure" ]; then
  printf 'block-verify: first failing command: %s\n' "$first_failure" >&2
  # why: without the tail the only way to see why a block is red is to open the run's log, which is exactly the
  # why: raw artifact the coordinator must not read; 30 lines carry the failure and cost nothing
  if [ -s "$tmp/first-out" ]; then
    printf 'block-verify: last 30 lines of that run:\n' >&2
    cat "$tmp/first-out" >&2
  else
    printf 'block-verify: the failing run printed nothing\n' >&2
  fi
elif [ "$run" -eq 0 ]; then
  printf 'block-verify: no test file in the diff of block %s against %s\n' "$id" "$base" >&2
fi
if [ -n "$crap_over" ]; then
  printf 'block-verify: crap over the threshold %s, one method per line:\n' "$threshold" >&2
  printf '%s\n' "$crap_over" >&2
  printf 'block-verify: the fix loop is skills/_shared/crap-loop.md\n' >&2
fi
exit 1
