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
# demands of every `dotnet test` (toolsets/dotnet.md). `timeout` is
# spelled as a bare word so PATH resolves it. A changed file that matches a glob but is neither shape is not
# counted and not run, and so is a file the block deleted: only a test file present on disk can be run. An
# empty diff is the same as a diff with no test file in it, which is red.
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
# redden anything. A method row of the run is a line whose first field carries a member separator (`.`, `:` or
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

# see: toolsets/dotnet.md, the command table whose binding cell is wrapped in backticks
binding_of() { # <toolset file> <command name>
  [ -f "$1" ] || return 0
  awk -F '|' -v want="$2" '
    NF >= 3 {
      name = $2; bind = $3
      gsub(/`/, "", name); gsub(/`/, "", bind)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name); gsub(/^[[:space:]]+|[[:space:]]+$/, "", bind)
      sub(/[[:space:]].*$/, "", name)
      if (name == want && bind != "" && bind != "binding") { print bind; exit }
    }' "$1"
}

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
run=0; passed=0; failed=0; first_failure=''
: > "$tmp/first-out"

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
    *) continue ;;
  esac
  set +e
  ( cd "$worktree" && eval "$cmd" ) >"$tmp/out" 2>&1
  status=$?
  set -e
  run=$((run + 1))
  if [ "$status" -eq 0 ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    if [ -z "$first_failure" ]; then
      first_failure=$cmd
      tail -n 30 "$tmp/out" > "$tmp/first-out"
    fi
  fi
done < "$tmp/changed"

crap_binding=$(binding_of "$toolset" crap)
crap_over=''
threshold=8
if [ -n "$crap_binding" ]; then
  t=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit }
    /^crap-threshold:[[:space:]]*/ { sub(/^crap-threshold:[[:space:]]*/, ""); sub(/[[:space:]].*$/, ""); print; exit }' \
    "$toolset")
  case "$t" in ''|*[!0-9.]*) ;; *) threshold=$t ;; esac
  set +e
  ( cd "$worktree" && eval "timeout 10m $crap_binding" ) >"$tmp/crap" 2>/dev/null
  set -e
  crap=$(head -n1 "$tmp/crap")
  [ -n "$crap" ] || crap='(no value)'
  # see: a method row is `<Type>.<Member> ... <value>`, pipes and all, so a summary line that happens to end
  # see: in a number ("Analyzed 123 files") is not one: the name has to carry a member separator
  crap_over=$(awk -v t="$threshold" '
    { gsub(/\|/, " ") }
    NF < 2 { next }
    $NF !~ /^[0-9]+([.][0-9]+)?$/ { next }
    $1 !~ /^[A-Za-z_][A-Za-z0-9_]*[.:#]/ { next }
    $NF + 0 > t + 0 { print $1, $NF }' "$tmp/crap")
  if [ -n "$crap_over" ]; then
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
