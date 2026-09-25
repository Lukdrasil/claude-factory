#!/bin/sh
# pass-stamp.sh (agent-org plan 3.8, Q4): a daily or weekly pass stamps the passes.yml of its scope, the four
# scope shapes each in their own folder, one commit under the state lock; --due lists the scopes whose pass is
# due (daily after 24 h or never, weekly after 7 d or never) and that have work for it (daily: a proposal or a
# draft, weekly: a draft, a proposal with a `Replaces:` line, or any proposal of a legacy tier, which the daily
# pass leaves for the human's round).
# session-start.sh prints that list in the state clone and nowhere else.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR=''
export WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
iso='[0-9][0-9]*-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'

# --- 1. stamping, one scope shape at a time ---------------------------------------------------------------------
st=$tmp/stamp/state
mkdir -p "$st/repos/demo/memory" "$st/memory/global" "$st/agents/scout/memory"
git init -q -b main "$st"
git -C "$st" config user.email harness@localhost
git -C "$st" config user.name harness
printf 'demo: {url: x, default_branch: main, path: %s}\n' "$tmp/demo" > "$st/repos.yml"
printf 'kept\n' > "$st/notes.md"
git -C "$st" add -A
git -C "$st" commit -q -m init
printf 'dirty\n' >> "$st/notes.md"

ps() { sh "$bin/pass-stamp.sh" "$@" --state "$st"; }
for pair in 'global memory/global/passes.yml' 'repo:demo repos/demo/memory/passes.yml' \
  'agent:scout agents/scout/memory/passes.yml' 'repo-agent:demo/implementer repos/demo/agents/implementer/passes.yml'; do
  set -- $pair
  ps daily "$1" >/dev/null 2>&1; rc=$?
  check "1. daily $1 exits 0" 0 "$rc"
  check "1. daily $1 writes $2" yes "$(sed -n 1p "$st/$2" 2>/dev/null | grep -qx "daily: $iso" && echo yes || echo no)"
  check "1. the weekly line of $1 reads never" 'weekly: never' "$(sed -n 2p "$st/$2" 2>/dev/null)"
  check "1. daily $1 is one commit" "chore(memory): daily pass $1" "$(git -C "$st" log -1 --format=%s)"
  check "1. the commit holds only $2" "$2" "$(git -C "$st" show --name-only --format= HEAD)"
done
check '1. another file stays uncommitted' ' M notes.md' "$(git -C "$st" status --porcelain)"
f=$st/repos/demo/agents/implementer/passes.yml
daily=$(sed -n 1p "$f")
ps weekly repo-agent:demo/implementer >/dev/null 2>&1; rc=$?
check '1. weekly exits 0' 0 "$rc"
check '1. weekly keeps the daily line' "$daily" "$(sed -n 1p "$f")"
check '1. weekly writes its own line' yes "$(sed -n 2p "$f" | grep -qx "weekly: $iso" && echo yes || echo no)"
check '1. passes.yml has two lines' 2 "$(wc -l < "$f" | tr -d ' ')"

head=$(git -C "$st" rev-parse HEAD)
for bad in 'monthly global' 'daily repo:nope' 'daily repo-agent:demo' 'daily repo-agent:nope/implementer' \
  'daily agent:' 'daily bogus' 'daily repo-agent:demo/../x'; do
  set -- $bad
  ps "$1" "$2" >/dev/null 2>&1; rc=$?
  check "1. '$bad' is refused" 1 "$rc"
done
check '1. a refusal commits nothing' "$head" "$(git -C "$st" rev-parse HEAD)"

rm -f "$tmp/held" "$tmp/release"
(. "$bin/lib-tasks.sh"; state_lock "$st" || exit 1; : > "$tmp/held"
 while [ ! -e "$tmp/release" ]; do sleep 1; done) &
