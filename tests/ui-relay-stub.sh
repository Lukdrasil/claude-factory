#!/bin/sh
# The stub `herdr` of the relay suites, sourced by tests/ui-relay.test.sh and tests/ui-multisession.test.sh.
# `relay_stub <dir>` writes it as <dir>/herdr. It scripts each pane's state and session id under
# $HERDR_STUB/panes/<pane>/ and records every prompt in $HERDR_STUB/prompts as `<n> <ms> <pane> <state> <since>
# <wait>`, its text in $HERDR_STUB/texts/<n>; `pane` and `setst` script a pane.

relay_stub() { # <dir>
  mkdir -p "$1"
  cat > "$1/herdr" <<'STUB'
#!/bin/sh
set -u
now() { date +%s%3N; }
p="$HERDR_STUB/panes/$3"
setst() { printf '%s\n' "$1" > "$p/status"; echo $(( $(cat "$p/seq") + 1 )) > "$p/seq"; now > "$p/changed"; }
case "$1 $2" in
  'agent get')
    echo "get $(now) $3" >> "$HERDR_STUB/log"
    [ -d "$p" ] || { printf '{"error":{"code":"agent_not_found","message":"agent target %s not found"},"id":"cli:agent:get"}\n' "$3"; exit 1; }
    sid=$(cat "$p/sid")
    if [ -n "$sid" ]; then sess="{\"agent\":\"claude\",\"kind\":\"id\",\"source\":\"herdr:claude\",\"value\":\"$sid\"}"; else sess=null; fi
    printf '{"id":"cli:agent:get","result":{"agent":{"agent":"claude","agent_session":%s,"agent_status":"%s","cwd":"/w","focused":false,"interactive_ready":true,"pane_id":"%s","revision":3,"state_change_seq":%s,"tab_id":"w1:t1","terminal_id":"term_1","terminal_title":"x","workspace_id":"w1"},"type":"agent_info"}}\n' \
      "$sess" "$(cat "$p/status")" "$3" "$(cat "$p/seq")"
    ;;
  'agent prompt')
    [ -d "$p" ] || exit 1
    n=$(( $(cat "$HERDR_STUB/calls") + 1 )); echo "$n" > "$HERDR_STUB/calls"
    st=$(cat "$p/status")
    if [ "$st" = blocked ]; then echo '{"error":{"code":"agent_blocked"}}'; exit 1; fi
    if [ "$n" = "$(cat "$HERDR_STUB/failat" 2>/dev/null)" ]; then echo '{"error":{"code":"io"}}'; exit 1; fi
    wait=no; for a in "$@"; do [ "$a" = --wait ] && wait=yes; done
    k=$(( $(cat "$HERDR_STUB/count") + 1 )); echo "$k" > "$HERDR_STUB/count"
    printf '%s' "$4" > "$HERDR_STUB/texts/$k"
    echo "$k $(now) $3 $st $(cat "$p/changed") $wait" >> "$HERDR_STUB/prompts"
    setst working
    sleep 0.1
    after=$(head -n1 "$p/afters" 2>/dev/null); sed -i 1d "$p/afters" 2>/dev/null
    setst "${after:-done}"
    echo '{"id":"cli:agent:prompt","result":{"type":"ok"}}'
    ;;
  *) echo "stub herdr: unscripted $*" >&2; exit 1 ;;
esac
STUB
  chmod +x "$1/herdr"
}

pane() { # <pane> <status> <reported sid>
  mkdir -p "$HERDR_STUB/panes/$1"
  printf '%s\n' "$3" > "$HERDR_STUB/panes/$1/sid"
  echo 1 > "$HERDR_STUB/panes/$1/seq"
  setst "$1" "$2"
}
setst() { # <pane> <status>
  q="$HERDR_STUB/panes/$1"
  printf '%s\n' "$2" > "$q/status"; echo $(( $(cat "$q/seq") + 1 )) > "$q/seq"; date +%s%3N > "$q/changed"
}
