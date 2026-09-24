#!/bin/sh
# map.sh over a throwaway state clone: the request map of skills/wayfinder, requests/<R-id>/map.md and its
# tickets requests/<R-id>/issues/NN-<slug>.md. --next allocates R-YYYYMMDD-n under the lock (live and archived
# ids counted), tickets are numbered and wired, claim/resolve/drop move a ticket, frontier and clear read the map,
# export seeds the grill of one repo, status walks the request lifecycle. Every write is one local commit of the
# request's own files; nothing is pushed.
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
has() { # <file> <text>
  if grep -qF -- "$2" "$1" 2>/dev/null; then printf yes; else printf no; fi
}

st="$tmp/state"
git init -q --bare "$tmp/origin.git"
git init -q -b main "$st"
git -C "$st" config user.email harness@localhost
git -C "$st" config user.name harness
mkdir -p "$st/repos/demo" "$st/repos/other"
printf 'demo:\n  path: /nowhere\n' > "$st/repos.yml"
printf 'shared notes\n' > "$st/notes.md"
git -C "$st" add -A
git -C "$st" commit -q -m fixture
git -C "$st" remote add origin "$tmp/origin.git"
git -C "$st" push -q origin main
pushed=$(git -C "$tmp/origin.git" rev-parse main)

map() { sh "$bin/map.sh" "$@" --state "$st"; }
head_() { git -C "$st" rev-parse HEAD; }
# one write: exit code, one new commit, and only files under requests/<R-id>/ in it
one_commit() { # <what> <R-id> <before>
  check "$1: one commit" "$3" "$(git -C "$st" rev-parse HEAD~1)"
  check "$1: only the request's files" '' \
    "$(git -C "$st" show --name-only --format= HEAD | grep -v "^requests/$2/" || :)"
}
field() { # <file> <Field>
  sed -n "s/^$2:[[:space:]]*//p" "$1" | head -n1
}

today=$(date +%Y%m%d)
printf 'another session, not committed\n' >> "$st/notes.md"

# --- new --next: two on one day are -1 and -2 ----------------------------------------------------------
b=$(head_)
r1=$(map new --next --destination 'Export invoices to the ledger' </dev/null) && rc=0 || rc=$?
check '--next exits 0' 0 "$rc"
check '--next prints the first id of the day' "R-$today-1" "$r1"
one_commit '--next' "R-$today-1" "$b"
m1="$st/requests/R-$today-1/map.md"
check 'the map starts charting' charting "$(awk 'FNR == 1 && /^---/ { fm = 1; next } fm && /^---/ { fm = 0; next }
  !fm && /^Status:/ { sub(/^Status:[ \t]*/, ""); print; exit }' "$m1")"
check 'the map carries the destination' yes "$(has "$m1" 'Export invoices to the ledger')"
check 'the frontmatter names the request' "R-$today-1" "$(field "$m1" request)"
for s in 'Destination' 'Notes' 'Decisions so far' 'Not yet specified' 'Out of scope' 'Terms'; do
  check "the map has ## $s" yes "$(has "$m1" "## $s")"
done
b=$(head_)
r2=$(map new --next --destination 'Second one' </dev/null)
check '--next again prints -2' "R-$today-2" "$r2"
one_commit '--next again' "R-$today-2" "$b"

# an archived id of the day is taken too
mkdir -p "$st/requests/archive/2026-09/R-$today-7"
printf -- '---\nrequest: R-%s-7\n---\n\nStatus: done\n' "$today" > "$st/requests/archive/2026-09/R-$today-7/map.md"
git -C "$st" add requests && git -C "$st" commit -q -m archived
r3=$(map new --next --destination 'Third' </dev/null)
check '--next counts the archive' "R-$today-8" "$r3"

