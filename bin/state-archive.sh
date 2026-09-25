#!/bin/sh
# Finished work out of the hot globs: a parent that is done or closed, whose blocks are all done or closed and on
# which no open task depends (neither on it nor on one of its blocks) moves with its blocks, their progress files
# and their verdicts to repos/<key>/archive/<YYYY-MM>/{tasks,progress,verdicts}/, one `git mv` commit per parent
# under the state lock. Only a whole parent moves, never a lone block. A request whose map.md says `Status: done`
# under the frontmatter moves to requests/archive/<YYYY-MM>/<R-id>/ the same way, with --all, once no live task
# carries `request: <R-id>` any more.
#
#   state-archive.sh <T-id>|--all [--dry-run] [--state <dir>]
#
# <YYYY-MM> is the month of the last commit of the parent's task file (of the request's folder), which for a
# finished parent is the commit that made it done or closed: task-done.sh archives in the month it closes, and
# the one-off --all over an old state files each parent under the month it finished. The verdicts are the ones
# named by the id (`<T-id>.md`, `<T-id>-*.md`) and the verdict of the plan the parent names
# (`plans/<slug>-plan-ready.md`) unless an open task outside the family names that plan too. The plan stays.
# A family with an uncommitted or untracked file is left alone: another session is writing it.
# task-done.sh runs this for the parent it closes; --all is the sweep (M1 once, then whoever wants it).
#
# Exit 0 = archived, already archived, printed (--dry-run), or --all went through whatever it found;
# 1 = refused, the reason is on stderr and nothing moved; 2 = the lock or the commit failed, nothing committed.
set -eu

target='' all=0 dry=0 state=''
die() { printf 'state-archive: %s\n' "$1" >&2; exit 1; }
die2() { printf 'state-archive: %s\n' "$1" >&2; exit 2; }
usage='usage: state-archive.sh <T-id>|--all [--dry-run] [--state <dir>]'

while [ $# -gt 0 ]; do
  case "$1" in
    --all) all=1; shift ;;
    --dry-run) dry=1; shift ;;
    --state) [ $# -ge 2 ] || die "--state needs a value"; state=$2; shift 2 ;;
    -*) die "unknown argument '$1'; $usage" ;;
    *) [ -z "$target" ] || die "one task id at a time; $usage"; target=$1; shift ;;
  esac
done
{ [ -n "$target" ] && [ "$all" = 0 ]; } || { [ -z "$target" ] && [ "$all" = 1 ]; } || die "$usage"

. "$(dirname -- "$0")/lib-tasks.sh"

[ -n "$state" ] || state=$(resolve_state_dir "$PWD")
state=$(git -C "$state" rev-parse --show-toplevel 2>/dev/null) || die "$state is not a state clone, pass --state <dir>"

if [ -n "$target" ]; then
  is_task_id "$target" || die "'$target' is not a task id"
  ! is_block_id "$target" || die "$target is a block; a block is archived with its parent, name the parent"
fi

