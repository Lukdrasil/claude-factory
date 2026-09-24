#!/bin/sh
# ui-relay.sh against one real `claude` on haiku in a herdr tab: 20 answers, one of them multi-line, each posted
# while the session is idle and the relay is up, must each arrive once as a user turn equal to the posted text
# within 4 s of the post (QS-02). Without herdr or a Claude login it prints a SKIP line, which is not a pass.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
root=$(dirname -- "$bin")

skip() { printf 'SKIP ui-relay-live: %s\n' "$1"; exit 0; }
command -v herdr >/dev/null 2>&1 || skip 'herdr is not on PATH'
herdr agent list >/dev/null 2>&1 || skip 'no herdr server answers'
command -v claude >/dev/null 2>&1 || skip 'claude is not on PATH'
auth=$(timeout 30 claude auth status 2>/dev/null) || skip 'claude auth status failed'
printf '%s' "$auth" | grep -q '"loggedIn": *true' || skip 'claude is not logged in'
projects=$(printf '%s' "$auth" | sed -n 's/.*"projectsDirectory": *"\([^"]*\)".*/\1/p')
projects=${projects:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects}

tmp=$(mktemp -d)
home="$tmp/ui" tab='' relay=''
cleanup() {
  [ -z "$relay" ] || kill "$relay" 2>/dev/null
  [ -z "$tab" ] || herdr tab close "$tab" >/dev/null 2>&1
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
die() { printf 'FAIL %s\n' "$1"; exit 1; }
now() { date +%s%3N; }

sid=$(cat /proc/sys/kernel/random/uuid)
nonce=$(printf '%s' "$sid" | cut -c1-8)
set -- tab create --cwd "$root" --label ui-relay-live --no-focus --env "FACTORY_UI_HOME=$home"
[ -z "${HERDR_WORKSPACE_ID:-}" ] || set -- "$@" --workspace "$HERDR_WORKSPACE_ID"
out=$(herdr "$@") || die "herdr tab create: $out"
tab=$(printf '%s' "$out" | sed -n 's/.*"tab_id":"\([^"]*\)".*/\1/p')
pane=$(printf '%s' "$out" | sed -n 's/.*"pane_id":"\([^"]*\)".*/\1/p')
[ -n "$pane" ] || die "herdr tab create gave no pane: $out"
out=$(herdr agent start "relaylive$nonce" --kind claude --pane "$pane" --timeout 90000 -- \
  --model haiku --session-id "$sid" --tools '' --settings '{"promptSuggestionEnabled":false}' \
  --append-system-prompt 'Reply to every user message with exactly the word ok and nothing else.' 2>&1) \
  || die "claude did not start in $pane (a trust dialog for $root answers once by hand): $out"

n=0
until herdr agent get "$pane" 2>/dev/null | grep -q "\"value\":\"$sid\""; do
  n=$((n + 1)); [ $n -lt 60 ] || die "herdr never reported session $sid for $pane; herdr's Claude hook must be installed"
  sleep 0.5
done
FACTORY_UI_HOME="$home" sh "$bin/ui-session.sh" --session "$sid" --pane "$pane" || die 'ui-session.sh failed'
mkdir -p "$home/sessions/$sid/answers"
sh "$bin/ui-relay.sh" --home "$home" > "$tmp/relay.log" 2>&1 &
relay=$!

esc() { printf '%s' "$1" | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'; }
turns() { # <escaped text>: the user turns in the transcript whose content is exactly that text
  f=$(find "$projects" -name "$sid.jsonl" 2>/dev/null | head -n1)
  [ -n "$f" ] || { echo 0; return; }
  grep '"type":"user"' "$f" | grep -cF "\"content\":\"$1\""
}
replies() {
  f=$(find "$projects" -name "$sid.jsonl" 2>/dev/null | head -n1)
  [ -n "$f" ] || { echo 0; return; }
  grep -c '"type":"assistant"' "$f"
}

worst=0 i=1
while [ $i -le 20 ]; do
  herdr agent wait "$pane" --until idle --until done --timeout 120000 >/dev/null 2>&1 || die "answer $i: the session never came back to idle"
  kill -0 "$relay" 2>/dev/null || die "the relay exited: $(tail -n 5 "$tmp/relay.log")"
  if [ $i -eq 7 ]; then text=$(printf 'relay live %s answer %s\nits second line' "$nonce" $i)
  else text="relay live $nonce answer $i"; fi
  e=$(esc "$text")
  before=$(replies)
  printf '%s' "$text" > "$home/sessions/$sid/answers/.post-$i"
  t0=$(now)
  mv "$home/sessions/$sid/answers/.post-$i" "$home/sessions/$sid/answers/$i-live.txt"
  until [ "$(turns "$e")" -ge 1 ]; do
    [ $(( $(now) - t0 )) -lt 20000 ] || die "answer $i never arrived as a user turn; relay: $(cat "$home/sessions/$sid/relay" 2>/dev/null)"
    sleep 0.1
  done
  dt=$(( $(now) - t0 ))
  [ $dt -le "$worst" ] || worst=$dt
  [ $dt -le 4000 ] || die "QS-02: answer $i took $dt ms from the post to the user turn, over 4000"
  n=0
  until [ "$(replies)" -gt "$before" ]; do
    n=$((n + 1)); [ $n -lt 600 ] || die "answer $i got no reply"
    sleep 0.1
  done
  i=$((i + 1))
done
herdr agent wait "$pane" --until idle --until done --timeout 120000 >/dev/null 2>&1

f=$(find "$projects" -name "$sid.jsonl" | head -n1)
i=1
while [ $i -le 20 ]; do
  if [ $i -eq 7 ]; then text=$(printf 'relay live %s answer %s\nits second line' "$nonce" $i)
  else text="relay live $nonce answer $i"; fi
  c=$(turns "$(esc "$text")")
  [ "$c" = 1 ] || die "answer $i is $c user turns, want exactly 1"
  i=$((i + 1))
done
typed=$(grep '"type":"user"' "$f" | grep -c '"promptSource":"typed"')
[ "$typed" = 20 ] || die "the transcript has $typed typed user turns, want 20: an answer was merged, doubled or foreign"
[ "$(cat "$home/sessions/$sid/delivered")" = 20 ] || die "delivered is $(cat "$home/sessions/$sid/delivered"), want 20"
printf 'PASS 20 of 20 answers arrived as user turns equal to the text, 1 multi-line, slowest %s ms (QS-02 4000)\n' "$worst"
