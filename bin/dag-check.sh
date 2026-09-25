#!/bin/sh
# The mechanical safety check of a `factory solve` cut (T-128), run by the coordinator after the blocks are
# written and before any block is spawned.
#
#   dag-check.sh <parent-id> [--state <dir>]
#                                          cwd = the state clone unless --state is given
#
# It reads every block T-NNN-NN of the parent out of the state clone and works out, per block, the files it
# claims: the `### `path`` headings of its `Design (approved in the grill):` section plus the backticked paths
# listed under its `## Docs`. Ownership is over files, not members, and it comes from the body of the task
# file, not from the frontmatter.
#
# A design heading always names a file, at the repo root or below it. A backticked Docs token counts as a
# claimed path only when it contains a `/` or ends in a file extension (`README.md`), while a Docs sentence
# naming a symbol, a flag or a call in backticks is ordinary prose: `#!`, `--state`, `depends_on` and
# `remove(file, id)` are not files and are ignored.
#
# Block 00, when a cut has one, is the additive skeleton: it declares surface that other blocks implement, so
# its paths take no part in the overlap computation and it is planned alone in the first wave. A block 00 that
# claims nothing is accepted, because it is the one block whose job may be pure declaration.
#
# A block is integration-only when its `## Acceptance` names a bound port (`bound port` or `binding a port`,
# the two spellings solve.md itself uses), a shared database or a fixed path. Those phrases are the flow's
# fixed vocabulary and nothing wider is matched: solve.md tells a block author that anything binding one
# of them is out of a block's own test run and belongs to the step 12 integration run, so a block whose
# contract rests on one cannot be proven alone and the cut has to fold it into a block that can. Only the
# `## Acceptance` section counts, because a `## Context` may discuss a port or a database freely, and a bullet
# that names `dag-check.sh`, or `integration run` after `belongs to` or `step 12`, is quoting the rule rather than
# resting its contract on the resource.
#
# stdout carries the wave plan, one wave per line, at most five blocks per wave, every block exactly once.
# stderr carries every refusal reason.
#
# Exit 0: the plan.
# Exit 1: no parent id, no task file for the id, the task has no blocks, a block claims no path at all, a
#         block's `## Acceptance` is integration-only, or two blocks with no depends_on edge between them claim
#         the same path.
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'dag-check: %s\n' "$1" >&2; exit 1; }

parent='' state=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$parent" ] || die "one parent id at a time"; parent=$1; shift ;;
  esac
done
[ -n "$parent" ] || die "usage: dag-check.sh <parent-id> [--state <dir>]"

# why: the cut is checked against the clone the coordinator is standing in, so the cwd fallback of
# why: resolve_state_dir is the answer here and $WORK_DIR must not override it.
if [ -z "$state" ]; then
  cwd=$(pwd)
  state=$(resolve_state_dir "$cwd")
  case "$state" in /*|[A-Za-z]:/*) ;; *) state="$cwd/$state" ;; esac
fi
[ -d "$state/repos" ] || die "$state is not a state clone"

ptask=$(task_of "$parent" || :)
[ -n "$ptask" ] || die "no task file for '$parent' in $state"
pkey=${ptask#"$state/repos/"}
pkey=${pkey%%/*}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/paths" "$tmp/deps" "$tmp/integration"

# invariant: a claim comes out of the body: every design heading of the file plus every backticked token of
# invariant: the `## Docs` section, which ends at the next `## ` heading. A Docs section reading `none` has no
# invariant: backticks and so claims nothing.
# invariant: a Docs token is a claim only when it carries a `/` or a file extension; else it is prose.
claimed_paths() { # <task file>
  awk '
    function claim(p) { if (p != "" && (index(p, "/") > 0 || p ~ /^[^[:space:]()]*\.[A-Za-z][A-Za-z0-9]*$/)) print p }
    /^## / { docs = ($0 ~ /^## Docs([[:space:]]*)$/) }
    /^### `/ { p = $0; sub(/^### `/, "", p); sub(/`.*$/, "", p); if (p != "") print p; next }
    docs {
      line = $0
      while (match(line, /`[^`]+`/)) {
        claim(substr(line, RSTART + 1, RLENGTH - 2))
        line = substr(line, RSTART + RLENGTH)
      }
    }' "$1" | sort -u
}

# invariant: the section ends at the next `## ` heading, so a phrase further down the task body is prose.
# invariant: a bullet is judged whole, its continuation lines folded in, because the phrase and the words that
# invariant: qualify it are routinely wrapped onto separate lines.
# why: a bullet naming `dag-check.sh`, or naming `integration run` after `belongs to` or `step 12`, is quoting
# why: the flow's own rule or this very check's vocabulary, not resting its contract on the resource.
# warn: `integration run` alone is not exempt, or any block could silence the check by saying the phrase.
acceptance_phrase() { # <task file>: the first of the vocabulary phrases named under ## Acceptance, or nothing
  awk '
    function judge(b,   line) {
      if (b == "" || hit != "") return
      line = tolower(b)
      if (match(line, /(belongs to|step 12)[^.]*integration run/) || index(line, "dag-check.sh") > 0) return
      if (match(line, /bound port|binding a port|shared database|fixed path/)) hit = substr(line, RSTART, RLENGTH)
    }
    /^## / { judge(buf); buf = ""; acc = ($0 ~ /^## Acceptance([[:space:]]*)$/); next }
    !acc { next }
    /^[-*][[:space:]]/ { judge(buf); buf = $0; next }
    { buf = buf " " $0 }
    END { judge(buf); if (hit != "") print hit }' "$1"
}

deps_of() { # <task file>
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit }
    /^depends_on:[[:space:]]*/ {
      d = $0; sub(/^depends_on:[[:space:]]*/, "", d)
      gsub(/[][,"'"'"']/, " ", d)
      n = split(d, a, /[[:space:]]+/)
      for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
      exit
    }' "$1"
}

