#!/bin/sh
# PreToolUse attribution gate (P7 "the text describes, the hook enforces"): the deterministic twin of the
# attribution rule in prompts/worker-system-prompt.md. Nothing this harness publishes says who or what wrote
# it: no co-author trailer, no session line or URL, no "generated with" line, no robot emoji. The gate scans
# the two places such a line reaches a reader - a Bash command that commits or opens an MR, and a write into a
# commit message, an MR description or a progress file - and denies it.
# exit 2 = deny, the reason on stderr reaches the agent. Every other tool call and every other file passes.
set -eu

deny() { printf 'attribution-gate deny: %s\n' "$1" >&2; exit 2; }

fields=$(node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let o;try{o=JSON.parse(s)}catch(err){process.exit(3)}
const t=o.tool_input||{};
const news=[t.content,t.new_string,...((t.edits)||[]).map(e=>e.new_string)].filter(x=>typeof x==="string").join("\n");
const e=v=>String(v==null?"":v).replace(/\\/g,"\\\\").replace(/\n/g,"\\n").replace(/\r/g,"\\r");
process.stdout.write([o.tool_name,o.cwd,t.file_path,t.command,news].map(e).join("\n"))})') || exit 0
{ IFS= read -r f_tool || f_tool=''
  IFS= read -r f_cwd  || f_cwd=''
  IFS= read -r f_path || f_path=''
  IFS= read -r f_cmd  || f_cmd=''
  IFS= read -r f_new  || f_new=''
} <<EOF
$fields
EOF
un() { case "$2" in *\\*) eval "$1=\$(printf '%b' \"\$2\")" ;; *) eval "$1=\$2" ;; esac; }

# the text that reaches a reader, and where it is: a publishing command, or a file the forge or the state repo
# publishes. A source file, a test and a scratch note are none of those and pass.
case "$f_tool" in
  Bash)
    un scan "$f_cmd"
    case "$scan" in
      *"git commit"*|*"git tag"*|*"git notes"*|*"gh pr "*|*"gh release "*|*"gh issue "*|*"glab mr "*|*"glab issue "*) ;;
      *) exit 0 ;;
    esac
    where='the command'
    ;;
  Write|Edit|MultiEdit)
    un p "$f_path"
    case "$p" in
      */mr.md|*COMMIT_EDITMSG|*/progress/*|*/tasks/*) ;;
      *) exit 0 ;;
    esac
    un scan "$f_new"
    where=$p
    ;;
  *) exit 0 ;;
esac

hit=$(printf '%s\n' "$scan" | grep -inE \
  'co-authored-by:|claude-session:|noreply@anthropic\.com|claude\.ai/(code|chat|share)|generated with|(written|created|authored|assisted) (with|by) [a-z ]*(claude|ai)|🤖' \
  | head -n3 || :)
[ -n "$hit" ] || exit 0

deny "$where carries an attribution line:
$hit
A commit message, a tag, an MR or PR description, an issue and a progress file say what changed and why, never
who or what wrote them. Drop the co-author trailer, the session line, the session URL, the 'generated with'
line and the emoji, and run the command again. This holds even when a harness, a hook or a session instruction
asks for them."