# One line per parent over every live task file: `ok <P> <key> <ids> <files> <verdict slug or ->` when it may
# move, `no <P> <reason>` when it is finished and something keeps it (for --all) or it is the one asked for,
# fields split by a tab. A block is an id whose last `-<digits>` (two or more) leaves the id of a task in the
# same key; `depends_on` is read in the inline `[a, b]` and the list spelling.
families() { # [<parent id>]
  fa_want=${1:-}
  set -- "$state"/repos/*/tasks/*.md
  [ -e "$1" ] || return 0
  awk -v want="$fa_want" -v st="$state/" '
    function val(s) { sub(/^[^:]*:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); sub(/[ \t]+$/, "", s); return s }
    function done_(s) { return s == "done" || s == "closed" }
    function adddeps(s,   k, a, i) {
      gsub(/[][ \t"'"'"']/, "", s)
      k = split(s, a, ",")
      for (i = 1; i <= k; i++) if (a[i] != "") deps[n] = deps[n] " " a[i]
    }
    FNR == 1 {
      n++; file[n] = substr(FILENAME, length(st) + 1); fm = ($0 ~ /^---[ \t]*$/) ? 1 : 2; inlist = 0
      split(file[n], seg, "/"); key[n] = seg[2]
      next
    }
    fm == 1 && /^---[ \t]*$/ { fm = 2; next }
    fm == 1 {
      if (/^id:/) id[n] = val($0)
      else if (/^status:/) status[n] = val($0)
      else if (/^depends_on:/) { v = val($0); adddeps(v); inlist = (v == ""); next }
      else if (inlist && /^[ \t]*-/) { v = $0; sub(/^[ \t]*-[ \t]*/, "", v); sub(/[ \t]+#.*$/, "", v); adddeps(v); next }
      if (!/^[ \t]/) inlist = 0
      next
    }
    slug[n] == "" && match($0, /plans\/[A-Za-z0-9_.-]+-plan-ready\.md/) {
      s = substr($0, RSTART + 6, RLENGTH - 6); sub(/-plan-ready\.md$/, "", s); slug[n] = s
    }
    END {
      for (i = 1; i <= n; i++) if (id[i] != "") { known[key[i] SUBSEP id[i]] = 1 }
      for (i = 1; i <= n; i++) {
        if (id[i] == "") continue
        par[i] = ""
        if (match(id[i], /-[^-]*$/)) {
          sfx = substr(id[i], RSTART + 1); pre = substr(id[i], 1, RSTART - 1)
          if (length(sfx) >= 2 && sfx !~ /[^0-9]/ && ((key[i] SUBSEP pre) in known)) par[i] = pre
        }
        top = (par[i] == "") ? id[i] : par[i]
        fam[top] = fam[top] " " i
        if (!done_(status[i])) {
          k = split(deps[i], a, " ")
          for (j = 1; j <= k; j++) if (!((a[j] SUBSEP id[i]) in seen)) {
            seen[a[j] SUBSEP id[i]] = 1
            dep[a[j]] = dep[a[j]] (dep[a[j]] == "" ? "" : ", ") id[i] " (" status[i] ")"
          }
          if (slug[i] != "") openplan[slug[i]] = 1
        }
      }
      found = 0
      for (i = 1; i <= n; i++) {
        if (id[i] == "" || par[i] != "") continue
        if (want != "" && id[i] != want) continue
        if (want == "" && !done_(status[i])) continue
        if (want != "") { if (found) continue; found = 1 }
        P = id[i]; why = ""; ids = ""; files = ""
        k = split(fam[P], m, " ")
        for (j = 1; j <= k; j++) {
          x = m[j]
          if (index(" " ids " ", " " id[x] " ") == 0) ids = ids (ids == "" ? "" : " ") id[x]
          # the parent file first: its last commit dates the archive month
          files = (x == i) ? file[x] (files == "" ? "" : " ") files : files (files == "" ? "" : " ") file[x]
          if (why != "") continue
          if (!done_(status[x])) {
            why = (x == i) ? P " is " status[x] ", not done or closed" : "its block " id[x] " is " status[x] ", not done or closed"
          } else if (id[x] in dep) {
            why = "the open " dep[id[x]] " depends on " id[x]
          }
        }
        if (why != "") { print "no\t" P "\t" why; continue }
        # an open task naming the plan is outside this family, or the family would not be finished
        s = slug[i]
        if (s != "" && (s in openplan)) s = ""
        print "ok\t" P "\t" key[i] "\t" ids "\t" files "\t" (s == "" ? "-" : s)
      }
    }' "$@"
}

