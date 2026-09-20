#!/bin/sh
# hooks/hooks.json: `hooks` is the only top-level key, every key under it is an event name, Stop has exactly
# one hook, and every command names a script that exists under bin/ (hooks/README.md).
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
f="$root/hooks/hooks.json"
fail=0
check() { # <ok 0|1> <label>
  if [ "$1" -eq 0 ]; then printf 'PASS %s\n' "$2"; else printf 'FAIL %s\n' "$2"; fail=1; fi
}

top=$(node -e 'const h=require(process.argv[1]);process.stdout.write(Object.keys(h).join(" "))' "$f")
[ "$top" = hooks ]; check $? "hooks is the only top-level key ($top)"

events=$(node -e 'const h=require(process.argv[1]);process.stdout.write(Object.keys(h.hooks).join(" "))' "$f")
bad=0
for e in $events; do
  case "$e" in SessionStart|PreToolUse|PostToolUse|PreCompact|Stop|Notification|UserPromptSubmit|SubagentStop|SessionEnd) ;; *) bad=1 ;; esac
done
check $bad "every key under hooks is an event name ($events)"

n=$(node -e 'const h=require(process.argv[1]);process.stdout.write(String(h.hooks.Stop.reduce((a,m)=>a+m.hooks.length,0)))' "$f")
[ "$n" = 1 ]; check $? "Stop has exactly one hook ($n)"

missing=0
for c in $(node -e 'const h=require(process.argv[1]);for(const ms of Object.values(h.hooks))for(const m of ms)for(const k of m.hooks)process.stdout.write(k.command+"\n")' "$f"); do
  p=$(printf '%s' "$c" | sed 's|\${CLAUDE_PLUGIN_ROOT}|'"$root"'|')
  [ -f "$p" ] || { printf 'FAIL missing script %s\n' "$c"; missing=1; }
done
check $missing "every hook command names a script under bin/"
exit $fail