# --- new <R-id> -------------------------------------------------------------------------------------------
R=R-20260901-1
b=$(head_)
out=$(map new "$R" --destination 'Invoices reach the ledger nightly' </dev/null) && rc=0 || rc=$?
check 'new <R-id> exits 0' 0 "$rc"
check 'new <R-id> prints it' "$R" "$out"
one_commit 'new <R-id>' "$R" "$b"
M="$st/requests/$R/map.md"
b=$(head_)
rc=0; map new "$R" --destination again </dev/null >/dev/null 2>&1 || rc=$?
check 'an existing id is refused' 1 "$rc"
rc=0; map new R-2026-1 --destination x </dev/null >/dev/null 2>&1 || rc=$?
check 'a malformed id is refused' 1 "$rc"
rc=0; map new R-20260901-9 </dev/null >/dev/null 2>&1 || rc=$?
check 'new without --destination is refused' 1 "$rc"
check 'no refusal committed' "$b" "$(head_)"

# --- tickets, numbered and wired --------------------------------------------------------------------------
I="$st/requests/$R/issues"
b=$(head_)
n=$(map ticket "$R" research 'Which ledger API' --repo demo </dev/null) && rc=0 || rc=$?
check 'ticket exits 0' 0 "$rc"
check 'the first ticket is 01' 01 "$n"
one_commit 'ticket' "$R" "$b"
t1="$I/01-which-ledger-api.md"
check 'the ticket file is NN-<slug>.md' yes "$([ -f "$t1" ] && echo yes || echo no)"
check 'Type' research "$(field "$t1" Type)"
check 'Status open' open "$(field "$t1" Status)"
check 'Blocked by none' none "$(field "$t1" 'Blocked by')"
check 'Repo' demo "$(field "$t1" Repo)"
check 'Claimed by none' none "$(field "$t1" 'Claimed by')"
check 'the title heads the ticket' '# Which ledger API' "$(head -n1 "$t1")"
check 'the question defaults to the title' yes "$(sed -n '/^## Question/,/^## /p' "$t1" | grep -qx 'Which ledger API' && echo yes || echo no)"
check 'an empty ## Answer' yes "$(has "$t1" '## Answer')"

n=$(printf 'Postgres or the ledger file store?\n' | map ticket "$R" grilling 'Pick the store' --blocked-by 1)
check 'the second ticket is 02' 02 "$n"
t2=$(ls "$I"/02-*.md)
check 'blocked by 01' 01 "$(field "$t2" 'Blocked by')"
check 'Repo defaults to all' all "$(field "$t2" Repo)"
check 'the question is stdin' yes "$(has "$t2" 'Postgres or the ledger file store?')"
n=$(map ticket "$R" task 'Get ledger access' --repo other </dev/null)
check 'the third ticket is 03' 03 "$n"
n=$(map ticket "$R" prototype 'Invoice row layout' --repo demo --blocked-by 01,03 </dev/null)
check 'the fourth ticket is 04' 04 "$n"
check 'two blockers' '01, 03' "$(field "$(ls "$I"/04-*.md)" 'Blocked by')"

b=$(head_)
rc=0; map ticket "$R" grilling 'Dangling' --blocked-by 09 </dev/null >/dev/null 2>&1 || rc=$?
check 'a blocker that does not exist is refused' 1 "$rc"
rc=0; map ticket "$R" chat 'Wrong type' </dev/null >/dev/null 2>&1 || rc=$?
check 'an unknown type is refused' 1 "$rc"
rc=0; map ticket R-20990101-1 grilling 'No map' </dev/null >/dev/null 2>&1 || rc=$?
check 'a ticket on no map is refused' 1 "$rc"
check 'no refusal committed a ticket' "$b" "$(head_)"

# --- frontier ---------------------------------------------------------------------------------------------
check 'the frontier: open, unblocked, unclaimed' "01 research Which ledger API
03 task Get ledger access" "$(map frontier "$R")"

