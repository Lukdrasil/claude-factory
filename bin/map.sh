#!/bin/sh
# The request map of skills/wayfinder in the state clone: requests/<R-id>/map.md (the index: destination, notes,
# decisions so far, not yet specified, out of scope, terms, and the request's `Status:` line under the
# frontmatter) and one file per decision ticket, requests/<R-id>/issues/NN-<slug>.md. This script is the only
# writer of both: every write takes the state lock, changes the request's own files and commits exactly those
# paths through state_write (lib-tasks.sh), so a request id is picked and written under one lock and another
# session's uncommitted edit never rides along. It never pushes; state-push.sh publishes in the background.
# The shapes are in skills/wayfinder/references/format.md, the one place the UI reads them from.
#
#   map.sh new <R-id>|--next --destination <text>        a map in `charting`; --next picks R-YYYYMMDD-n
#   map.sh ticket <R-id> <type> <title> [--repo <key>] [--blocked-by NN,..]   the question on stdin, else the title
#   map.sh wire <R-id> <NN> --blocked-by NN,..           adds blockers to a ticket that exists (create, then wire)
#   map.sh claim|resolve|drop <R-id> <NN> [--by <sid>]   resolve takes the answer on stdin, drop the reason
#   map.sh set <R-id> destination|notes|fog|terms|out-of-scope   the section's new body on stdin
#   map.sh frontier <R-id>                                `<NN> <type> <title>` per open, unblocked, unclaimed ticket
#   map.sh clear <R-id>                                   exit 0 when no ticket is open or claimed and nothing is
#                                                         left under Not yet specified
#   map.sh export <R-id> <key>                            the grill's seed for one repo, on stdout
#   map.sh status <R-id> charting|grilling|planned|queued|running|done
#   every form takes [--state <dir>]; default $WORK_DIR/state, else the clone the cwd resolves to
#
# Types: research, prototype, grilling, task. A ticket is `open`, `claimed` (by one session, before any work),
# `resolved` (its answer in `## Answer`, a line in Decisions so far) or `dropped` (ruled out of scope, a line in
# Out of scope). A ticket is unblocked when every ticket it is blocked by is resolved or dropped. A ticket number
# is `[0-9][0-9]*`, written with two digits at least; `1` and `01` name the same ticket.
# Status: planned, queued, running and done need the map clear, done is reached from running only and is final;
# a map in any other status takes a new ticket and goes back to grilling ([XR]), and forward again once clear.
#
# Exit 0 done; 1 refused (usage, an unknown request or ticket, a move the ticket or the status does not allow,
# and `clear` when the map is not clear), nothing written; 2 not written (the state lock was held for longer than
# STATE_LOCK_WAIT seconds, default 30, or git refused the commit, which is then undone).
set -eu
. "$(dirname -- "$0")/lib-tasks.sh"

die() { printf 'map: %s\n' "$1" >&2; exit 1; }
die2() { printf 'map: %s\n' "$1" >&2; exit 2; }
usage='usage: map.sh new <R-id>|--next --destination <text> | ticket <R-id> <type> <title> [--repo <key>] [--blocked-by NN,..] | wire <R-id> <NN> --blocked-by NN,.. | claim|resolve|drop <R-id> <NN> [--by <sid>] | set <R-id> <section> | frontier <R-id> | clear <R-id> | export <R-id> <key> | status <R-id> <word> [--state <dir>]'

cmd='' a1='' a2='' a3='' n=0
state='' dest='' dest_set='' repo=all blocked='' by='' next=''
while [ $# -gt 0 ]; do
  case "$1" in
    --state|--destination|--repo|--blocked-by|--by)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in
        --state) state=$2 ;;
        --destination) dest=$2; dest_set=1 ;;
        --repo) repo=$2 ;;
        --blocked-by) blocked=$2 ;;
        --by) by=$2 ;;
      esac
      shift 2 ;;
    --next) next=1; shift ;;
    -*) die "unknown argument '$1'; $usage" ;;
    *)
      case $n in
        0) cmd=$1 ;; 1) a1=$1 ;; 2) a2=$1 ;; 3) a3=$1 ;;
        *) die "too many arguments; $usage" ;;
      esac
      n=$((n + 1)); shift ;;
  esac