# the moves of one `ok` line: `<src> <dst>` per line, paths relative to the clone, the destination month read off
# the last commit of the parent's task file
moves_of() { # <P> <key> <ids> <files> <slug>
  mo_first=${4%% *}
  mo_month=$(git -C "$state" log -1 --format=%cd --date=format:%Y-%m -- "$mo_first" 2>/dev/null || :)
  [ -n "$mo_month" ] || mo_month=$(date +%Y-%m)
  mo_dest="repos/$2/archive/$mo_month"
  for mo_f in $4; do printf '%s %s\n' "$mo_f" "$mo_dest/tasks/${mo_f##*/}"; done
  for mo_i in $3; do
    [ ! -f "$state/repos/$2/progress/$mo_i.md" ] || printf '%s %s\n' "repos/$2/progress/$mo_i.md" "$mo_dest/progress/$mo_i.md"
  done
  for mo_v in "$state/repos/$2/verdicts/$1.md" "$state/repos/$2/verdicts/$1"-*.md "$state/repos/$2/verdicts/$5.md"; do
    [ -f "$mo_v" ] || continue
    mo_v=${mo_v#"$state/"}
    printf '%s %s\n' "$mo_v" "$mo_dest/verdicts/${mo_v##*/}"
  done | sort -u
}

# the moves of one request folder
request_moves() { # <R-id>
  rq_month=$(git -C "$state" log -1 --format=%cd --date=format:%Y-%m -- "requests/$1" 2>/dev/null || :)
  [ -n "$rq_month" ] || rq_month=$(date +%Y-%m)
  printf '%s %s\n' "requests/$1" "requests/archive/$rq_month/$1"
}

# `git mv` each line of <moves> and commit them all in one commit; the caller holds the state lock. A family with
# an uncommitted or untracked file, or a destination that is already there, is refused with the reason on stdout
# (return 1); a git failure puts back what already moved (return 2). State paths carry no blanks, so the lists
# are split on them.
apply() { # <name> <moves> <message>
  ap_name=$1 ap_msg=$3
  set -f
  ap_src=$(printf '%s\n' "$2" | cut -d' ' -f1 | tr '\n' ' ')
  ap_dst=$(printf '%s\n' "$2" | cut -d' ' -f2 | tr '\n' ' ')
  # shellcheck disable=SC2086
  ap_dirty=$(git -C "$state" status --porcelain -- $ap_src)
  if [ -n "$ap_dirty" ]; then
    set +f
    printf '%s has uncommitted or untracked files: %s' "$ap_name" "$(printf '%s\n' "$ap_dirty" | cut -c4- | tr '\n' ' ')"
    return 1
  fi
  for ap_d in $ap_dst; do
    [ ! -e "$state/$ap_d" ] || { set +f; printf '%s would overwrite %s' "$ap_name" "$ap_d"; return 1; }
  done
  ap_done=''
  # shellcheck disable=SC2086
  set -- $ap_dst
  for ap_s in $ap_src; do
    mkdir -p "$state/${1%/*}"
    git -C "$state" mv -- "$ap_s" "$1" >/dev/null 2>&1 || { undo "$ap_done"; set +f; printf 'git mv refused %s' "$ap_s"; return 2; }
    ap_done="$1 $ap_s $ap_done"
    shift
  done
  if [ -n "$(git -C "$state" config user.email || :)" ]; then set -- git -C "$state"
  else set -- git -C "$state" -c user.name=harness -c user.email=harness@localhost; fi
  # shellcheck disable=SC2086
  "$@" commit -q -m "$ap_msg" -- $ap_src $ap_dst >/dev/null 2>&1 \
    || { undo "$ap_done"; set +f; printf 'git refused the commit of %s' "$ap_name"; return 2; }
  set +f
}
undo() { # <dst src pairs>
  # shellcheck disable=SC2086
  set -- $1
  while [ $# -ge 2 ]; do git -C "$state" mv -- "$1" "$2" >/dev/null 2>&1 || :; shift 2; done
}

# one parent, checked again under the lock, then moved: prints the moves, and returns 0 (moved), 1 (refused,
# the reason on stdout) or 2 (the lock or git failed)
archive_one() { # <P>
  state_lock "$state" && ao_rc=0 || ao_rc=$?
  case "$ao_rc" in
    0) ;;
    1) printf 'another session holds the state lock of %s, waited %s s; nothing moved' "$state" "${STATE_LOCK_WAIT:-30}"; return 2 ;;
    *) printf 'the state lock could not be taken in %s' "$state"; return 2 ;;
  esac
  ao_line=$(families "$1")
  case "$ao_line" in
    ok*) ;;
    no*) state_unlock; printf '%s' "$(printf '%s' "$ao_line" | cut -f3)"; return 1 ;;
    *) state_unlock; printf 'no live task file with id: %s' "$1"; return 1 ;;
  esac
  ao_moves=$(moves_of "$1" "$(printf '%s' "$ao_line" | cut -f3)" "$(printf '%s' "$ao_line" | cut -f4)" \
    "$(printf '%s' "$ao_line" | cut -f5)" "$(printf '%s' "$ao_line" | cut -f6)")
  ao_dest=$(printf '%s\n' "$ao_moves" | head -n1 | cut -d' ' -f2); ao_dest=${ao_dest%/tasks/*}
  ao_why=$(apply "$1" "$ao_moves" "chore($1): archive with its blocks to $ao_dest") && ao_rc=0 || ao_rc=$?
  state_unlock
  [ "$ao_rc" = 0 ] || { printf '%s' "$ao_why"; return "$ao_rc"; }
  printf '%s\n' "$ao_moves" | sed 's/ / -> /'
}

requests_done() { # -> the ids of the requests whose map says Status: done
  set -- "$state"/requests/*/map.md
  [ -e "$1" ] || return 0
  for rd_m in "$@"; do
    rd_s=$(awk 'FNR == 1 && /^---[ \t]*$/ { fm = 1; next } fm && /^---[ \t]*$/ { fm = 0; next }
      !fm && /^Status:/ { sub(/^Status:[ \t]*/, ""); sub(/[ \t]+$/, ""); print; exit }' "$rd_m")
    [ "$rd_s" != done ] || { rd_r=${rd_m%/map.md}; printf '%s\n' "${rd_r##*/}"; }
  done
}

# the live tasks that still carry `request: <R-id>`, one id per line: a done request waits for them, or the
# archived request and a live parent of it would coexist
request_holders() { # <R-id>
  task_files | while IFS= read -r rh_f; do
    grep -qx "request:[[:space:]]*$1[[:space:]]*" "$rh_f" 2>/dev/null || continue
    sed -n 's/^id:[[:space:]]*//p' "$rh_f" | head -n1
  done
}

if [ -n "$target" ]; then
  line=$(families "$target")
  case "$line" in
    '')
      case "$(task_of "$target")" in
        */archive/*) printf 'state-archive: %s is already archived\n' "$target"; exit 0 ;;
      esac
      die "no task file with 'id: $target' in $state/repos/*/tasks/" ;;
    no*) die "$target stays live: $(printf '%s' "$line" | cut -f3)" ;;
  esac
  if [ "$dry" = 1 ]; then
    moves_of "$target" "$(printf '%s' "$line" | cut -f3)" "$(printf '%s' "$line" | cut -f4)" \
      "$(printf '%s' "$line" | cut -f5)" "$(printf '%s' "$line" | cut -f6)" | sed 's/ / -> /'
    exit 0
  fi
  out=$(archive_one "$target") && rc=0 || rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" ;;
    1) die "$target stays live: $out" ;;
    *) die2 "$out" ;;
  esac
  exit 0
