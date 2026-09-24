# Sourced by the suites that drive herdr, never run: `herdr_stub <dir>` puts a fake `herdr` first on PATH and
# exports HERDR_ENV=1. The fake appends every call to $HERDR_STUB_LOG, one line per call with each argument
# that holds a space in double quotes, answers `tab create` with a tab `tab-1` and a pane `pane-1`, and
# succeeds on everything else.
herdr_stub() { # <dir>
  mkdir -p "$1/bin"
  cat > "$1/bin/herdr" <<'EOF'
#!/bin/sh
for a; do
  case "$a" in *' '*) printf '"%s" ' "$a" ;; *) printf '%s ' "$a" ;; esac
done >> "$HERDR_STUB_LOG"
echo >> "$HERDR_STUB_LOG"
case "$1 $2" in
  'tab create') printf '{"result":{"tab":{"tab_id":"tab-1"},"root_pane":{"pane_id":"pane-1"}}}\n' ;;
esac
exit 0
EOF
  chmod +x "$1/bin/herdr"
  : > "$1/herdr.log"
  HERDR_STUB_LOG="$1/herdr.log"
  PATH="$1/bin:$PATH"
  HERDR_ENV=1
  export HERDR_STUB_LOG PATH HERDR_ENV
}