# --- claim, resolve, drop ---------------------------------------------------------------------------------
b=$(head_)
rc=0; map claim "$R" 02 --by s1 >/dev/null 2>&1 || rc=$?
check 'a blocked ticket cannot be claimed' 1 "$rc"
check 'the refused claim committed nothing' "$b" "$(head_)"
map claim "$R" 1 --by s1 >/dev/null && rc=0 || rc=$?
check 'claim takes the number without its zero' 0 "$rc"
one_commit 'claim' "$R" "$b"
check 'claimed' claimed "$(field "$t1" Status)"
check 'Claimed by the session' s1 "$(field "$t1" 'Claimed by')"
check 'a claimed ticket leaves the frontier' '03 task Get ledger access' "$(map frontier "$R")"
rc=0; map claim "$R" 01 --by s2 >/dev/null 2>&1 || rc=$?
check 'a ticket claimed by another session is refused' 1 "$rc"
rc=0; printf 'x\n' | map resolve "$R" 01 --by s2 >/dev/null 2>&1 || rc=$?
check 'resolve by another session is refused' 1 "$rc"
rc=0; map resolve "$R" 01 --by s1 </dev/null >/dev/null 2>&1 || rc=$?
check 'resolve without an answer is refused' 1 "$rc"
rc=0; printf 'x\n' | map resolve "$R" 03 >/dev/null 2>&1 || rc=$?
check 'resolve of an unclaimed ticket is refused' 1 "$rc"

b=$(head_)
printf 'The REST API, v2.\nReport: repos/demo/research/ledger-api.md\n' | map resolve "$R" 01 --by s1 >/dev/null && rc=0 || rc=$?
check 'resolve exits 0' 0 "$rc"
one_commit 'resolve' "$R" "$b"
check 'resolved' resolved "$(field "$t1" Status)"
check 'the answer is in ## Answer' yes "$(sed -n '/^## Answer/,$p' "$t1" | grep -q 'Report: repos/demo/research/ledger-api.md' && echo yes || echo no)"
check 'Decisions so far points at it by name' yes "$(sed -n '/^## Decisions so far/,/^## /p' "$M" | grep -qF -- '- [Which ledger API](issues/01-which-ledger-api.md): The REST API, v2.' && echo yes || echo no)"
check '02 joins the frontier' "02 grilling Pick the store
03 task Get ledger access" "$(map frontier "$R")"

b=$(head_)
printf 'Access is the other team'"'"'s rollout, not this request.\n' | map drop "$R" 03 >/dev/null && rc=0 || rc=$?
check 'drop exits 0' 0 "$rc"
one_commit 'drop' "$R" "$b"
t3=$(ls "$I"/03-*.md)
check 'dropped' dropped "$(field "$t3" Status)"
check 'Out of scope holds the line' yes "$(sed -n '/^## Out of scope/,/^## /p' "$M" | grep -qF -- '- [Get ledger access](issues/03-get-ledger-access.md): Access is' && echo yes || echo no)"
check 'a dropped ticket is no decision' no "$(sed -n '/^## Decisions so far/,/^## /p' "$M" | grep -q 'Get ledger access' && echo yes || echo no)"
check 'a dropped blocker unblocks' "02 grilling Pick the store
04 prototype Invoice row layout" "$(map frontier "$R")"
rc=0; printf 'x\n' | map drop "$R" 01 >/dev/null 2>&1 || rc=$?
check 'a resolved ticket cannot be dropped' 1 "$rc"

# --- wire: blocking added after the ticket exists, never a cycle ------------------------------------------
n=$(map ticket "$R" grilling 'Name the export job' </dev/null)
check 'the fifth ticket is 05' 05 "$n"
b=$(head_)
map wire "$R" 02 --blocked-by 05 >/dev/null && rc=0 || rc=$?
check 'wire exits 0' 0 "$rc"
one_commit 'wire' "$R" "$b"
check 'wire adds the blocker' '01, 05' "$(field "$t2" 'Blocked by')"
b=$(head_)
rc=0; map wire "$R" 05 --blocked-by 02 >/dev/null 2>&1 || rc=$?
check 'a cycle is refused' 1 "$rc"
rc=0; map wire "$R" 05 --blocked-by 05 >/dev/null 2>&1 || rc=$?
check 'a ticket cannot block itself' 1 "$rc"
check 'no refused wire committed' "$b" "$(head_)"