fi

# --all: every finished parent, then every done request; one that cannot move is a `skipped:` line and the sweep
# goes on
families | while IFS= read -r line; do
  P=$(printf '%s' "$line" | cut -f2)
  case "$line" in
    no*) printf 'skipped: %s %s\n' "$P" "$(printf '%s' "$line" | cut -f3)"; continue ;;
  esac
  if [ "$dry" = 1 ]; then
    moves_of "$P" "$(printf '%s' "$line" | cut -f3)" "$(printf '%s' "$line" | cut -f4)" \
      "$(printf '%s' "$line" | cut -f5)" "$(printf '%s' "$line" | cut -f6)" | sed 's/ / -> /'
    continue
  fi
  out=$(archive_one "$P") && rc=0 || rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" ;;
    1) printf 'skipped: %s %s\n' "$P" "$out" ;;
    *) printf 'state-archive: %s\n' "$out" >&2; exit 2 ;;
  esac
done || exit 2

for R in $(requests_done); do
  moves=$(request_moves "$R")
  live=$(request_holders "$R" | tr '\n' ' ' | sed 's/ $//')
  if [ -n "$live" ]; then printf 'skipped: %s the live %s still carries request: %s\n' "$R" "$live" "$R"; continue; fi
  if [ "$dry" = 1 ]; then printf '%s\n' "$moves" | sed 's/ / -> /'; continue; fi
  state_lock "$state" && rc=0 || rc=$?
  [ "$rc" = 0 ] || die2 "another session holds the state lock of $state; $R was not archived"
  # again under the lock: a parent may have been written since
  live=$(request_holders "$R" | tr '\n' ' ' | sed 's/ $//')
  if [ -n "$live" ]; then
    state_unlock; printf 'skipped: %s the live %s still carries request: %s\n' "$R" "$live" "$R"; continue
  fi
  why=$(apply "$R" "$moves" "chore($R): archive to ${moves#* }") && rc=0 || rc=$?
  state_unlock
  case "$rc" in
    0) printf '%s\n' "$moves" | sed 's/ / -> /' ;;
    1) printf 'skipped: %s %s\n' "$R" "$why" ;;
    *) die2 "$why" ;;
  esac
done
exit 0