holder=$!
n=0
while [ ! -e "$tmp/held" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
STATE_LOCK_WAIT=1 sh "$bin/pass-stamp.sh" daily global --state "$st" >/dev/null 2>&1; rc=$?
: > "$tmp/release"
wait "$holder"
check '1. a held state lock is exit 2' 2 "$rc"
check '1. and nothing is committed' "$head" "$(git -C "$st" rev-parse HEAD)"

# --- 2. --due ---------------------------------------------------------------------------------------------------
d=$tmp/due/state
mkdir -p "$d/memory/global" "$d/repos/demo/memory/proposals" "$d/agents/scout/memory/proposals" \
  "$d/agents/idle/memory"
for a in implementer scout test-designer quiet; do mkdir -p "$d/repos/demo/agents/$a/memory/proposals"; done
for a in implementer scout test-designer; do printf '# p\n' > "$d/repos/demo/agents/$a/memory/proposals/p.md"; done
printf '# p\n' > "$d/repos/demo/memory/proposals/p.md"
printf '# p\n' > "$d/agents/scout/memory/proposals/p.md"
for a in implementer scout test-designer; do mkdir -p "$d/repos/demo/agents/$a/drafts"; printf '# d\n' > "$d/repos/demo/agents/$a/drafts/d.md"; done
mkdir -p "$d/repos/demo/agents/drafter/drafts"
printf '# d\n' > "$d/repos/demo/agents/drafter/drafts/d.md"
mkdir -p "$d/repos/demo/agents/replacer/memory/proposals"
printf '# r\n\nReplaces: repos/demo/agents/replacer/memory/old.md\n' > "$d/repos/demo/agents/replacer/memory/proposals/r.md"
printf '# r\n\nReplaces: `agents/scout/memory/old.md`\n' > "$d/agents/scout/memory/proposals/r.md"
printf 'daily: 2026-09-24T13:00:00Z\nweekly: 2026-09-19T12:00:00Z\n' > "$d/repos/demo/agents/scout/passes.yml"
printf 'daily: 2026-09-24T11:00:00Z\nweekly: 2026-09-17T12:00:00Z\n' > "$d/repos/demo/agents/test-designer/passes.yml"
printf 'daily: 2026-09-24T12:00:00Z\nweekly: never\n' > "$d/repos/demo/memory/passes.yml"
printf 'daily: 2026-09-01T00:00:00Z\nweekly: never\n' > "$d/agents/scout/memory/passes.yml"

# now = 2026-09-25T12:00:00Z
due() { PASS_STAMP_NOW=1790337600 sh "$bin/pass-stamp.sh" --due "$1" --state "$d"; }
check '2. daily: never, 24 h and older, with work, sorted' 'agent:scout daily 2026-09-01T00:00:00Z
repo-agent:demo/drafter daily never
repo-agent:demo/implementer daily never
repo-agent:demo/replacer daily never
repo-agent:demo/test-designer daily 2026-09-24T11:00:00Z
repo:demo daily 2026-09-24T12:00:00Z' "$(due daily)"
check '2. weekly: never and 7 d and older, with drafts, a Replaces: proposal or a legacy proposal' 'agent:scout weekly never
repo-agent:demo/drafter weekly never
repo-agent:demo/implementer weekly never
repo-agent:demo/replacer weekly never
repo-agent:demo/test-designer weekly 2026-09-17T12:00:00Z
repo:demo weekly never' "$(due weekly)"
sh "$bin/pass-stamp.sh" --due monthly --state "$d" >/dev/null 2>&1; rc=$?
check '2. --due of an unknown kind is refused' 1 "$rc"
check '2. --due exits 0 on an empty state' '0 ' \
  "$(mkdir -p "$tmp/empty"; out=$(sh "$bin/pass-stamp.sh" --due daily --state "$tmp/empty"); printf '%s %s' "$?" "$out")"

mkdir -p "$st/repos/demo/agents/implementer/memory/proposals"
printf '# p\n' > "$st/repos/demo/agents/implementer/memory/proposals/p.md"
check '2. a scope stamped just now is not due' '' \
  "$(sh "$bin/pass-stamp.sh" --due daily --state "$st" | grep 'repo-agent:demo/implementer')"

# --- 3. session-start.sh prints the due passes in the state clone only ------------------------------------------
W=$tmp/w
git init -q -b main "$tmp/demo"
mkdir -p "$W"
cp -R "$d" "$W/state"
git init -q -b main "$W/state"
printf 'demo: {url: x, default_branch: main, path: %s}\n' "$tmp/demo" > "$W/state/repos.yml"
start() { # <cwd>
  printf '{"session_id":"s-1","cwd":"%s"}' "$1" | HOME=$tmp/home WORK_DIR=$W sh "$bin/session-start.sh" 2>/dev/null
}
out=$(start "$W/state")
check '3. the state clone gets the identity line' yes \
  "$(printf '%s' "$out" | grep -q 'Session identity: session_id s-1' && echo yes || echo no)"
check '3. the state clone gets the due daily passes' yes \
  "$(printf '%s' "$out" | grep -q 'repo-agent:demo/implementer daily never' && echo yes || echo no)"
check '3. and the due weekly passes' yes \
  "$(printf '%s' "$out" | grep -q 'repo-agent:demo/drafter weekly never' && echo yes || echo no)"
check '3. the state clone is not told to register' no \
  "$(printf '%s' "$out" | grep -q 'not registered' && echo yes || echo no)"
out=$(start "$tmp/demo")
check '3. a registered clone gets no due passes' no \
  "$(printf '%s' "$out" | grep -q 'daily never' && echo yes || echo no)"
check '3. nor a playbook line' no "$(printf '%s' "$out" | grep -q 'playbook' && echo yes || echo no)"
check '3. and keeps its identity line' yes \
  "$(printf '%s' "$out" | grep -q 'Session identity: session_id s-1' && echo yes || echo no)"

exit "$fail"
