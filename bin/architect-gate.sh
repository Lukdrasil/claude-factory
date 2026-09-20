#!/bin/sh
# PreToolUse tripwire for the architect curation (architect-agent plan, decision 8): a task write — a Bash POST to
# /api/tasks, or a Write creating a task file under repos/<key>/tasks/ in a state clone — needs a valid verdict
# when the product repo has docs/architecture/. exit 2 = deny, the reason on stderr. The verdict format is defined
# in skills/architect-review/SKILL.md; this script only reads it. A verdict whose `scope:` is `quick` is the
# quick lane's, accepted without a plan hash and found by the task id.
# Deny on positive evidence only: everything the gate cannot resolve passes with a warning, so a forgotten check is
# blocked and an unrelated flow never is.
set -eu

deny() { printf 'architect-gate deny: %s\n' "$1" >&2; exit 2; }
warn() { printf 'architect-gate: %s\n' "$1" >&2; exit 0; }

input=$(cat)
# the same reader as policy-guard.sh — node is in the worker image, no parser of our own
node_json() { printf '%s' "$input" | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const o=JSON.parse(s);
const v=process.argv[1].split(".").reduce((a,k)=>a==null?a:a[k],o);
process.stdout.write(v==null?"":String(v))})' "$1"; }

tool=$(node_json tool_name) || warn "unreadable JSON on the hook stdin"
cwd=$(node_json cwd) || warn "unreadable JSON on the hook stdin"

# the plan slug of the task being written: decompose names `repos/<key>/plans/<slug>-plan-ready.md` in its `## Context`
plan_slug() { grep -oE 'plans/[A-Za-z0-9_.-]+-plan-ready\.md' | head -n1 | sed 's|^plans/||; s|-plan-ready\.md$||'; }

key=''
state=''
slug=''
task_id=''
case "$tool" in
  Bash)
    c=$(node_json tool_input.command) || warn "unreadable JSON on the hook stdin"
    case "$c" in *"/api/tasks"*) ;; *) exit 0 ;; esac
    printf '%s' "$c" | grep -q POST || exit 0
    # the repo key as the decompose skill writes it: `--arg repo "<key>"` or a "repo" field in the body
    key=$(printf '%s' "$c" | grep -oE -- '--arg[[:space:]]+repo[[:space:]]+"?[A-Za-z0-9_.-]+' | head -n1 | sed 's/.*[[:space:]"]//')
    if [ -z "$key" ]; then
      key=$(printf '%s' "$c" | grep -oE '"repo"[[:space:]]*:[[:space:]]*"[A-Za-z0-9_.-]+' | head -n1 | sed 's/.*"//')
    fi
    [ -n "$key" ] || warn "a POST to /api/tasks with no readable repo key — the product repo cannot be resolved"
    # the task body is inline in the command, or in the file `--rawfile markdown <path>` reads
    body=$c
    rf=$(printf '%s' "$c" | grep -oE -- '--rawfile[[:space:]]+[A-Za-z0-9_]+[[:space:]]+[^[:space:]"]+' | head -n1 | awk '{print $3}')
    if [ -n "$rf" ] && [ -f "$rf" ]; then body="$c
