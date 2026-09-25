#!/bin/sh
# ui-relay.sh against a stub `herdr` whose prompt answers agent_prompt_stalled, the error herdr gives after the input
# was already sent: the answer counts as delivered and is never typed twice, while an error before the input
# (agent_blocked) keeps it queued.
set -u
unset FACTORY_UI_HOME FACTORY_UI_CONTAINER WORK_DIR
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/path" "$tmp/ui/sessions/s1/answers"
cat > "$tmp/path/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  'agent get')
    printf '{"result":{"agent":{"agent_session":{"kind":"id","value":"s1"},"agent_status":"idle","state_change_seq":%s}}}\n' \
      "$(wc -l < "$STUB/prompts")" ;;
  'agent prompt')
    echo "$*" >> "$STUB/prompts"
    printf '{"error":{"code":"%s","message":"x"},"id":"cli:agent:prompt"}\n' "$(cat "$STUB/code")"
    exit 1 ;;
esac
STUB
chmod +x "$tmp/path/herdr"
STUB=$tmp PATH="$tmp/path:$PATH"
export STUB PATH
: > "$tmp/prompts"
printf -- '---\nsid: s1\npane: w1:p1\n---\n' > "$tmp/ui/sessions/s1/session.md"
printf 'Q1 A' > "$tmp/ui/sessions/s1/answers/1-q1.txt"

fail=0
is() { if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf "FAIL %s: want '%s', got '%s'\n" "$1" "$3" "$2"; fail=1; fi; }
relay() { timeout 60 sh "$bin/ui-relay.sh" --home "$tmp/ui" --settle 0 --once >/dev/null 2>&1; }

echo agent_blocked > "$tmp/code"
relay
is 'an error before the input keeps the answer queued' "$(cat "$tmp/ui/sessions/s1/delivered" 2>/dev/null)" ''
is 'and holds it as prompt-failed'                    "$(cat "$tmp/ui/sessions/s1/relay" 2>/dev/null)" '1 prompt-failed'

echo agent_prompt_stalled > "$tmp/code"
: > "$tmp/prompts"
relay; relay
is 'a stalled prompt counts as delivered'             "$(cat "$tmp/ui/sessions/s1/delivered" 2>/dev/null)" 1
is 'and is typed once'                                "$(wc -l < "$tmp/prompts")" 1
is 'the wait ends at the first state after the submit' "$(sed 's/.*--wait//' "$tmp/prompts")" \
  ' --until working --until idle --until done --until blocked'
is 'the relay file goes with the queue'               "$(cat "$tmp/ui/sessions/s1/relay" 2>/dev/null)" ''

exit $fail
