# Sourced by the suites that drive herdr, never run: `herdr_stub <dir>` puts a fake `herdr` first on PATH and
# exports HERDR_ENV=1. The fake appends every call to $HERDR_STUB_LOG, one line per call with each argument
# that holds a space in double quotes, and answers with the JSON shapes of herdr 0.8.2 (docs/herdr-research.md
# 1.3): an error is `{"error":{"code":..,"message":..},"id":..}` on stderr with exit 1, and a verb it does not
# know succeeds with no output.
#
# Live agents sit in panes. `herdr_agent <name> <status> <pane> [<session>]` makes one live in <pane>, in the
# tab `tab-<pane less its pane- prefix>`, with <session> as its `agent_session.value`; the name `-` is an agent
# herdr knows by its pane only (a manual launch, or any agent after a herdr restart). `herdr_tab <tab_id>
# <agent_status> <focused> [<agent name>]` makes a tab live, and the agent of that name live too, in the pane
# `pane-<tab less its tab- prefix>`. `herdr_procs <pane> [<command line>...]` sets what `pane process-info`
# reports as the pane's foreground processes, none for a bare shell. Names are the suite's to keep unique.
#
#   agent list                 every live agent: `name` (when named), `pane_id`, `tab_id`, `agent_status`,
#                              `agent_session.value` (when set), `focused`
#   agent get <target>         one agent by name or pane id; `agent_not_found` when none
#   agent wait <target> [--until S]... [--timeout MS]
#                              the agent at once when its status is in the --until set (default idle, done,
#                              blocked), `timeout` otherwise: the stub never blocks
#   agent rename <target> <name>|--clear
#   agent read <target> ...    $HERDR_STUB_READ as plain text
#   agent send-keys <target> <key>...
#   agent start ...            no output; `HERDR_STUB_START=<code>` makes it that error, e.g. agent_not_ready
#   workspace create ...       `.result.workspace` ws-1, `.result.tab` tab-1, `.result.root_pane` pane-1
#   tab create ...             `.result.tab` tab-1 in the --workspace (default ws-1), `.result.root_pane` pane-1
#   tab get <tab>, tab close <tab>
#                              from the live tabs, `tab_not_found` when not live; a close ends the tab's agents
#   notification show ...      `shown` and `reason`, the reason $HERDR_STUB_NOTIFY (default shown)
#   pane process-info --pane <pane>|--current
#                              the herdr_procs of the pane, else `claude` in a pane with a live agent, else
#                              `pane_not_found`
#
# Both creates write their `--env K=V` pairs to $HERDR_STUB_DIR/env/pane-1, one per line, so a suite reads the
# env the new pane got. `HERDR_STUB_CREATE` and `HERDR_STUB_WORKSPACE`, when set, are the reply of `tab create`
# and `workspace create` instead of the default. `herdr_tab_reply <tab_id> <exit> <text>` makes `tab get` of
# that tab answer <text>, on stdout with exit 0 and on stderr otherwise.
herdr_stub() { # <dir>
  mkdir -p "$1/bin" "$1/tabs" "$1/panes" "$1/procs" "$1/env" "$1/replies"
  cat > "$1/bin/herdr" <<'EOF'
#!/bin/sh
for a; do
  case "$a" in *' '*) printf '"%s" ' "$a" ;; *) printf '%s ' "$a" ;; esac
done >> "$HERDR_STUB_LOG"
echo >> "$HERDR_STUB_LOG"
d=$HERDR_STUB_DIR
verb="${1-} ${2-}"
id="cli:${1-}:$(printf '%s' "${2-}" | tr - _)"
[ $# -lt 2 ] || shift 2

err() { # <code> <message>
  printf '{"error":{"code":"%s","message":"%s"},"id":"%s"}\n' "$1" "$2" "$id" >&2
  exit 1
}
q() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }

# the pane of an agent target: a pane id with a live agent, or the pane whose agent has that name
pane_of() { # <target>
  if [ -f "$d/panes/$1" ]; then printf '%s\n' "$1"; return 0; fi
  for f in "$d"/panes/*; do
    [ -f "$f" ] || continue
    read -r n rest < "$f"
    if [ "$n" = "$1" ]; then printf '%s\n' "${f##*/}"; return 0; fi
  done
  err agent_not_found "agent target $1 not found"
}
agent_json() { # <pane>
  read -r n st ses tab fo < "$d/panes/$1"
  printf '{"agent":"claude",'
  [ "$ses" = - ] || printf '"agent_session":{"agent":"claude","kind":"id","source":"herdr:claude","value":"%s"},' "$ses"
  printf '"agent_status":"%s","focused":%s,' "$st" "$fo"
  [ "$n" = - ] || printf '"name":"%s",' "$n"
  printf '"pane_id":"%s","tab_id":"%s","workspace_id":"ws-1"}' "$1" "$tab"
}
agent_info() { # <pane>
  printf '{"id":"%s","result":{"agent":%s,"type":"agent_info"}}\n' "$id" "$(agent_json "$1")"
}
# the flags of a create: its workspace and label, and the env of the new pane
create_flags() {
  ws=ws-1 label=1
  : > "$d/env/pane-1"
  while [ $# -gt 0 ]; do
    case "$1" in
      --workspace) ws=$2; shift 2 ;;
      --label) label=$2; shift 2 ;;
      --env) printf '%s\n' "$2" >> "$d/env/pane-1"; shift 2 ;;
      --cwd) shift 2 ;;
      *) shift ;;
    esac
  done
}
tab_json() { # <tab> <workspace> <label>
  printf '{"agent_status":"unknown","focused":false,"label":"%s","number":1,"pane_count":1,"tab_id":"%s","workspace_id":"%s"}' \
    "$(q "$3")" "$1" "$2"
}
pane_json() { # <pane> <tab> <workspace>
  printf '{"agent_status":"unknown","focused":false,"pane_id":"%s","tab_id":"%s","workspace_id":"%s"}' "$1" "$2" "$3"
}

