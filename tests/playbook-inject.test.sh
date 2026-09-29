#!/bin/sh
# playbook-inject.sh and the playbook in agent-brief.sh over a throwaway factory root: the SubagentStart hook
# prints the playbook of the agent's role for the repo key of the cwd as additionalContext, or nothing when the
# state has none; the key comes from a task worktree's path or from a clone registered with `path:` in
# repos.yml; agent-brief.sh prints the playbook after the rules and the memory.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

WORK_DIR="$tmp/factory"
export WORK_DIR
state="$WORK_DIR/state"
clone="$tmp/clones/demo"
mkdir -p "$state/repos/demo/agents/scout" "$state/repos/demo/agents/researcher" "$state/agents/scout/memory" \
  "$WORK_DIR/demo/T-001" "$clone" "$tmp/elsewhere"
git init -q "$clone"
printf 'demo: {url: https://example.invalid/demo.git, default_branch: main, path: %s}\n' "$clone" > "$state/repos.yml"
printf '# Scout playbook for demo\n\nRead "src/" first.\n' > "$state/repos/demo/agents/scout/playbook.md"
printf '# Researcher playbook for demo\n' > "$state/repos/demo/agents/researcher/playbook.md"
printf 'a scout lesson\n' > "$state/agents/scout/memory/lesson.md"

fail=0
pass() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
is() { # <label> <want> <got>
  if [ "$2" = "$3" ]; then pass "$1"; else bad "$1 (want '$2', got '$3')"; fi
}
hook() { # <cwd> <agent_type>
  printf '{"session_id":"S1","cwd":"%s","hook_event_name":"SubagentStart","agent_id":"A1","agent_type":"%s"}' "$1" "$2" \
    | sh "$bin/playbook-inject.sh" --hook
}
context() { # the additionalContext of a SubagentStart answer, or the parse error
  printf '%s' "$1" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const h=JSON.parse(s).hookSpecificOutput;
    process.stdout.write(h.hookEventName+"\n"+h.additionalContext)}catch(e){process.stdout.write("unparsable: "+s)}})'
}

want=$(printf 'SubagentStart\n<!-- repos/demo/agents/scout/playbook.md -->\n\n# Scout playbook for demo\n\nRead "src/" first.')
is 'a task worktree cwd gets the playbook of its repo key' "$want" "$(context "$(hook "$WORK_DIR/demo/T-001" claude-factory:scout)")"
is 'a cwd inside a registered clone gets the playbook of its key' "$want" "$(context "$(hook "$clone" scout)")"
case "$(context "$(hook "$WORK_DIR/demo/T-001" claude-factory:researcher-s3)")" in
  *'# Researcher playbook for demo'*) pass 'researcher-s3 gets the researcher playbook' ;;
  *) bad 'researcher-s3 gets the researcher playbook' ;;
esac
is 'an agent with no playbook gets nothing' '' "$(hook "$WORK_DIR/demo/T-001" claude-factory:implementer)"
is 'a cwd of no repo gets nothing' '' "$(hook "$tmp/elsewhere" scout)"
out=$(printf 'not json' | sh "$bin/playbook-inject.sh" --hook); rc=$?
is 'unparsable stdin: exit 0 with nothing' '0 ' "$rc $out"
out=$(printf '{"cwd":"%s","agent_type":"scout"}' "$clone" | WORK_DIR="$tmp/nowhere" sh "$bin/playbook-inject.sh" --hook); rc=$?
is 'a missing state: exit 0 with nothing' '0 ' "$rc $out"

is 'the CLI prints the playbook of <agent> <key>' "$(printf '<!-- repos/demo/agents/scout/playbook.md -->\n\n# Scout playbook for demo\n\nRead "src/" first.')" \
  "$(sh "$bin/playbook-inject.sh" scout demo)"
out=$(sh "$bin/playbook-inject.sh" scout other); rc=$?
is 'the CLI prints nothing for a key with no playbook' '0 ' "$rc $out"

# agent-brief.sh: rules, memory, then the playbook
brief=$(cd "$WORK_DIR/demo/T-001" && sh "$bin/agent-brief.sh" scout --state "$state")
order=$(printf '%s\n' "$brief" | grep -n -e '^<!-- skills/_shared/rules.md -->$' -e '^<!-- agents/scout/memory/lesson.md -->$' \
  -e '^<!-- repos/demo/agents/scout/playbook.md -->$' | cut -d: -f2 | tr '\n' ' ')
is 'agent-brief prints the playbook of the cwd key after the rules and the memory' \
  '<!-- skills/_shared/rules.md --> <!-- agents/scout/memory/lesson.md --> <!-- repos/demo/agents/scout/playbook.md --> ' "$order"
printf '%s\n' "$brief" | grep -q '^Read "src/" first\.$'; is 'agent-brief prints the playbook text' 0 $?
brief=$(cd "$tmp/elsewhere" && sh "$bin/agent-brief.sh" scout --state "$state" --key demo)
printf '%s\n' "$brief" | grep -q '^<!-- repos/demo/agents/scout/playbook.md -->$'; is 'agent-brief --key names the key' 0 $?
brief=$(cd "$tmp/elsewhere" && sh "$bin/agent-brief.sh" researcher-s1 --state "$state" --key demo)
printf '%s\n' "$brief" | grep -q '^# Researcher playbook for demo$'; is 'agent-brief prints the playbook of an agent with no memory' 0 $?
brief=$(cd "$tmp/elsewhere" && sh "$bin/agent-brief.sh" scout --state "$state")
printf '%s\n' "$brief" | grep -q '^<!-- repos/'; is 'agent-brief prints no playbook for a cwd of no repo' 1 $?
brief=$(cd "$WORK_DIR/demo/T-001" && sh "$bin/agent-brief.sh" implementer --state "$state"); rc=$?
printf '%s\n' "$brief" | grep -q '^<!-- repos/'; is 'agent-brief prints no playbook when the state has none' '0 1' "$rc $?"

exit $fail
