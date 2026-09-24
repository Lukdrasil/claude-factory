#!/bin/sh
# Stop hook: session statistics for the task — the archetype/tier from the frontmatter plus the model, duration
# and tokens from the transcript (transcript_path from the hook stdin) are sent through state-report.sh as a line
# for ## Attempts, failed tool calls as lines for ## Tool failures; the dashboard writes them (ADR-0047), or the
# state clone commits them without one (ADR-0050). A session that owns several tasks gets one line per task.
# Telemetry: it never blocks (always exit 0); duplicates are guarded by the session_id, in the line and in a marker file.
set -eu

# hook_field, task_of, the owner-based lookup and the layout resolver are shared with self-report-check.sh,
# compact-tripwire.sh and pre-compact.sh
. "$(dirname -- "$0")/lib-tasks.sh"

stdin=$(cat)
transcript=$(hook_field "$stdin" transcript_path)
sid=$(hook_field "$stdin" session_id)
[ -n "$transcript" ] && [ -f "$transcript" ] && [ -n "$sid" ] || exit 0

# resolve_state_dir (lib-tasks.sh) is the one state-clone rule, shared with self-report-check.sh and state-report.sh
state=$(resolve_state_dir "$PWD")

# the tasks are the ones whose `owner:` ends in this session's id (`factory@<host>:<session_id>`, ADR-0050), same
# as self-report-check.sh
ids=$(owned_task_ids "$sid") || :
[ -n "${ids:-}" ] || exit 0

# line 1 = stats, the rest = failed tool calls (tool + first line of the error, top 5 by frequency); read once
stats=''
fails=''
parse_transcript() {
  out=$(node -e '
const lines=require("fs").readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean);
const fmt=n=>n>=1e6?`${Math.round(n/1e5)/10}M`:n>=1e3?`${Math.round(n/1e3)}k`:String(n);
let t=[],model="?";
const tools={},fails={},usage=new Map();
for(const line of lines){
  let e;try{e=JSON.parse(line)}catch{continue}
  if(e.timestamp)t.push(Date.parse(e.timestamp));
  const m=e.message;if(!m)continue;
  if(m.model)model=m.model;
  if(Array.isArray(m.content))for(const b of m.content){
    if(b.type==="tool_use")tools[b.id]=b.name;
    if(b.type==="tool_result"&&b.is_error){
      const raw=typeof b.content==="string"?b.content:(b.content||[]).map(c=>c.text||"").join("\n");
      const msg=(raw.split("\n").find(l=>l.trim())||"").trim().slice(0,120);
      const key=`${tools[b.tool_use_id]||"?"}: ${msg}`;
      fails[key]=(fails[key]||0)+1;
    }
  }
  const u=m.usage;if(!u)continue;
  // one usage per message.id: Claude Code writes a line per content block and repeats the response usage on
  // each, streamed lines carry a partial output_tokens and a later variant can zero it out — the largest
  // output_tokens is the final one, so max-wins covers both shapes. No id (a subagent line) counts on its own.
  const k=m.id||Symbol();const p=usage.get(k);
  if(!p||(u.output_tokens||0)>(p.output_tokens||0))usage.set(k,u);
}
let inTok=0,outTok=0;
for(const u of usage.values()){
  inTok+=(u.input_tokens||0)+(u.cache_creation_input_tokens||0)+(u.cache_read_input_tokens||0);
  outTok+=u.output_tokens||0;
}
t=t.filter(Number.isFinite);
if(!t.length)process.exit(1);
const min=Math.round((Math.max(...t)-Math.min(...t))/60000);
const top=Object.entries(fails).sort((a,b)=>b[1]-a[1]).slice(0,5);
process.stdout.write([`${model}, ${min} min, tokens ${fmt(inTok)} in / ${fmt(outTok)} out`,
  ...top.map(([k,n])=>n>1?`${k} (${n}×)`:k)].join("\n"));
' "$transcript" 2>/dev/null) || return 1
  stats=$(printf '%s\n' "$out" | sed -n 1p)
  fails=$(printf '%s\n' "$out" | sed 1d)
  [ -n "$stats" ]
}

for id in $ids; do
  task=$(task_of "$id")
  [ -n "${task:-}" ] && [ -f "$task" ] || continue

  # stats belong with the final self-report; a stop without a terminal status is bounced by self-report-check
  status=$(sed -n 's/^status:[[:space:]]*//p' "$task" | head -n1)
  case "$status" in review|blocked|failed|tests_ready) ;; *) continue ;; esac

  # the line lands in the task file itself, so its sid marker catches a repeated Stop of this session
  grep -q "sid:$sid" "$task" 2>/dev/null && continue

  [ -n "$stats" ] || parse_transcript || exit 0

  attempt=$(sed -n 's/^attempt:[[:space:]]*//p' "$task" | head -n1)
  # #300: the archetype × tier of the dispatch goes into the line next to the model — the controller maps the
  # initial model from exactly this pair, so the mapping can be tuned from the stats without a second source.
  archetype=$(sed -n 's/^archetype:[[:space:]]*//p' "$task" | head -n1)
  tier=$(sed -n 's/^tier:[[:space:]]*//p' "$task" | head -n1)

  # ponytail: `set --` builds the argument list so the optional --tool-failures needs no second call site
  set -- --task "$id" --attempts "attempt ${attempt:-?} — $status, ${archetype:-?}/${tier:-?}, $stats <!-- sid:$sid -->"
  if [ -n "$fails" ]; then
    set -- "$@" --tool-failures "$(printf '%s\n' "$fails" | sed "s/^/attempt ${attempt:-?} — /")"
  fi

  # a report of its own: self-report-check.sh chains this script only after the agent's self-report went through, so
  # the stats are a commit on top of it, never part of it. A failure is simply dropped — worst case one stats line
  # is missing, which must not bring the task down.
  sh "$(dirname -- "$0")/state-report.sh" "$@" --message "stats: $id $status" >/dev/null 2>&1 || continue
done
exit 0
