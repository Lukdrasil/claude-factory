#!/bin/sh
# PreToolUse dash gate (P7 "the text describes, the hook enforces"): the deterministic twin of the dash rule in
# prompts/worker-system-prompt.md. A Write/Edit/MultiEdit may not add a line carrying an em dash (U+2014) or an
# en dash (U+2013); the hyphen-minus is the only dash the harness writes. Every other character passes.
# exit 2 = deny, the reason on stderr reaches the agent.
# Deny on positive evidence only: a line that already stood in the text being replaced, or in the file a Write
# overwrites, is moved rather than added and passes, so an existing document can be edited without a rewrite.
set -eu

deny() { printf 'dash-gate deny: %s\n' "$1" >&2; exit 2; }

# one node run reads the hook stdin: the tool, the cwd, the target path, and the old/new text pairs of the
# edit. For Write the new text is `content` and the old text is the file on disk (read below); for Edit the
# pair is old_string/new_string; for MultiEdit every edit contributes its pair. Newlines are escaped on the way
# out so each field is one line, as comment-gate.sh does.
fields=$(node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
let o;try{o=JSON.parse(s)}catch(err){process.exit(3)}
const t=o.tool_input||{};
const olds=[t.old_string,...((t.edits)||[]).map(e=>e.old_string)].filter(x=>typeof x==="string").join("\n");
const news=[t.content,t.new_string,...((t.edits)||[]).map(e=>e.new_string)].filter(x=>typeof x==="string").join("\n");
const e=v=>String(v==null?"":v).replace(/\\/g,"\\\\").replace(/\n/g,"\\n").replace(/\r/g,"\\r");
process.stdout.write([o.tool_name,o.cwd,t.file_path,olds,news].map(e).join("\n"))})') || exit 0
{ IFS= read -r f_tool || f_tool=''
  IFS= read -r f_cwd  || f_cwd=''
  IFS= read -r f_path || f_path=''
  IFS= read -r f_old  || f_old=''
  IFS= read -r f_new  || f_new=''
} <<EOF
$fields
EOF
un() { case "$2" in *\\*) eval "$1=\$(printf '%b' \"\$2\")" ;; *) eval "$1=\$2" ;; esac; }

case "$f_tool" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac
un cwd "$f_cwd"; un p "$f_path"
[ -n "$p" ] || exit 0
case "$p" in /*|[A-Za-z]:*) abs=$p ;; *) abs="$cwd/$p" ;; esac

un old "$f_old"; un new "$f_new"
if [ "$f_tool" = Write ] && [ -f "$abs" ]; then old=$(cat "$abs"); fi

EM=$(printf '\342\200\224'); EN=$(printf '\342\200\223')
dashed() { printf '%s\n' "$1" | grep -F -e "$EM" -e "$EN" || :; }

oldl=$(dashed "$old")
added=''
n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  if [ -n "$oldl" ] && printf '%s\n' "$oldl" | grep -qxF -- "$line"; then continue; fi
  n=$((n + 1))
  [ $n -le 3 ] && added="$added
  $line"
done <<EOF
$(dashed "$new")
EOF
[ $n -eq 0 ] && exit 0

deny "$n new line(s) in '$abs' carry an em dash (U+2014) or an en dash (U+2013):$added
The hyphen-minus '-' is the only dash this harness writes, in prose, code, commit messages and task text alike.
Replace the character: a parenthetical takes a comma, a colon or a full stop, a range takes 'to', and where a
dash is still the right mark, write a hyphen-minus. Rewrite the edit and retry."
