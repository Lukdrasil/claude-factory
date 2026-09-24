#!/bin/sh
# ui-relay.sh against a stub `herdr` on PATH: the stub scripts each pane's state and session id and records every
# prompt with the state it was typed into and when that state began, so the settle rule, the pane check, replay
# (QS-04), isolation (QS-07) and merges (QS-08) are all read off the same record.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

. "$(dirname -- "$0")/ui-relay-stub.sh"
relay_stub "$tmp/path"
PATH="$tmp/path:$PATH"
export PATH

fail=0
pass() { printf 'PASS %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
is() { if [ "$2" = "$3" ]; then pass "$1"; else bad "$1: want '$3', got '$2'"; fi; }

fresh() { # a new UI home and a new stub record
  home="$tmp/ui$1" HERDR_STUB="$tmp/stub$1"
  export HERDR_STUB
  mkdir -p "$home/sessions" "$HERDR_STUB/panes" "$HERDR_STUB/texts"
  echo 0 > "$HERDR_STUB/calls"; echo 0 > "$HERDR_STUB/count"; : > "$HERDR_STUB/prompts"
}
session() { # <sid> <pane>
  mkdir -p "$home/sessions/$1/answers"
  printf -- '---\nsid: %s\npane: %s\nflow: grill\ntask: T-001\nstep: round 1\nupdated: 2026-09-23T00:00:00Z\n---\n' "$1" "$2" \
    > "$home/sessions/$1/session.md"
}
answer() { # <sid> <seq> <ask> <text>
  printf '%s' "$4" > "$home/sessions/$1/answers/$2-$3.txt"
}
relay() { # <settle> [--once]
  timeout 120 sh "$bin/ui-relay.sh" --home "$home" --settle "$@" >"$tmp/relay.out" 2>&1
}
typed() { # the texts typed, one per line, in order
  k=1; n=$(cat "$HERDR_STUB/count")
  while [ "$k" -le "$n" ]; do cat "$HERDR_STUB/texts/$k"; echo; k=$((k + 1)); done
}
col() { awk -v c="$1" '{ print $c }' "$HERDR_STUB/prompts"; }
delivered() { cat "$home/sessions/$1/delivered" 2>/dev/null || echo none; }
reason() { cat "$home/sessions/$1/relay" 2>/dev/null || echo none; }
settled_ok() { # <label> <settle s>: every prompt went into idle or done, with --wait, after that state held <settle> s
  v=$(awk -v s="$2" '($4 != "idle" && $4 != "done") || $6 != "yes" || $2 - $5 < s * 1000 { print; exit }' "$HERDR_STUB/prompts")
  if [ -z "$v" ] && [ -s "$HERDR_STUB/prompts" ]; then pass "$1"; else bad "$1: <n> <ms> <pane> <state> <since> <wait> = ${v:-no prompt at all}"; fi
}

# --- one answer: the text verbatim, the right pane, --wait, only after the settle time -----------------------
fresh 1
pane w1:p1 idle s1
session s1 w1:p1
mkdir -p "$home/sessions/empty"
answer s1 1 q1 'Q1 A, Q2 "B" $HOME \back *glob*'
setst w1:p1 idle
relay 2 --once; rc=$?
is 'a pass over a deliverable queue exits 0'             "$rc" 0
is 'the answer is typed once'                            "$(cat "$HERDR_STUB/count")" 1
is 'the text is the answer file verbatim, no prefix'     "$(cat "$HERDR_STUB/texts/1")" 'Q1 A, Q2 "B" $HOME \back *glob*'
is 'it is typed into the pane of session.md'             "$(col 3)" w1:p1
settled_ok 'it waits until the pane has held idle for the 2 s settle time, and uses --wait' 2
is 'delivered holds the seq'                             "$(delivered s1)" 1
is 'an empty queue leaves no relay file'                 "$(reason s1)" none
: > "$HERDR_STUB/log"
relay 0 --once
is 'a delivered answer is never typed again'             "$(cat "$HERDR_STUB/count")" 1

# --- a multi-line answer and a trailing newline arrive as one prompt, byte for byte --------------------------
fresh 2
pane w1:p1 done s1
session s1 w1:p1
printf 'Q1 C\nand a second line\n' > "$home/sessions/s1/answers/1-q1.txt"
relay 0 --once
if cmp -s "$home/sessions/s1/answers/1-q1.txt" "$HERDR_STUB/texts/1"; then pass 'a multi-line answer is one prompt, byte for byte'
else bad 'a multi-line answer is one prompt, byte for byte'; fi
is 'done counts as settled like idle'                    "$(delivered s1)" 1

# --- seq order is numeric, temp names are skipped, delivered is where it resumes --------------------------------
fresh 3
pane w1:p1 idle s1
session s1 w1:p1
answer s1 1 q1 one; answer s1 2 q1 two; answer s1 10 q2 ten
printf 'temp' > "$home/sessions/s1/answers/.answer.Xy12Ab"
printf 'temp' > "$home/sessions/s1/answers/.11-q2.txt"
printf 'temp' > "$home/sessions/s1/answers/12-q2.txt.tmp"
printf 'temp' > "$home/sessions/s1/answers/x-q2.txt"
relay 0 --once
is 'answers go in numeric seq order, temp names skipped' "$(typed | tr '\n' ' ')" 'one two ten '
is 'delivered holds one decimal seq, the last typed'     "$(delivered s1)" 10
answer s1 3 q2 three; answer s1 11 q3 eleven
relay 0 --once
is 'a seq at or below delivered is never typed, a later one is' "$(typed | tr '\n' ' ')" 'one two ten eleven '

# --- the settle rule: a pane that is working, or was working inside the settle window, is not typed into -------
fresh 4
pane w1:p1 working s1
session s1 w1:p1
answer s1 1 q1 'Q1 A'
relay 1 --once
is 'a working pane gets nothing'                         "$(cat "$HERDR_STUB/count")" 0
is 'the answer stays queued'                             "$(delivered s1)" none
setst w1:p1 idle
( sleep 0.6; setst w1:p1 working; sleep 0.8; setst w1:p1 idle ) &
relay 2 --once
wait
if [ -s "$HERDR_STUB/prompts" ]; then settled_ok 'a working blip inside the window restarts the settle time' 2
else pass 'a working blip inside the window restarts the settle time'; fi
: > "$HERDR_STUB/prompts"; echo 0 > "$HERDR_STUB/count"
setst w1:p1 idle
relay 2 --once
is 'once the pane holds idle, the queued answer is typed' "$(typed)" 'Q1 A'

# --- the pane check: blocked, a different session id, no session id, no pane ----------------------------------
fresh 5
pane w1:p1 blocked s1
session s1 w1:p1
answer s1 1 q1 'Q1 A'
relay 0 --once
is 'a pane at a dialog gets nothing'                     "$(cat "$HERDR_STUB/count")" 0
is 'the hold reason is blocked'                          "$(reason s1)" '1 blocked'
is 'the answer stays queued at a dialog'                 "$(delivered s1)" none
setst w1:p1 idle
relay 0 --once
is 'after the dialog the answer is typed'                "$(typed)" 'Q1 A'
is 'the relay file goes when the queue is empty'         "$(reason s1)" none

fresh 6
pane w1:p1 idle other-session
pane w1:p2 idle ''
session s1 w1:p1; answer s1 1 q1 'to s1'
session s2 w1:p2; answer s2 1 q1 'to s2'
session s3 w1:p9; answer s3 1 q1 'to s3'
session s4 '';    answer s4 1 q1 'to s4'
relay 0 --once
is 'no pane that reports another id, none, or does not exist gets anything' "$(cat "$HERDR_STUB/count")" 0
is 'a pane reporting another session id is gone'         "$(reason s1)" '1 gone'
is 'a pane reporting no session id is gone'              "$(reason s2)" '1 gone'
is 'a pane herdr does not know is gone'                  "$(reason s3)" '1 gone'
is 'a session.md with no pane is gone'                   "$(reason s4)" '1 gone'
is 'a gone answer stays queued'                          "$(delivered s1)" none

# --- a failed prompt stays queued, and QS-04: 20 answers queued while the relay was down, replayed in order ---
fresh 7
pane w1:p1 idle s1
session s1 w1:p1
i=1; while [ $i -le 20 ]; do answer s1 $i q$i "answer $i"; i=$((i + 1)); done
echo 8 > "$HERDR_STUB/failat"
relay 0 --once
is 'a failed prompt stops the queue before it'           "$(delivered s1)" 7
is 'the hold reason is prompt-failed'                    "$(reason s1)" '8 prompt-failed'
rm "$HERDR_STUB/failat"
relay 0 --once
want=$(i=1; while [ $i -le 20 ]; do echo "answer $i"; i=$((i + 1)); done)
is 'QS-04: 20 of 20 delivered after the restart, 0 lost, 0 out of order, 0 twice' "$(typed)" "$want"
is 'the replayed queue ends at 20'                       "$(delivered s1)" 20

# --- QS-07: two sessions, 100 interleaved answers, 0 cross-session turns; a pane now held by A is not C's -------
fresh 8
pane w1:pa idle sa
pane w1:pb idle sb
session sa w1:pa; session sb w1:pb; session sc w1:pa
i=1; while [ $i -le 50 ]; do answer sa $i q "A $i"; answer sb $i q "B $i"; i=$((i + 1)); done
answer sc 1 q 'C 1'
relay 0 --once
k=1 cross=0 ain='' bin_=''
while [ $k -le "$(cat "$HERDR_STUB/count")" ]; do
  p=$(awk -v k=$k '$1 == k { print $3 }' "$HERDR_STUB/prompts"); t=$(cat "$HERDR_STUB/texts/$k")
  case "$p:$t" in w1:pa:A\ *) ain="$ain${t#A } " ;; w1:pb:B\ *) bin_="$bin_${t#B } " ;; *) cross=$((cross + 1)) ;; esac
  k=$((k + 1))