case "$verb" in
  'agent list')
    printf '{"id":"%s","result":{"agents":[' "$id"
    sep=''
    for f in "$d"/panes/*; do
      [ -f "$f" ] || continue
      printf '%s%s' "$sep" "$(agent_json "${f##*/}")"
      sep=,
    done
    printf '],"type":"agent_list"}}\n' ;;
  'agent get')
    p=$(pane_of "$1") || exit 1
    agent_info "$p" ;;
  'agent wait')
    p=$(pane_of "$1") || exit 1
    shift
    until=''
    while [ $# -gt 0 ]; do
      case "$1" in --until) until="$until $2"; shift 2 ;; *) shift ;; esac
    done
    read -r n st rest < "$d/panes/$p"
    case " ${until:-idle done blocked} " in
      *" $st "*) agent_info "$p" ;;
      *) err timeout "timed out waiting for agent $p" ;;
    esac ;;
  'agent rename')
    p=$(pane_of "$1") || exit 1
    new=$2
    [ "$new" != --clear ] || new=-
    read -r n rest < "$d/panes/$p"
    printf '%s %s\n' "$new" "$rest" > "$d/panes/$p"
    agent_info "$p" ;;
  'agent read')
    pane_of "$1" >/dev/null
    [ -z "${HERDR_STUB_READ:-}" ] || printf '%s\n' "$HERDR_STUB_READ" ;;
  'agent send-keys')
    pane_of "$1" >/dev/null
    printf '{"id":"%s","result":{"type":"ok"}}\n' "$id" ;;
  'agent start')
    [ -z "${HERDR_STUB_START:-}" ] || err "$HERDR_STUB_START" "agent $1 is not ready" ;;
  'workspace create')
    create_flags "$@"
    if [ -n "${HERDR_STUB_WORKSPACE+x}" ]; then printf '%s\n' "$HERDR_STUB_WORKSPACE"; exit 0; fi
    printf '{"id":"%s","result":{"root_pane":%s,"tab":%s,"type":"workspace_created","workspace":{"active_tab_id":"tab-1","agent_status":"unknown","focused":false,"label":"%s","number":1,"pane_count":1,"tab_count":1,"workspace_id":"ws-1"}}}\n' \
      "$id" "$(pane_json pane-1 tab-1 ws-1)" "$(tab_json tab-1 ws-1 1)" "$(q "$label")" ;;
  'tab create')
    create_flags "$@"
    if [ -n "${HERDR_STUB_CREATE+x}" ]; then printf '%s\n' "$HERDR_STUB_CREATE"; exit 0; fi
    printf '{"id":"%s","result":{"root_pane":%s,"tab":%s,"type":"tab_created"}}\n' \
      "$id" "$(pane_json pane-1 tab-1 "$ws")" "$(tab_json tab-1 "$ws" "$label")" ;;
  'tab get')
    if [ -f "$d/replies/$1" ]; then
      rc=$(head -n1 "$d/replies/$1")
      if [ "$rc" -eq 0 ]; then tail -n +2 "$d/replies/$1"; else tail -n +2 "$d/replies/$1" >&2; fi
      exit "$rc"
    fi
    [ -f "$d/tabs/$1" ] || err tab_not_found "tab $1 not found"
    read -r st fo ag < "$d/tabs/$1"
    printf '{"id":"%s","result":{"tab":{"agent_status":"%s","focused":%s,"label":"1","number":1,"pane_count":1,"tab_id":"%s","workspace_id":"ws-1"},"type":"tab_info"}}\n' \
      "$id" "$st" "$fo" "$1" ;;
  'tab close')
    [ -f "$d/tabs/$1" ] || err tab_not_found "tab $1 not found"
    rm -f "$d/tabs/$1"
    for f in "$d"/panes/*; do
      [ -f "$f" ] || continue
      read -r n st ses tab rest < "$f"
      [ "$tab" != "$1" ] || rm -f "$f"
    done
    printf '{"id":"%s","result":{"type":"ok"}}\n' "$id" ;;
  'notification show')
    r=${HERDR_STUB_NOTIFY:-shown}
    shown=false
    [ "$r" != shown ] || shown=true
    printf '{"id":"%s","result":{"reason":"%s","shown":%s,"type":"notification_show"}}\n' "$id" "$r" "$shown" ;;
  'pane process-info')
    p=${HERDR_PANE_ID:-}
    while [ $# -gt 0 ]; do
      case "$1" in --pane) p=$2; shift 2 ;; *) shift ;; esac
    done
    [ -n "$p" ] && { [ -f "$d/procs/$p" ] || [ -f "$d/panes/$p" ]; } || err pane_not_found "pane $p not found"
    fg=$( { if [ -f "$d/procs/$p" ]; then cat "$d/procs/$p"; else echo claude; fi; } | awk '
      function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
      NF { c++; n = split($0, w, " "); a = ""
           for (i = 1; i <= n; i++) a = a (i > 1 ? "," : "") "\"" esc(w[i]) "\""
           nm = w[1]; sub(/.*\//, "", nm)
           printf "%s{\"argv\":[%s],\"cmdline\":\"%s\",\"name\":\"%s\",\"pid\":%d}", (c > 1 ? "," : ""), a, esc($0), esc(nm), 1000 + c }')
    pg=1000
    [ -z "$fg" ] || pg=1001
    printf '{"id":"%s","result":{"process_info":{"foreground_process_group_id":%s,"foreground_processes":[%s],"pane_id":"%s","shell_pid":1000},"type":"pane_process_info"}}\n' \
      "$id" "$pg" "$fg" "$p" ;;
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
herdr_agent() { # <name> <status> <pane> [<session>]
  printf '%s %s %s tab-%s false\n' "$1" "$2" "${4:--}" "${3#pane-}" > "$HERDR_STUB_DIR/panes/$3"
}
herdr_tab() { # <tab_id> <agent_status> <focused> [<agent name>]
  printf '%s %s %s\n' "$2" "$3" "${4:-}" > "$HERDR_STUB_DIR/tabs/$1"
  [ -z "${4:-}" ] || printf '%s %s - %s %s\n' "$4" "$2" "$1" "$3" > "$HERDR_STUB_DIR/panes/pane-${1#tab-}"
}
herdr_procs() ( # <pane> [<command line>...]
  f="$HERDR_STUB_DIR/procs/$1"
  shift
  : > "$f"
  for c; do printf '%s\n' "$c" >> "$f"; done
)
herdr_tab_reply() { # <tab_id> <exit> <text>
  printf '%s\n%s\n' "$2" "$3" > "$HERDR_STUB_DIR/replies/$1"
}