# invariant: blocks are selected by their `id:` line and an id-shape check, never by an `<id>-*.md` glob: the
# invariant: parent file T-200-parent.md sits in the same directory and a glob would pick it up too.
# invariant: the blocks sit under the parent's repo key, live or archived (task_files --all, the way task_of
# invariant: finds the parent): an archived parent moved with all its blocks, so its cut stays whole.
# why: a depends_on outside the parent's blocks, live or archived, is no edge of the wave plan: it orders
# why: parents, the queue (queue-next.sh) waits for it, and an archived id is done.
while IFS= read -r f; do
  [ -f "$f" ] || continue
  bid=$(sed -n 's/^id:[[:space:]]*//p' "$f" | sed 's/[[:space:]]*#.*//' | head -n 1)
  is_block_of "$parent" "$bid" || continue
  printf '%s\n' "$bid" >> "$tmp/blocks"
  claimed_paths "$f" > "$tmp/paths/$bid"
  deps_of "$f" > "$tmp/deps/$bid"
  acceptance_phrase "$f" > "$tmp/integration/$bid"
done <<EOF
$(task_files --all "$pkey")
EOF
[ -f "$tmp/blocks" ] || die "'$parent' has no T-NNN-NN blocks, so it is not a parent task"
sort -u "$tmp/blocks" | sort_ids > "$tmp/blocks.sorted" && mv -f "$tmp/blocks.sorted" "$tmp/blocks"

skeleton="$parent-00"

# why: a block that claims no file has no contract it can prove alone; block 00 is exempt, it only declares
while read -r b; do
  [ "$b" != "$skeleton" ] || continue
  [ -s "$tmp/paths/$b" ] || die "block $b claims no path at all, so nothing it does can be verified alone"
done < "$tmp/blocks"

# why: a contract only an integration test can prove is out of the block's own test run, so the block cannot
# why: be verified alone and the cut has to fold it into one that can
while read -r b; do
  phrase=$(cat "$tmp/integration/$b")
  [ -n "$phrase" ] || continue
  die "block $b has an integration-only ## Acceptance: it names '$phrase', which belongs to the step 12 integration run"
done < "$tmp/blocks"

has_edge() { # <a> <b>: a depends_on b, or b depends_on a
  grep -qx -- "$2" "$tmp/deps/$1" || grep -qx -- "$1" "$tmp/deps/$2"
}

# why: block 00's declarations are excluded from the overlap: ownership is over the implementers of a file
: > "$tmp/claims"
while read -r b; do
  [ "$b" != "$skeleton" ] || continue
  while read -r p; do printf '%s %s\n' "$p" "$b" >> "$tmp/claims"; done < "$tmp/paths/$b"
done < "$tmp/blocks"

conflict=0
cut -d' ' -f1 "$tmp/claims" | sort | uniq -d > "$tmp/dup"
while read -r p; do
  [ -n "$p" ] || continue
  owners=$(awk -v want="$p" '$1 == want { print $2 }' "$tmp/claims" | sort -u)
  for a in $owners; do
    for b in $owners; do
      [ "$a" \< "$b" ] || continue
      if ! has_edge "$a" "$b"; then
        printf 'dag-check: %s is claimed by both %s and %s, which have no depends_on edge between them\n' \
          "$p" "$a" "$b" >&2
        conflict=1
      fi
    done
  done
done < "$tmp/dup"
[ "$conflict" = 0 ] || die "the cut is not safe to run in parallel"

# invariant: the wave level of an implementer is one past the deepest block of the parent it depends on, and
# invariant: the loop is bounded by the block count, so a depends_on cycle stops it instead of spinning.
mkdir -p "$tmp/lvl"
while read -r b; do
  [ "$b" != "$skeleton" ] || continue
  echo 1 > "$tmp/lvl/$b"
done < "$tmp/blocks"

count=$(wc -l < "$tmp/blocks")
i=0
while [ "$i" -lt "$count" ]; do
  changed=0
  while read -r b; do
    [ "$b" != "$skeleton" ] || continue
    for d in $(cat "$tmp/deps/$b"); do
      [ -f "$tmp/lvl/$d" ] || continue
      dl=$(cat "$tmp/lvl/$d"); bl=$(cat "$tmp/lvl/$b")
      if [ "$dl" -ge "$bl" ]; then echo $((dl + 1)) > "$tmp/lvl/$b"; changed=1; fi
    done
  done < "$tmp/blocks"
  [ "$changed" = 1 ] || break
  i=$((i + 1))
done

wave=0
print_wave() { wave=$((wave + 1)); printf 'wave %s:%s\n' "$wave" "$1"; }

if [ -f "$tmp/paths/$skeleton" ]; then print_wave " $skeleton"; fi

levels=$(for b in $(cat "$tmp/blocks"); do
  [ "$b" != "$skeleton" ] && cat "$tmp/lvl/$b" || :
done | sort -n -u)

for lv in $levels; do
  line='' n=0
  while read -r b; do
    [ "$b" != "$skeleton" ] || continue
    [ "$(cat "$tmp/lvl/$b")" = "$lv" ] || continue
    line="$line $b"; n=$((n + 1))
    if [ "$n" -ge 5 ]; then print_wave "$line"; line=''; n=0; fi
  done < "$tmp/blocks"
  [ -z "$line" ] || print_wave "$line"
done