done
want=$(i=1; while [ $i -le 50 ]; do printf '%s ' $i; i=$((i + 1)); done)
is 'QS-07: 0 cross-session turns in 100'                 "$cross" 0
is 'session A got its 50 in order'                       "$ain" "$want"
is 'session B got its 50 in order'                       "$bin_" "$want"
is 'a session whose pane reports another id gets nothing' "$(reason sc)" '1 gone'

# --- QS-08: 50 answers into a session that works or stops at a dialog: 0 typed mid-turn, 0 merged --------------
fresh 9
pane w1:p1 idle s1
session s1 w1:p1
i=1; while [ $i -le 50 ]; do answer s1 $i q "turn $i"; i=$((i + 1)); done
: > "$HERDR_STUB/panes/w1:p1/afters"
i=1; while [ $i -le 50 ]; do if [ $((i % 10)) -eq 5 ]; then echo blocked; else echo done; fi; i=$((i + 1)); done \
  > "$HERDR_STUB/panes/w1:p1/afters"
setst w1:p1 idle
runs=0 held=0
while [ "$(delivered s1)" != 50 ] && [ $runs -lt 20 ]; do
  relay 1 --once
  if [ "$(sed 's/.* //' "$home/sessions/s1/relay" 2>/dev/null)" = blocked ]; then held=$((held + 1)); setst w1:p1 done; fi
  runs=$((runs + 1))
done
want=$(i=1; while [ $i -le 50 ]; do echo "turn $i"; i=$((i + 1)); done)
is 'QS-08: 50 of 50 typed once each, in order'           "$(typed)" "$want"
is 'each of the 5 dialogs held the queue'                "$held" 5
settled_ok 'QS-08: 0 typed mid-turn or at a dialog, each after 1 s of settled state' 1

# --- the default home is the UI home ---------------------------------------------------------------------------
fresh 10
pane w1:p1 idle s1
session s1 w1:p1
answer s1 1 q1 'Q1 A'
FACTORY_UI_HOME="$home" timeout 60 sh "$bin/ui-relay.sh" --settle 0 --once >/dev/null 2>&1
is 'without --home the relay reads FACTORY_UI_HOME'      "$(delivered s1)" 1

exit $fail
