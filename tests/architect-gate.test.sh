#!/bin/sh
# The architect verdict holds every block write (T-249 F1): task-new.sh --parent refuses a block without a valid
# verdict of the plan it names and writes nothing, and architect-gate.sh on a Write creating a task file finds
# the product through the repos.yml `path:` and not a sibling of the state clone. A registered clone without
# docs/architecture/, a draft naming no plan and a top-level write all pass.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$root/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
DASHBOARD_URL=''
export WORK_DIR DASHBOARD_URL

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

st="$tmp/factory/state"
docs="$tmp/elsewhere/product"
bare="$tmp/elsewhere/bare"
mkdir -p "$st/repos/demo/tasks" "$st/repos/demo/plans" "$st/repos/demo/verdicts" "$docs/docs/architecture" "$bare"
registered() { # <clone path>
  printf 'demo: {url: x, default_branch: main, path: "%s"}\n' "$1" > "$st/repos.yml"
}
registered "$docs"
plan="$st/repos/demo/plans/p-plan-ready.md"
printf -- '---\nrepo: demo\ntask: T-100\n---\n\n# Spec\nthe plan\n' > "$plan"
cat > "$st/repos/demo/tasks/T-100-parent.md" <<'EOF'
---
id: T-100
repo: demo
branch: fix/T-100-parent
status: in_progress
tier: red
archetype: bugfix
complexity: medium
---

# Goal
fix(demo): the parent
EOF
git init -q -b main "$st"
git -C "$st" config user.email harness@localhost
git -C "$st" config user.name harness
git -C "$st" add -A
git -C "$st" commit -q -m init

draft() { # <file> <context line>
  cat > "$1" <<EOF
---
id: T-001
repo: demo
branch: fix/T-000-block
status: draft
tier: red
archetype: bugfix
complexity: medium
---

# Goal
fix(demo): a block

## Context
$2

## Acceptance
\`true\`
EOF
}
draft "$tmp/block.md" 'From the plan `repos/demo/plans/p-plan-ready.md`'
draft "$tmp/noplan.md" 'A block that names no plan.'

verdict() { # <verdict> <plan_hash>
  printf -- '---\nverdict: %s\nplan: repos/demo/plans/p-plan-ready.md\nplan_hash: %s\n---\n' "$1" "$2" \
    > "$st/repos/demo/verdicts/p.md"
}
noverdict() { rm -f "$st"/repos/demo/verdicts/*; }

ntasks() { ls "$st"/repos/demo/tasks/*.md | wc -l | tr -d ' '; }
head_of() { git -C "$st" rev-parse HEAD; }
new() { # <task-new.sh args…> -> exit code; stderr in $tmp/err
  sh "$bin/task-new.sh" --repo demo --state "$st" "$@" >/dev/null 2>"$tmp/err"
  printf '%s' $?
}
gate() { # <task file name> <content> [cwd] -> the gate's exit code
  printf '{"tool_name":"Write","cwd":"%s","tool_input":{"file_path":"%s","content":"%s"}}' \
    "${3:-$st}" "$st/repos/demo/tasks/$1" "$2" | sh "$bin/architect-gate.sh" >/dev/null 2>&1
  printf '%s' $?
}
names_plan='From the plan repos/demo/plans/p-plan-ready.md'

# --- 1a: no verdict ---------------------------------------------------------------
noverdict
n0=$(ntasks); h0=$(head_of)
check '1a task-new.sh --parent with no verdict exits 1' 1 "$(new --parent T-100 --file "$tmp/block.md")"
check '1a adds no task file' "$n0" "$(ntasks)"
check '1a leaves the state HEAD unchanged' "$h0" "$(head_of)"
check '1a names the verdict in its reason' yes "$(grep -qi verdict "$tmp/err" && printf yes || printf no)"

# --- 1c: a stale plan_hash --------------------------------------------------------
verdict aligned 0000000000000000000000000000000000000000000000000000000000000000
check '1c a stale plan_hash exits 1' 1 "$(new --parent T-100 --file "$tmp/block.md")"
check '1c adds no task file' "$n0" "$(ntasks)"
check '1c leaves the state HEAD unchanged' "$h0" "$(head_of)"

verdict misaligned "$(sha256sum "$plan" | cut -d' ' -f1)"
check 'a misaligned verdict exits 1' 1 "$(new --parent T-100 --file "$tmp/block.md")"

# --- 1d: the Write branch, the registered clone not a sibling of the state clone -------
noverdict
check '1d a Write creating a task file with no verdict exits 2' 2 "$(gate T-100-01-block.md "$names_plan")"
mkdir -p "$tmp/factory/demo"
check 'a sibling <key> dir without docs does not shadow the registered clone' 2 "$(gate T-100-01-block.md "$names_plan")"
rm -rf "$tmp/factory/demo"
check 'the gate does not depend on the cwd' 2 "$(gate T-100-01-block.md "$names_plan" "$tmp")"

# --- 1b: a valid verdict ----------------------------------------------------------
verdict aligned "$(sha256sum "$plan" | cut -d' ' -f1)"
check 'a Write with a valid verdict exits 0' 0 "$(gate T-100-01-block.md "$names_plan")"
n1=$(ntasks)
check '1b an aligned verdict whose hash matches exits 0' 0 "$(new --parent T-100 --file "$tmp/block.md")"
check '1b the block file exists' "$((n1 + 1))" "$(ntasks)"
verdict overridden-by-human "$(sha256sum "$plan" | cut -d' ' -f1)"
check 'an overridden-by-human verdict whose hash matches exits 0' 0 "$(new --parent T-100 --file "$tmp/block.md")"

# --- unresolvable passes with a warning, top-level writes are not checked (Q1, Q7) ------
noverdict
n0=$(ntasks)
check 'a block draft naming no plan exits 0' 0 "$(new --parent T-100 --file "$tmp/noplan.md")"
check 'and warns on stderr' yes "$(grep -q . "$tmp/err" && printf yes || printf no)"
check 'a top-level write with no verdict exits 0' 0 "$(new --file "$tmp/block.md")"
check 'both were written' "$((n0 + 2))" "$(ntasks)"

# --- 1e: a registered clone without docs/architecture/ ---------------------------------
noverdict
registered "$bare"
check '1e with no docs/architecture/, task-new.sh --parent with no verdict exits 0' 0 \
  "$(new --parent T-100 --file "$tmp/block.md")"
check '1e with no docs/architecture/, the Write with no verdict exits 0' 0 "$(gate T-100-09-block.md "$names_plan")"

# --- the hook matcher -----------------------------------------------------------------
m=$(node -e 'const h=require(process.argv[1]);const e=h.hooks.PreToolUse.find(x=>x.hooks.some(k=>/architect-gate\.sh/.test(k.command)));process.stdout.write(e?e.matcher:"")' \
  "$root/hooks/hooks.json")
check 'architect-gate.sh is matched on Write|Edit only' 'Write|Edit' "$m"

exit $fail