done
[ -n "$cmd" ] || die "$usage"

# see: solve-next.sh, the same resolution, anchored absolute
if [ -z "$state" ]; then
  if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR/state/repos" ]; then
    state="$WORK_DIR/state"
  else
    here=$(pwd)
    state=$(resolve_state_dir "$here")
    case "$state" in /*|[A-Za-z]:/*) ;; *) state="$here/$state" ;; esac
  fi
fi
state=${state%/}

valid_rid() { printf '%s\n' "$1" | grep -Eq '^R-[0-9]{8}-[0-9]+$'; }
num() { printf '%s' "$1" | sed 's/^0*//; s/^$/0/'; }
is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; }

# --- reading the map and its tickets -------------------------------------------------------------------
# the Status: line under the frontmatter (state-archive.sh reads it the same way)
map_status() {
  awk 'FNR == 1 && /^---[ \t]*$/ { fm = 1; next } fm && /^---[ \t]*$/ { fm = 0; next }
    !fm && /^Status:/ { sub(/^Status:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$mapf"
}
# the body of one `## <heading>` section, blank lines at both ends dropped
section() { # <file> <heading>
  awk -v h="## $2" '$0 == h { on = 1; next } on && /^## / { exit } on { a[n++] = $0 }
    END { i = 0; while (i < n && a[i] ~ /^[ \t]*$/) i++; while (n > i && a[n - 1] ~ /^[ \t]*$/) n--
          for (; i < n; i++) print a[i] }' "$1"
}
# a ticket field is a `<Field>: value` line above the first `## ` heading
tf() { # <ticket> <Field>
  awk -v f="$2" '/^## / { exit } index($0, f ":") == 1 { v = substr($0, length(f) + 2); gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }' "$1"
}
title_of() { sed -n 's/^# //p' "$1" | head -n1; }
nn_of() { nb=${1##*/}; printf '%s' "${nb%%-*}"; }
# every ticket file in number order
tickets() {
  for tk_f in "$issues"/*.md; do
    [ -f "$tk_f" ] || continue
    printf '%s %s\n' "$(num "$(nn_of "$tk_f")")" "$tk_f"
  done | sort -n -k1,1 | cut -d' ' -f2-
}
ticket_file() { # <NN> -> the path, or nothing
  is_num "$1" || return 0
  tickets | while IFS= read -r tk; do
    [ "$(num "$(nn_of "$tk")")" = "$(num "$1")" ] && { printf '%s' "$tk"; break; }
  done
}
blockers() { # <ticket> -> one NN per line
  v=$(tf "$1" 'Blocked by')
  [ "$v" = none ] || printf '%s\n' "$v" | tr ',' '\n' | tr -d ' ' | sed '/^$/d'
}
closed() { case "$(tf "$1" Status)" in resolved|dropped) return 0 ;; esac; return 1; }
unblocked() { # <ticket>
  for ub in $(blockers "$1"); do
    ub_f=$(ticket_file "$ub")
    [ -n "$ub_f" ] && closed "$ub_f" || return 1
  done
}
# what keeps the map from being clear, one line each; nothing when it is clear
remains() {
  tickets | while IFS= read -r rm_f; do
    case "$(tf "$rm_f" Status)" in
      open|claimed) printf '%s %s %s: %s\n' "$(nn_of "$rm_f")" "$(tf "$rm_f" Type)" "$(tf "$rm_f" Status)" "$(title_of "$rm_f")" ;;
    esac
  done
  [ -z "$(section "$mapf" 'Not yet specified')" ] || printf 'Not yet specified still holds text\n'
}

# --- writing -------------------------------------------------------------------------------------------
put_section() { # <file> <heading> <body>
  PS_BODY=$3 awk -v h="## $2" '
    $0 == h { print; print ""; if (ENVIRON["PS_BODY"] != "") { print ENVIRON["PS_BODY"]; print "" } skip = 1; next }
    skip && /^## / { skip = 0 }
    !skip { print }' "$1" > "$1.tmp" && mv -f "$1.tmp" "$1"
}
add_line() { # <file> <heading> <line>
  al_body=$(section "$1" "$2")
  put_section "$1" "$2" "${al_body:+$al_body
}$3"
}
set_tf() { # <ticket> <Field> <value>
  TF_V=$3 awk -v f="$2" '!done && /^## / { done = 1 }
    !done && index($0, f ":") == 1 { print f ": " ENVIRON["TF_V"]; done = 1; next } { print }' "$1" > "$1.tmp" \
    && mv -f "$1.tmp" "$1"
}
set_status() { # <word>
  MS=$1 awk 'FNR == 1 && /^---[ \t]*$/ { fm = 1; print; next } fm && /^---[ \t]*$/ { fm = 0; print; next }
    !fm && !done && /^Status:/ { print "Status: " ENVIRON["MS"]; done = 1; next } { print }' "$mapf" > "$mapf.tmp" \
    && mv -f "$mapf.tmp" "$mapf"
}
# stdin, leading blank lines dropped (the command substitution drops the trailing ones); nothing from a terminal
body_in() { [ -t 0 ] || awk 'NF { s = 1 } s'; }

begin() {
  state_lock "$state" && bl_rc=0 || bl_rc=$?
  case "$bl_rc" in
    0) trap state_unlock EXIT ;;
    1) die2 "another session holds the state lock of $state, waited ${STATE_LOCK_WAIT:-30} s; nothing was written, run it again" ;;
    *) die2 "the state lock could not be taken in $state, is it a git clone?" ;;
  esac
}
# commits the paths (relative to the clone) under the lock begin took; a refused commit puts them back
commit() { # <message> <path>...
  cm_msg=$1; shift
  state_write "$state" "$cm_msg" "$@" && return 0
  for cm_p; do
    if git -C "$state" cat-file -e "HEAD:$cm_p" 2>/dev/null; then git -C "$state" checkout -q HEAD -- "$cm_p" || :
    else git -C "$state" rm -q --cached --ignore-unmatch -- "$cm_p" >/dev/null 2>&1 || :; rm -f "$state/$cm_p"; fi
  done
  die2 "git refused the commit in $state; nothing was written"
}

# --- the request -----------------------------------------------------------------------------------------
if [ "$cmd" = new ]; then
  [ -n "$dest_set" ] && [ -n "$dest" ] || die "new needs --destination <text>"
  if [ -n "$next" ]; then [ -z "$a1" ] || die "new takes <R-id> or --next, not both"
  else valid_rid "$a1" || die "'$a1' is not a request id of the shape R-YYYYMMDD-n"; fi
  begin
  if [ -n "$next" ]; then
    day=$(date +%Y%m%d)
    max=0
    for d in "$state"/requests/R-"$day"-* "$state"/requests/archive/*/R-"$day"-*; do
      [ -e "$d" ] || continue
      k=${d##*-}
      is_num "$k" || continue
      if [ "$(num "$k")" -gt "$max" ]; then max=$(num "$k"); fi
    done
    R="R-$day-$((max + 1))"
  else
    R=$a1
    [ ! -e "$state/requests/$R" ] || die "$R exists already"
    for d in "$state"/requests/archive/*/"$R"; do [ ! -e "$d" ] || die "$R is archived at ${d#"$state"/}"; done
  fi
  mkdir -p "$state/requests/$R"
  printf -- '---\nrequest: %s\ncreated: %s\n---\n\nStatus: charting\n\n## Destination\n\n%s\n\n## Notes\n\n## Decisions so far\n\n## Not yet specified\n\n## Out of scope\n\n## Terms\n' \
    "$R" "$(date +%Y-%m-%d)" "$dest" > "$state/requests/$R/map.md"
  commit "chore($R): map new" "requests/$R/map.md"
  printf '%s\n' "$R"
  exit 0
fi

R=$a1
valid_rid "$R" || die "'$R' is not a request id of the shape R-YYYYMMDD-n; $usage"
rd="$state/requests/$R"
mapf="$rd/map.md"
issues="$rd/issues"
relmap="requests/$R/map.md"
if [ ! -f "$mapf" ]; then
  [ "$cmd" = clear ] && { printf 'map: no map at requests/%s/map.md, so not clear\n' "$R" >&2; exit 1; }
  die "no map at requests/$R/map.md"
fi

# a ticket named by its number, with its path relative to the clone
the_ticket() { # <NN>
  is_num "$1" || die "'$1' is not a ticket number"
  f=$(ticket_file "$1")
  [ -n "$f" ] || die "$R has no ticket $1"
  rel=${f#"$state"/}
  nn=$(nn_of "$f")
  title=$(title_of "$f")
}
# a NN,.. list checked against the tickets that exist, printed normalized as `01, 03`
norm_list() { # <list>
  nl_out=''
  for nl in $(printf '%s' "$1" | tr ',' ' '); do
    is_num "$nl" || die "'$nl' is not a ticket number"
    nl_f=$(ticket_file "$nl")
    [ -n "$nl_f" ] || die "$R has no ticket $nl to be blocked by"
    nl_out="$nl_out$(nn_of "$nl_f")
"
  done
  printf '%s' "$nl_out" | awk 'NF && !seen[$0]++' | sort -n | awk '{ printf "%s%s", (NR > 1 ? ", " : ""), $0 }'
}
# is <to> among the tickets <from> is blocked by, directly or through another ticket
reaches() { # <from NN> <to NN>
  rc_to=$(num "$2") rc_todo=$(num "$1") rc_seen=' '
  while [ -n "$rc_todo" ]; do
    rc_cur=${rc_todo%% *}
    case "$rc_todo" in *' '*) rc_todo=${rc_todo#* } ;; *) rc_todo='' ;; esac
    [ "$rc_cur" != "$rc_to" ] || return 0
    case "$rc_seen" in *" $rc_cur "*) continue ;; esac
    rc_seen="$rc_seen$rc_cur "
    rc_f=$(ticket_file "$rc_cur")
    [ -n "$rc_f" ] || continue
    for rc_b in $(blockers "$rc_f"); do rc_todo="${rc_todo:+$rc_todo }$(num "$rc_b")"; done
  done
  return 1
}

case "$cmd" in
  ticket)
    type=$a2 t=$a3
    case "$type" in research|prototype|grilling|task) ;; *) die "type '$type' is none of research, prototype, grilling, task" ;; esac
    [ -n "$t" ] || die "ticket needs a title; $usage"
    printf '%s' "$repo" | grep -Eq '^[A-Za-z0-9_.-]+$' || die "--repo '$repo' is not a repo key"
    q=$(body_in)
    [ -n "$q" ] || q=$t
    begin
    [ "$(map_status)" != done ] || die "the map of $R is done; a new need is a new request"
    bl=none
    [ -z "$blocked" ] || bl=$(norm_list "$blocked")
    max=0
    for f in $(tickets); do
      k=$(num "$(nn_of "$f")")
      if [ "$k" -gt "$max" ]; then max=$k; fi
    done
    nn=$(printf '%02d' $((max + 1)))
    slug=$(printf '%s' "$t" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-//; s/-$//' | cut -d- -f1-6)
    [ -n "$slug" ] || slug=ticket
    mkdir -p "$issues"
    printf '# %s\n\nType: %s\nStatus: open\nBlocked by: %s\nRepo: %s\nClaimed by: none\n\n## Question\n\n%s\n\n## Answer\n' \
      "$t" "$type" "$bl" "$repo" "$q" > "$issues/$nn-$slug.md"
    commit "chore($R): ticket $nn $t" "requests/$R/issues/$nn-$slug.md"
    printf '%s\n' "$nn" ;;

  wire)
    [ -n "$blocked" ] || die "wire needs --blocked-by NN,..; $usage"
    begin
    the_ticket "$a2"
    case "$(tf "$f" Status)" in open|claimed) ;; *) die "ticket $nn is $(tf "$f" Status); only an open or claimed one is wired" ;; esac
    add=$(norm_list "$blocked")
    for b in $(printf '%s' "$add" | tr ',' ' '); do
      [ "$(num "$b")" != "$(num "$nn")" ] || die "ticket $nn cannot block itself"
      if reaches "$b" "$nn"; then die "ticket $b is already blocked by $nn, directly or through another ticket: a cycle"; fi
    done
    all=$(norm_list "$(blockers "$f" | tr '\n' ,)$add")
    set_tf "$f" 'Blocked by' "$all"
    commit "chore($R): ticket $nn blocked by $all" "$rel"
    printf '%s blocked by %s\n' "$nn" "$all" ;;

  claim)
    [ -n "$by" ] || by=${FACTORY_UNIT:-}
    [ -n "$by" ] || die "claim needs --by <session id>"
    begin
    the_ticket "$a2"
    case "$(tf "$f" Status)" in
      open) ;;
      claimed)
        [ "$(tf "$f" 'Claimed by')" = "$by" ] || die "ticket $nn is claimed by $(tf "$f" 'Claimed by')"
        printf '%s claimed by %s\n' "$nn" "$by"; exit 0 ;;
      *) die "ticket $nn is $(tf "$f" Status)" ;;
    esac
    unblocked "$f" || die "ticket $nn is blocked by $(tf "$f" 'Blocked by'), not all resolved or dropped"
    set_tf "$f" Status claimed
    set_tf "$f" 'Claimed by' "$by"
    commit "chore($R): claim $nn $title" "$rel"
    printf '%s claimed by %s\n' "$nn" "$by" ;;

  resolve|drop)
    text=$(body_in)
    [ -n "$text" ] || die "$cmd reads the $( [ "$cmd" = resolve ] && echo answer || echo reason ) on stdin, and it is empty"
    begin
    the_ticket "$a2"
    s=$(tf "$f" Status)
    holder=$(tf "$f" 'Claimed by')
    if [ "$cmd" = resolve ]; then
      [ "$s" = claimed ] || die "ticket $nn is $s; claim it before you resolve it"
    else
      case "$s" in open|claimed) ;; *) die "ticket $nn is $s" ;; esac
    fi
    [ -z "$by" ] || [ "$s" != claimed ] || [ "$holder" = "$by" ] || die "ticket $nn is claimed by $holder, not $by"
    gist=$(printf '%s\n' "$text" | awk 'NF { print; exit }')
    put_section "$f" Answer "$text"
    if [ "$cmd" = resolve ]; then
      set_tf "$f" Status resolved
      add_line "$mapf" 'Decisions so far' "- [$title](issues/${f##*/}): $gist"
    else
      set_tf "$f" Status dropped
      add_line "$mapf" 'Out of scope' "- [$title](issues/${f##*/}): $gist"
    fi
    commit "chore($R): $cmd $nn $title" "$rel" "$relmap"
    printf '%s %s\n' "$nn" "$( [ "$cmd" = resolve ] && echo resolved || echo dropped )" ;;

  set)
    case "$a2" in
      destination) h=Destination ;;
      notes) h=Notes ;;
      fog) h='Not yet specified' ;;
      terms) h=Terms ;;
      out-of-scope) h='Out of scope' ;;
      *) die "set takes destination, notes, fog, terms or out-of-scope; Decisions so far is written by resolve" ;;
    esac
    text=$(body_in)
    [ "$a2" != destination ] || [ -n "$text" ] || die "a map keeps a destination"
    begin
    [ "$(map_status)" != done ] || die "the map of $R is done"
    put_section "$mapf" "$h" "$text"
    commit "chore($R): map $a2" "$relmap" ;;

  frontier)
    for f in $(tickets); do
      [ "$(tf "$f" Status)" = open ] || continue
      unblocked "$f" || continue
      printf '%s %s %s\n' "$(nn_of "$f")" "$(tf "$f" Type)" "$(title_of "$f")"
    done ;;

  clear)
    left=$(remains)
    [ -n "$left" ] || { printf '%s is clear\n' "$R"; exit 0; }
    printf '%s is not clear:\n%s\n' "$R" "$left"
    exit 1 ;;

  export)
    key=$a2
    [ -n "$key" ] || die "export needs a repo key; $usage"
    # the rows: resolved tickets of this repo or of all, with the ledger's type
    rows='' ids=' '
    for f in $(tickets); do
      [ "$(tf "$f" Status)" = resolved ] || continue
      case "$(tf "$f" Repo)" in "$key"|all) ;; *) continue ;; esac
      ids="$ids$(num "$(nn_of "$f")") "
      rows="$rows$f