# --- set: the sections a session writes -------------------------------------------------------------------
b=$(head_)
printf -- '- **Ledger**: the accounting system of record. Avoid: books\n' | map set "$R" terms && rc=0 || rc=$?
check 'set terms exits 0' 0 "$rc"
one_commit 'set terms' "$R" "$b"
printf 'The rollout order across the two repos.\n' | map set "$R" fog
check 'set fog writes Not yet specified' yes "$(sed -n '/^## Not yet specified/,/^## /p' "$M" | grep -q 'rollout order' && echo yes || echo no)"
rc=0; printf 'x\n' | map set "$R" decisions >/dev/null 2>&1 || rc=$?
check 'Decisions so far is not set by hand' 1 "$rc"

# --- clear -----------------------------------------------------------------------------------------------
rc=0; map clear "$R" >/dev/null 2>&1 || rc=$?
check 'clear with open tickets exits 1' 1 "$rc"
map claim "$R" 05 --by s3 >/dev/null
printf 'job name: ledger-export\n' | map resolve "$R" 05 --by s3 >/dev/null
map claim "$R" 02 --by s3 >/dev/null
printf 'Postgres.\n' | map resolve "$R" 02 --by s3 >/dev/null
map claim "$R" 04 --by s3 >/dev/null
rc=0; map clear "$R" >/dev/null 2>&1 || rc=$?
check 'clear with a claimed ticket exits 1' 1 "$rc"
printf 'One row per invoice, the sum last.\n' | map resolve "$R" 04 --by s3 >/dev/null
rc=0; map clear "$R" >"$tmp/out" 2>&1 || rc=$?
check 'clear with Not yet specified text exits 1' 1 "$rc"
check 'and says so' yes "$(has "$tmp/out" 'Not yet specified')"
map set "$R" fog </dev/null
rc=0; map clear "$R" >/dev/null 2>&1 || rc=$?
check 'clear with nothing left exits 0' 0 "$rc"
rc=0; map clear R-20990101-1 >/dev/null 2>&1 || rc=$?
check 'clear of no map is not clear' 1 "$rc"

# --- export for one repo ---------------------------------------------------------------------------------
map ticket "$R" grilling 'Other repo only' --repo other </dev/null >/dev/null
map claim "$R" 06 --by s4 >/dev/null
printf 'other answer\n' | map resolve "$R" 06 --by s4 >/dev/null
b=$(head_)
map export "$R" demo > "$tmp/export" && rc=0 || rc=$?
check 'export exits 0' 0 "$rc"
check 'export writes nothing' "$b" "$(head_)"
check 'export has the destination' yes "$(has "$tmp/export" 'Invoices reach the ledger nightly')"
check 'a Repo: demo ticket is a closed ledger row' yes "$(grep -E '^\| M01 \| research \| Which ledger API \| - \| closed \| The REST API, v2\.' "$tmp/export" >/dev/null && echo yes || echo no)"
check 'a Repo: all ticket is a closed ledger row' yes "$(grep -E '^\| M02 \| decision \| Pick the store \| M01, M05 \| closed \| Postgres\.' "$tmp/export" >/dev/null && echo yes || echo no)"
check 'a prototype stays a prototype' yes "$(grep -E '^\| M04 \| prototype \|' "$tmp/export" >/dev/null && echo yes || echo no)"
check 'a Repo: other ticket is not exported' no "$(has "$tmp/export" 'Other repo only')"
check 'a dropped ticket is no row' no "$(grep -E '^\| M03 ' "$tmp/export" >/dev/null && echo yes || echo no)"
check 'out of scope is exported' yes "$(has "$tmp/export" 'Access is the other team')"
check 'terms are exported' yes "$(has "$tmp/export" '**Ledger**: the accounting system of record')"
check 'export names request: for the plan' yes "$(has "$tmp/export" "request: $R")"

