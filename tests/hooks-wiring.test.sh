#!/bin/sh
# hooks/hooks.json: `hooks` is the only top-level key, every key under it is an event name, Stop has exactly
# one hook, every command names a script that exists under bin/, and the capacity and playbook hooks sit on
# their events: PreToolUse on Agent, SubagentStart, SubagentStop (hooks/README.md).
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
  case "$e" in SessionStart|PreToolUse|PostToolUse|PreCompact|Stop|Notification|UserPromptSubmit|SubagentStart|SubagentStop|SessionEnd) ;; *) bad=1 ;; esac
done
check $bad "every key under hooks is an event name ($events)"

n=$(node -e 'const h=require(process.argv[1]);process.stdout.write(String(h.hooks.Stop.reduce((a,m)=>a+m.hooks.length,0)))' "$f")
[ "$n" = 1 ]; check $? "Stop has exactly one hook ($n)"

# one `<event> <matcher or -> <command>` line per hook, the plugin root prefix dropped
lines=$(node -e 'const h=require(process.argv[1]);for(const [e,ms] of Object.entries(h.hooks))for(const m of ms)for(const k of m.hooks)
  process.stdout.write(e+" "+(m.matcher||"-")+" "+k.command.replace("${CLAUDE_PLUGIN_ROOT}/","")+"\n")' "$f")

# the script is the first word of the command, its arguments are not files
missing=0
while read -r e m c rest; do
  [ -f "$root/$c" ] || { printf 'FAIL missing script %s\n' "$c"; missing=1; }
done <<EOF
$lines
EOF
check $missing "every hook command names a script under bin/"

has() { # <label> <line>
  printf '%s\n' "$lines" | grep -qxF "$2"; check $? "$1"
}
has "PreToolUse on Agent runs the capacity gate" 'PreToolUse Agent bin/capacity.sh --hook pretooluse'
has "SubagentStart acquires the lease" 'SubagentStart - bin/capacity.sh --hook subagentstart'
has "SubagentStart injects the playbook" 'SubagentStart - bin/playbook-inject.sh --hook'
has "SubagentStop releases the lease" 'SubagentStop - bin/capacity.sh --hook subagentstop'
exit $fail
