#!/bin/sh
# PreToolUse comment gate (P7 "the text describes, the hook enforces"): the deterministic twin of the
# comment-policy skill. A Write/Edit/MultiEdit into a code file inside a task work dir may add a comment line
# only when it belongs to an allowed class, recognised by its prefix — `why:`, `invariant:`, `warn:`, `see:` —
# or is a doc comment (`///`), a shebang, a license header, or a tool directive. Every other new comment line is denied with the
# three-question test and the replacements on stderr, so the agent says it in a name, a method, a test or the
# commit message instead. exit 2 = deny, the reason on stderr reaches the agent.
# Deny on positive evidence only: a file outside a task work dir, a non-code extension, a repo whose toolset
# says `comments: free`, and a comment line that already stood in the text being replaced all pass.
set -eu

deny() { printf 'comment-gate deny: %s\n' "$1" >&2; exit 2; }

. "$(dirname -- "$0")/lib-tasks.sh"

# one node run reads the hook stdin: the tool, the cwd, the target path, and the old/new text pairs of the
# edit — for Write the new text is `content` and the old text is the file on disk (read below); for Edit the
# pair is old_string/new_string; for MultiEdit every edit contributes its pair. Newlines are escaped on the way
# out so each field is one line, as policy-guard.sh does.
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
case "$p" in /*|[A-Za-z]:*) ;; *) p="$cwd/$p" ;; esac
norm_into abs "$p"

# --- 1. the comment syntax of the file, by extension; anything else is not code for this gate --------------
ext=${abs##*.}
case "$abs" in */*.*) ;; *) exit 0 ;; esac
case "$ext" in
  cs|fs|java|kt|kts|go|rs|swift|scala|dart|php|c|h|cc|cpp|hpp|js|jsx|ts|tsx|mjs|cjs) marker=slash ;;
  sh|bash|zsh|py|rb|ps1|psm1|psd1|pl) marker=hash ;;
  sql) marker=dash ;;
  *) exit 0 ;;
esac

# --- 2. only a target inside a task work dir is gated; the repo can switch the gate off in its toolset -----
root=${WORK_DIR:-}
if ! { [ -n "$root" ] && resolve_layout "$abs" "$root"; }; then
  d=${cwd%/*}; root=${d%/*}
  resolve_layout "$abs" "$root" || exit 0
fi
# resolve_layout answers for any path under the root; only a task worktree (T-NNN or T-NNN-NN) is gated
is_task_id "$LO_TASK" || exit 0
state=$LO_STATE
key=''
if [ "$LO_POSTURE" = standalone ]; then
  norm_into nroot "$root"; rest=${abs#"$nroot"/}; key=${rest%%/*}
elif [ -d "$state" ]; then
  tf=$(task_of "$LO_TASK") || tf=''
  [ -n "$tf" ] && key=$(sed -n 's/^repo:[[:space:]]*//p' "$tf" | head -n1 | sed 's/[[:space:]]*#.*//')
fi
if [ -n "$key" ] && [ -f "$state/repos/$key/toolset.md" ]; then
  mode=$(awk '/^---[ \t\r]*$/ { if (++fence == 2) exit; next }
              fence == 1 && /^comments:[ \t]*/ { sub(/^comments:[ \t]*/, ""); sub(/[ \t\r]+$/, ""); print; exit }' \
         "$state/repos/$key/toolset.md")
  [ "$mode" = free ] && exit 0
fi

# --- 3. the comment lines the edit adds: in the new text and absent from the old ---------------------------
un old "$f_old"; un new "$f_new"
if [ "$f_tool" = Write ] && [ -f "$abs" ]; then old=$(cat "$abs"); fi

# a full-line comment: the first non-blank characters are the marker. Trailing comments after code are not
# scanned — a `//` inside a string or a URL would make the gate lie, and the reviewer reads the diff anyway.
comment_lines() { # <text> — one trimmed comment line per output line
  case "$marker" in
    slash) printf '%s\n' "$1" | sed -n 's/^[[:space:]]*\(\/\/.*\|\/\*.*\|\* .*\|\*\/.*\|\*\)$/\1/p' ;;
    hash)  printf '%s\n' "$1" | sed -n 's/^[[:space:]]*\(#.*\)$/\1/p' ;;
    dash)  printf '%s\n' "$1" | sed -n 's/^[[:space:]]*\(--.*\)$/\1/p' ;;
  esac
}
# the classes that pass: a doc comment, a shebang, a license header, a directive a tool reads, and the four
# prefixed classes of the comment-policy skill. Case matters: the prefix is the contract the reviewer greps for.
allowed() { # <trimmed comment line>
  case "$1" in
    '///'*|'/**'*|'#!'*) return 0 ;;
    '// why: '?*|'// invariant: '?*|'// warn: '?*|'// see: '?*) return 0 ;;
    '# why: '?*|'# invariant: '?*|'# warn: '?*|'# see: '?*) return 0 ;;
    '-- why: '?*|'-- invariant: '?*|'-- warn: '?*|'-- see: '?*) return 0 ;;
    '// Copyright'*|'// SPDX-'*|'# Copyright'*|'# SPDX-'*|'-- Copyright'*|'-- SPDX-'*) return 0 ;;
    '# shellcheck '*|'# noqa'*|'# type: '*|'# pragma: '*|'# fmt: '*|'# pylint: '*|'#Requires '*|'#requires '*) return 0 ;;
    '* '*|'*/'*|'*') return 0 ;;
  esac
  return 1
}

oldc=$(comment_lines "$old")
added=''
n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  allowed "$line" && continue
  # a comment that already stood in the replaced text is moved, not added
  if [ -n "$oldc" ] && printf '%s\n' "$oldc" | grep -qxF -- "$line"; then continue; fi
  n=$((n + 1))
  [ $n -le 3 ] && added="$added
  $line"
done <<EOF
$(comment_lines "$new")
EOF
[ $n -eq 0 ] && exit 0

deny "$n new comment line(s) in '$abs' (comment-policy):$added
A comment passes only when it states what the reader cannot get from the code, its names, its tests or the docs. Ask three questions: (1) can a name, a method, a type or an assertion say it? then write that instead; (2) is it the history, the intent of the change, or a todo? then it belongs in the commit message, the progress file or a task; (3) is it a reason, an invariant, a warning or an external reference the code cannot express? then keep it with its class prefix — '// why: <the non-obvious reason, a link for a workaround, numbers for a measurement>', '// invariant: <what must hold and who relies on it>', '// warn: <what breaks when this changes>', '// see: <url|ADR|issue> <what it settles>' ('#' or '--' for the file's syntax). Doc comments ('///'), a shebang, a license header and tool directives pass as they are. Restated code, section headers, commented-out code and TODOs never pass. Rewrite the edit and retry; the reference is \${CLAUDE_PLUGIN_ROOT}/skills/comment-policy/SKILL.md."