# --- status: the lifecycle and the way back ------------------------------------------------------------
st_of() { awk 'FNR == 1 && /^---/ { fm = 1; next } fm && /^---/ { fm = 0; next }
  !fm && /^Status:/ { sub(/^Status:[ \t]*/, ""); print; exit }' "$1"; }
b=$(head_)
map status "$R" grilling >/dev/null && rc=0 || rc=$?
check 'charting -> grilling' 0 "$rc"
one_commit 'status' "$R" "$b"
check 'the Status line moved' grilling "$(st_of "$M")"
rc=0; map status "$R" finished >/dev/null 2>&1 || rc=$?
check 'an unknown word is refused' 1 "$rc"
map status "$R" planned >/dev/null && rc=0 || rc=$?
check 'grilling -> planned once clear' 0 "$rc"
map status "$R" queued >/dev/null && rc=0 || rc=$?
check 'planned -> queued' 0 "$rc"
map status "$R" running >/dev/null && rc=0 || rc=$?
check 'queued -> running' 0 "$rc"
# [XR] a running map takes a new grilling ticket and goes back to grilling
n=$(map ticket "$R" grilling 'The other repo needs a hook' --repo other </dev/null) && rc=0 || rc=$?
check 'a running map accepts a ticket' 0 "$rc"
check 'numbered on' 07 "$n"
map status "$R" grilling >/dev/null && rc=0 || rc=$?
check 'running -> grilling' 0 "$rc"
rc=0; map status "$R" running >/dev/null 2>&1 || rc=$?
check 'back to running is refused while not clear' 1 "$rc"
check 'the refusal left grilling' grilling "$(st_of "$M")"
map claim "$R" 07 --by s5 >/dev/null
printf 'In scope: a new parent in other.\n' | map resolve "$R" 07 --by s5 >/dev/null
map status "$R" running >/dev/null && rc=0 || rc=$?
check 'grilling -> running once clear again' 0 "$rc"
map status "$R" done >/dev/null && rc=0 || rc=$?
check 'running -> done' 0 "$rc"
rc=0; map status "$R" running >/dev/null 2>&1 || rc=$?
check 'done is final' 1 "$rc"
rc=0; map ticket "$R" grilling 'Too late' </dev/null >/dev/null 2>&1 || rc=$?
check 'a done map takes no ticket' 1 "$rc"
R4=R-20260901-4
map new "$R4" --destination d </dev/null >/dev/null
rc=0; map status "$R4" done >/dev/null 2>&1 || rc=$?
check 'charting -> done is refused' 1 "$rc"

# --- the lock is taken ---------------------------------------------------------------------------------
rm -f "$tmp/held" "$tmp/release"
(. "$bin/lib-tasks.sh"; state_lock "$st" || exit 1; : > "$tmp/held"
 while [ ! -e "$tmp/release" ]; do sleep 0.2; done) &
holder=$!
n=0; while [ ! -e "$tmp/held" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
b=$(head_)
rc=0; STATE_LOCK_WAIT=1 sh "$bin/map.sh" new --next --destination x --state "$st" </dev/null >/dev/null 2>&1 || rc=$?
check 'a held state lock exits 2' 2 "$rc"
check 'a held state lock writes nothing' "$b" "$(head_)"
: > "$tmp/release"; wait "$holder"

# --- nothing pushes, nothing foreign is committed ------------------------------------------------------
check 'origin never moved' "$pushed" "$(git -C "$tmp/origin.git" rev-parse main)"
check 'the foreign edit is still uncommitted' ' M notes.md' "$(git -C "$st" status --porcelain -- notes.md)"
check 'every map write is committed' '' "$(git -C "$st" status --porcelain -- requests)"

exit $fail
