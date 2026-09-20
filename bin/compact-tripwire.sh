#!/bin/sh
# PreToolUse hook on every tool: a tripwire on the *current* context size — the token sum (input + cache creation
# + cache read) of the latest assistant message in the transcript, counted once per message.id, not the session
# total session-stats.sh adds up. The window is configuration, not a derivation: nothing in the transcript tells
# a 200k session from a 1M one (a claude-opus-5[1m] session writes plain "claude-opus-5" in every `model` field,
# the 2026-09-07 lesson). Resolution order, first hit wins: FACTORY_CONTEXT_WINDOW > `context_window:` in
# $WORK_DIR/state/factory.yml > the model table (a `[1m]`, fable or mythos model id — a last resort, for a
# harness that does write a distinguishing id, not the mechanism the 1M case relies on) > 200000. Crossing 60 %
# of the window emits one nudge naming /compact and where the window came from, then one more every further
# 50000 tokens; a size past the window is proof the window is wrong, so that emits one nudge saying so and then
# stays quiet until a compact drops the size back under 60 %, which re-arms it normally. The level reached is
# kept per session in $WORK_DIR/<key>/.harness/<session_id>.tripwire (a registered cwd) or
# ${TMPDIR:-/tmp}/claude-tripwire-<session_id>. Never blocks, one node run: exit 0 always.
set -u
. "$(dirname -- "$0")/lib-tasks.sh"
stdin=$(cat)
transcript=$(hook_field "$stdin" transcript_path)
sid=$(hook_field "$stdin" session_id)
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -n "$sid" ] || exit 0

# the window itself: FACTORY_CONTEXT_WINDOW first, then context_window: in $WORK_DIR/state/factory.yml — read
# here, in sh, so it never depends on a registered cwd or on repos.yml existing. A non-numeric, zero, leading-zero
# (007 — refused rather than read as 7, matching factory-doctor.sh's guard, T-056-04) or absent value on either
# falls through silently to the model table (resolved in node below, where the model id lives).
cfg_window=""
cfg_src=""
case "${FACTORY_CONTEXT_WINDOW:-}" in
  ''|*[!0-9]*) : ;;
  0?*) : ;;
  *[!0]*) cfg_window=$FACTORY_CONTEXT_WINDOW; cfg_src=env ;;
  *) : ;;
esac
if [ -z "$cfg_window" ] && [ -n "${WORK_DIR:-}" ] && [ -r "$WORK_DIR/state/factory.yml" ]; then
  cw=$(sed -n 's/^context_window:[[:space:]]*//p' "$WORK_DIR/state/factory.yml" 2>/dev/null | head -n 1 | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
  case "${cw:-}" in
    ''|*[!0-9]*) : ;;
    0?*) : ;;
    *[!0]*) cfg_window=$cw; cfg_src=file ;;
    *) : ;;
  esac
fi

# only the tail is read: the size lives in the *latest* assistant message, and a long session's transcript is
# megabytes of history this hook would otherwise pipe through node on every single tool call. A first line the
# cut lands in the middle of fails JSON.parse and is skipped, like any other unparsable line.
out=$(tail -c 262144 "$transcript" | WINDOW=$cfg_window SRC=$cfg_src node -e '
// the model table is the last resort, for a harness that writes a distinguishing model id — not the mechanism
// that catches a 1M session in this harness, which never writes [1m], fable or mythos into `model`.
const WINDOWS=[[/\[1m\]/i,1000000],[/fable/i,1000000],[/mythos/i,1000000]],DEFAULT_WINDOW=200000;
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  let id=null,u=null,model="";
  for(const line of s.split("\n")){
    if(!line.includes("\"usage\""))continue;
    let e;try{e=JSON.parse(line)}catch{continue}
    const m=e.message;if(!m||!m.usage)continue;
    if(m.id&&m.id===id)continue;
    id=m.id||null;u=m.usage;model=String(m.model||"");
  }
  if(!u)return;
  const size=(u.input_tokens||0)+(u.cache_creation_input_tokens||0)+(u.cache_read_input_tokens||0);
  const preW=Number(process.env.WINDOW)||0;
  let w,tag;
  if(preW){w=preW;tag=process.env.SRC==="env"?"env":"file"}
  else{const row=WINDOWS.find(([re])=>re.test(model));if(row){w=row[1];tag="model"}else{w=DEFAULT_WINDOW;tag="default"}}
  const first=Math.floor(w*0.6),maxNormal=1+Math.floor((w-first)/50000);
  let level;
  if(size<first)level=0;else if(size<=w)level=1+Math.floor((size-first)/50000);else level=maxNormal+1;
  process.stdout.write(`${level} ${size} ${w} ${size>w?1:0} ${tag}`)})' 2>/dev/null) || exit 0
[ -n "$out" ] || exit 0
set -- $out
level=$1
size=$2
window=$3
runaway=$4
tag=$5
case "$tag" in
  env) label="FACTORY_CONTEXT_WINDOW" ;;
  file) label="factory.yml" ;;
  model) label="the model table" ;;
  *) label="the $window default" ;;
esac

cwd=$(hook_field "$stdin" cwd)
[ -n "$cwd" ] || cwd=.
key=$(repo_key_of_cwd "$cwd")
if [ -n "$key" ]; then
  mkdir -p "$WORK_DIR/$key/.harness" 2>/dev/null
  file="$WORK_DIR/$key/.harness/$sid.tripwire"
else
  file="${TMPDIR:-/tmp}/claude-tripwire-$sid"
fi
prev=$(cat "$file" 2>/dev/null)
case "${prev:-}" in ''|*[!0-9]*) prev=0 ;; esac

if [ "$level" -gt "$prev" ]; then
  # T-005 review: a PreToolUse hook that exits 0 has its stderr discarded — it surfaces only on exit 2 or under
  # --debug — so a nudge written only there reached nobody. The nudge is stdout JSON: `additionalContext` puts it
  # in front of the model (which is the one that has to run /compact), `systemMessage` in front of the human. The
  # stderr line stays for --debug. node builds the JSON so the message is escaped, not hand-quoted.
  if [ "$runaway" = 1 ]; then
    msg=$(printf 'compact-tripwire: the context is at %s of %s tokens (%s %%), already past the window — the window (from %s) is probably wrong or misconfigured; run /compact, then check it. No further nudge follows until a compact drops the size back down.' \
      "$size" "$window" "$((size * 100 / window))" "$label")
  else
    msg=$(printf 'compact-tripwire: the context is at %s of %s tokens (%s %%) — run /compact now, before the next long step; the progress file is your notes across it. (window from %s)' \
      "$size" "$window" "$((size * 100 / window))" "$label")
  fi
  printf '%s\n' "$msg" >&2
  M=$msg node -e 'const m=process.env.M;process.stdout.write(JSON.stringify(
    {hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:m},systemMessage:m}))' 2>/dev/null || :
fi
[ "$level" = "$prev" ] || printf '%s\n' "$level" > "$file" 2>/dev/null
exit 0