"
    done
    printf '# Request map %s, seeded into the grill of %s\n\n' "$R" "$key"
    printf 'Every ledger row below is closed on the request map: carry it into the gap ledger as it stands and never ask\n'
    printf 'it again. The plan-ready frontmatter carries `request: %s` beside `task:`.\n\n' "$R"
    printf '## Destination\n\n%s\n\n' "$(section "$mapf" Destination)"
    printf '## Gap ledger (pre-closed)\n\n| # | type | question | deps | state | answer |\n|---|---|---|---|---|---|\n'
    printf '%s' "$rows" | while IFS= read -r f; do
      [ -n "$f" ] || continue
      case "$(tf "$f" Type)" in grilling) lt=decision ;; prototype) lt=prototype ;; *) lt=research ;; esac
      deps=''
      for b in $(blockers "$f"); do
        case "$ids" in *" $(num "$b") "*) deps="${deps:+$deps, }M$b" ;; esac
      done
      gist=$(section "$f" Answer | awk 'NF { print; exit }')
      printf '| M%s | %s | %s | %s | closed | %s; requests/%s/issues/%s |\n' "$(nn_of "$f")" "$lt" \
        "$(title_of "$f" | sed 's/|/\\|/g')" "${deps:--}" "$(printf '%s' "$gist" | sed 's/|/\\|/g')" "$R" "${f##*/}"
    done
    oos=$(section "$mapf" 'Out of scope') terms=$(section "$mapf" Terms)
    printf '\n## Out of scope\n\n%s\n\n## Terms\n\n%s\n' "${oos:-none}" "${terms:-none}" ;;

  status)
    word=$a2
    case "$word" in charting|grilling|planned|queued|running|done) ;; *) die "status '$word' is none of charting, grilling, planned, queued, running, done" ;; esac
    begin
    cur=$(map_status)
    [ "$cur" != "$word" ] || { printf '%s %s\n' "$R" "$word"; exit 0; }
    [ "$cur" != done ] || die "$R is done, which is final"
    [ "$word" != charting ] || die "charting is where map.sh new starts a map, never a way back"
    case "$word" in
      planned|queued|running|done)
        left=$(remains)
        [ -z "$left" ] || die "$R is not clear, so not $word:
$left" ;;
    esac
    [ "$word" != done ] || [ "$cur" = running ] || die "$R is $cur; done follows running"
    set_status "$word"
    commit "chore($R): map status $word" "$relmap"
    printf '%s %s\n' "$R" "$word" ;;

  *) die "unknown command '$cmd'; $usage" ;;
esac