$(cat "$rf")"; fi
    slug=$(printf '%s' "$body" | plan_slug)
    ;;
  Write|Edit)
    p=$(node_json tool_input.file_path) || warn "unreadable JSON on the hook stdin"
    [ -n "$p" ] || exit 0
    case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
    case "$p" in */repos/*/tasks/*) ;; *) exit 0 ;; esac
    # only creating a task file is a task write; editing or overwriting one is the session's own status self-report
    if [ -e "$p" ]; then exit 0; fi
    state=${p%%/repos/*}
    # a task path outside a state clone is somebody else's repos/<key>/tasks/, not the rc standalone write
    [ -f "$state/repos.yml" ] || exit 0
    rest=${p#*/repos/}
    key=${rest%%/*}
    slug=$(node_json tool_input.content | plan_slug)
    task_id=$(basename "$p" .md | grep -oE '^T-[0-9]{3}(-[0-9]{2})?' || :)
    ;;
  *) exit 0 ;;
esac

# Product repo discovery per layout.
product=''
if [ -f "$cwd/repos.yml" ] && [ -d "$cwd/repos" ]; then
  # host session layout: cwd is a state clone; the product repo is the local clone for <key> from repos.yml
  [ -n "$state" ] || state=$cwd
  grep -qE "^[[:space:]]*$key:" "$cwd/repos.yml" || warn "repo key '$key' is not in repos.yml — no product repo to check"
  parent=$(dirname "$cwd")
  if [ "$(basename "$parent")" = "$key" ]; then
    product=$parent
  elif [ -d "$parent/$key" ]; then
    product="$parent/$key"
  fi
  [ -n "$product" ] || warn "the product repo for '$key' is not cloned next to the state clone — nothing to check"
else
  # worker/rc layout: cwd is inside the product clone, the state clone sits at <product>/state or ../state
  d=$cwd
  while :; do
    if [ -e "$d/.git" ]; then product=$d; break; fi
    parent=$(dirname "$d")
    if [ "$parent" = "$d" ]; then break; fi
    d=$parent
  done
  [ -n "$product" ] || warn "no product repo clone at or above cwd '$cwd' — nothing to check"
  if [ -z "$state" ]; then
    if [ -f "$product/state/repos.yml" ]; then
      state="$product/state"
    elif [ -f "$(dirname "$product")/state/repos.yml" ]; then
      state="$(dirname "$product")/state"
    else
      warn "no state clone at '$product/state' or next to it — the verdict cannot be found"
    fi
  fi
fi

# Repos without the docs skip curation entirely (plan, decision 6).
[ -d "$product/docs/architecture" ] || exit 0

if command -v sha256sum >/dev/null 2>&1; then
  sha256() { sha256sum "$1" | cut -d' ' -f1; }
elif command -v shasum >/dev/null 2>&1; then
  sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
else
  warn "no sha256 tool — the plan hash of the verdict cannot be recomputed"
fi

# A valid verdict is `aligned` or `overridden-by-human` whose plan_hash is the current hash of its plan file;
# a mismatch counts as no verdict. The task names the plan it came from, so only that plan's verdict is read —
# verdicts of other plans in the same directory are irrelevant. A task naming no plan cannot be resolved: pass.
# invariant: a quick-lane task (skills/factory/references/solve-quick.md) has no grilled plan to hash, so its
# invariant: verdict says `scope: quick` and is read by the task id instead of by a plan slug
fm() { sed -n "s/^$2:[[:space:]]*//p" "$1" 2>/dev/null | head -n1; }
quick_verdict() {
  [ -f "$1" ] || return 1
  [ "$(fm "$1" scope)" = quick ] || return 1
  case "$(fm "$1" verdict)" in aligned|overridden-by-human) return 0 ;; *) return 1 ;; esac
}

if [ -n "$task_id" ] && quick_verdict "$state/repos/$key/verdicts/$task_id.md"; then exit 0; fi

[ -n "$slug" ] || warn "the task for '$key' names no plans/<slug>-plan-ready.md, so its verdict cannot be found"

f="$state/repos/$key/verdicts/$slug.md"
reason="repos/$key/verdicts/$slug.md, the verdict of the plan this task names, is missing"
if quick_verdict "$f"; then exit 0; fi
if [ -f "$f" ]; then
  v=$(sed -n 's/^verdict:[[:space:]]*//p' "$f" | head -n1)
  plan=$(sed -n 's/^plan:[[:space:]]*//p' "$f" | head -n1)
  want=$(sed -n 's/^plan_hash:[[:space:]]*//p' "$f" | head -n1)
  case "$plan" in /*) planfile=$plan ;; *) planfile="$state/$plan" ;; esac
  case "$v" in
    aligned|overridden-by-human)
      if [ -z "$plan" ] || [ -z "$want" ]; then
        reason="$slug.md has no plan/plan_hash"
      elif [ ! -f "$planfile" ]; then
        reason="the plan '$plan' of $slug.md is missing"
      elif [ "$(sha256 "$planfile")" != "$want" ]; then
        reason="the plan_hash in $slug.md does not match '$plan'"
      else
        exit 0
      fi
      ;;
    *) reason="the verdict in $slug.md is '${v:-unreadable}'" ;;
  esac
fi

deny "the product repo '$product' has docs/architecture/, so a task for '$key' may only be written on an architect verdict — $reason. Run the architect-review skill (plan-check on the plan, cut-check on the task drafts), let the human decide on the findings, and write the verdict per its verdict contract; a plan edited after the review has to be reviewed again."
