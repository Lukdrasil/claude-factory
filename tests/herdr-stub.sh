# Sourced by the suites that drive herdr, never run: `herdr_stub <dir>` puts a fake `herdr` first on PATH and
# exports HERDR_ENV=1. The fake appends every call to $HERDR_STUB_LOG, one line per call with each argument
# that holds a space in double quotes, answers `tab create` with a tab `tab-1` and a pane `pane-1`, and
# succeeds on everything else.
#
# `herdr_tab <tab_id> <agent_status> <focused> [<agent name>]` makes a tab live, with the agent under that name
# live too. `tab get` and `agent get` answer from the live tabs and agents the way herdr 0.8.2 does, `tab close`
# ends a live tab and its agent, and a tab or agent that is not live is `tab_not_found` or `agent_not_found` on
# stderr with exit 1.
herdr_stub() { # <dir>
  mkdir -p "$1/bin" "$1/tabs" "$1/agents"
  cat > "$1/bin/herdr" <<'EOF'
#!/bin/sh
for a; do
  case "$a" in *' '*) printf '"%s" ' "$a" ;; *) printf '%s ' "$a" ;; esac
done >> "$HERDR_STUB_LOG"
echo >> "$HERDR_STUB_LOG"
d=$HERDR_STUB_DIR
case "$1 $2" in
  'tab create') printf '{"result":{"tab":{"tab_id":"tab-1"},"root_pane":{"pane_id":"pane-1"}}}\n' ;;
  'tab get')
    [ -f "$d/tabs/$3" ] || { printf '{"error":{"code":"tab_not_found","message":"tab %s not found"},"id":"cli:tab:get"}\n' "$3" >&2; exit 1; }
    read -r st fo ag < "$d/tabs/$3"
    printf '{"id":"cli:tab:get","result":{"tab":{"agent_status":"%s","focused":%s,"pane_count":1,"tab_id":"%s"},"type":"tab_info"}}\n' "$st" "$fo" "$3" ;;
  'tab close')
    [ -f "$d/tabs/$3" ] || { printf '{"error":{"code":"tab_not_found","message":"tab %s not found"},"id":"cli:tab:close"}\n' "$3" >&2; exit 1; }
    read -r st fo ag < "$d/tabs/$3"
    rm -f "$d/tabs/$3"
    [ -z "$ag" ] || rm -f "$d/agents/$ag"
    printf '{"id":"cli:tab:close","result":{"type":"ok"}}\n' ;;
  'agent get')
    [ -f "$d/agents/$3" ] || { printf '{"error":{"code":"agent_not_found","message":"agent target %s not found"},"id":"cli:agent:get"}\n' "$3" >&2; exit 1; }
    printf '{"id":"cli:agent:get","result":{"agent":{"agent_status":"%s","name":"%s"},"type":"agent_info"}}\n' "$(cat "$d/agents/$3")" "$3" ;;
esac
exit 0
EOF
  chmod +x "$1/bin/herdr"
  : > "$1/herdr.log"
  HERDR_STUB_LOG="$1/herdr.log"
  HERDR_STUB_DIR="$1"
  PATH="$1/bin:$PATH"
  HERDR_ENV=1
  export HERDR_STUB_LOG HERDR_STUB_DIR PATH HERDR_ENV
}
herdr_tab() { # <tab_id> <agent_status> <focused> [<agent name>]
  printf '%s %s %s\n' "$2" "$3" "${4:-}" > "$HERDR_STUB_DIR/tabs/$1"
  [ -z "${4:-}" ] || printf '%s\n' "$2" > "$HERDR_STUB_DIR/agents/$4"
}
