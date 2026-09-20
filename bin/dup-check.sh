#!/bin/sh
# Duplicate-code candidates of one diff (T-163): what the added lines repeat of code the repo already has.
# Deterministic and cheap, no model call anywhere in here: it hands the coordinator a short list of pairs to
# ask about, and the asking is done by `worker-explorer` spawns per skills/_shared/delegation.md.
#
#   dup-check.sh <diff-file> <repo-dir>
#
# Two kinds of candidate come out of the added lines (`+`, never `+++`) of the diff:
#
#   * a new function or method signature, in C#, sh, python or typescript, whose **normalized** name (lower
#     case, `_` and `-` removed) already names a definition somewhere else in the repo;
#   * an added run of six or more non-blank lines whose trimmed text appears, in the same order, somewhere
#     else in the repo.
#
# Both searches skip the diff's own files and `.git/`, so a block never matches itself, and both compare text
# trimmed at the ends with runs of blanks squeezed, so indentation alone never hides a copy. Prints one
# candidate per line on stdout, at most 20, whitespace separated:
#
#     <added symbol or block> <existing path:line> <why>
#
# Exit 0 whether or not there are candidates; the empty list is the normal answer. Exit 1 on a bad argument,
# a missing diff file or a repo directory that is not one.
set -eu

die() { printf 'dup-check: %s\n' "$1" >&2; exit 1; }

[ $# -eq 2 ] || die "usage: dup-check.sh <diff-file> <repo-dir>"
diff_file=$1
repo=$2
[ -f "$diff_file" ] || die "the diff file is not a file: $diff_file"
[ -d "$repo" ] || die "the repo directory is not a directory: $repo"

CAP=20
BLOCK_MIN=6

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# the added lines of the diff as `<path> <new line number> <text>`, and the set of files the diff touches
awk '
  /^\+\+\+ / { p = $2; sub(/^b\//, "", p); file = p; next }
  /^@@ / { n = $3; sub(/^\+/, "", n); sub(/,.*$/, "", n); ln = n + 0; next }
  /^\+/ && file != "" { printf "%s %d %s\n", file, ln, substr($0, 2); ln++; next }
  /^-/ { next }
  file != "" { ln++ }
' "$diff_file" > "$tmp/added"
awk '{ print $1 }' "$tmp/added" | sort -u > "$tmp/files"
[ -s "$tmp/added" ] || exit 0

# see: the four signature shapes understood here are the ones the header names
defs_of() { # <file>, prints `<file>:<line>:<name>`
  awk -v f="$1" '
    function emit(n) { if (n != "") printf "%s:%d:%s\n", f, FNR, n }
    /^[ \t]*(def|function)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*/ {
      s = $0; sub(/^[ \t]*(def|function)[ \t]+/, "", s); sub(/[^A-Za-z0-9_$].*$/, "", s); emit(s); next
    }
    /^[ \t]*[A-Za-z_][A-Za-z0-9_-]*[ \t]*\(\)[ \t]*\{/ {
      s = $0; sub(/^[ \t]*/, "", s); sub(/[ \t]*\(\).*$/, "", s); emit(s); next
    }
    /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*(async[ \t]+)?(\(|function)/ {
      s = $0; sub(/^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+/, "", s); sub(/[^A-Za-z0-9_$].*$/, "", s)
      emit(s); next
    }
    /(public|private|protected|internal|static|async|override|virtual|sealed|partial)[ \t]/ &&
    /[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/ {
      s = $0; sub(/\(.*$/, "", s); sub(/^.*[^A-Za-z0-9_]/, "", s)
      if (s ~ /^(if|for|while|switch|catch|return|using|lock)$/) next
      emit(s); next
    }
  ' "$1"
}

norm() { # <name>
  printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '_-'
}

searchable() { # <repo-relative path>
  case "$1" in *.cs|*.sh|*.py|*.ts|*.tsx|*.js|*.md) return 0 ;; esac
  return 1
}

find "$repo" -type f ! -path '*/.git/*' -print | sort > "$tmp/repo-files"
: > "$tmp/repo-defs"
while IFS= read -r f; do
  rel=${f#"$repo"/}
  if grep -qxF -- "$rel" "$tmp/files"; then continue; fi
  if ! searchable "$rel"; then continue; fi
  defs_of "$f" | sed "s|^[^:]*:|$rel:|" >> "$tmp/repo-defs"
done < "$tmp/repo-files"

: > "$tmp/out"
emit() { # <added symbol or block> <path:line> <why>
  [ "$(wc -l < "$tmp/out")" -lt "$CAP" ] || return 0
  printf '%s %s %s\n' "$1" "$2" "$3" >> "$tmp/out"
}

# --- 1. a new signature whose normalized name already names a definition elsewhere ----------------------
while IFS= read -r line; do
  file=${line%% *}; rest=${line#* }
  lno=${rest%% *}; text=${rest#* }
  printf '%s\n' "$text" > "$tmp/one"
  name=$(defs_of "$tmp/one" | head -n1 | sed 's|^.*:[0-9][0-9]*:||')
  [ -n "$name" ] || continue
  want=$(norm "$name")
  [ -n "$want" ] || continue
  while IFS= read -r d; do
    dname=${d##*:}
    [ "$(norm "$dname")" = "$want" ] || continue
    emit "$name" "${d%:*}" "same normalized name, added at $file:$lno"
    break
  done < "$tmp/repo-defs"
done < "$tmp/added"

# --- 2. an added run of BLOCK_MIN or more non-blank lines that exists elsewhere -------------------------
awk -v min="$BLOCK_MIN" '
  { blank = (NF < 3)
    if (blank || $1 != file || $2 != expect) {
      if (count >= min) print file, start, count
      count = 0
    }
    if (blank) { file = ""; next }
    if (count == 0) { file = $1; start = $2 }
    expect = $2 + 1
    count++
  }
  END { if (count >= min) print file, start, count }' "$tmp/added" > "$tmp/runs"

squeeze() { sed 's/^[ \t]*//; s/[ \t]*$//' | tr -s ' \t' ' '; }

# every searchable file of the repo outside the diff, once, trimmed and squeezed, so the window scan below
# reads prepared text instead of re-reading the repo per window
n=0
: > "$tmp/sqmap"
while IFS= read -r f; do
  rel=${f#"$repo"/}
  if grep -qxF -- "$rel" "$tmp/files"; then continue; fi
  if ! searchable "$rel"; then continue; fi
  n=$((n + 1))
  squeeze < "$f" > "$tmp/sq.$n"
  printf '%s %s\n' "$n" "$rel" >> "$tmp/sqmap"
done < "$tmp/repo-files"

# why: a run of added lines is usually longer than the part that was copied, so the whole run almost never
# why: matches; the window of BLOCK_MIN lines slid over the run is what finds the copy
while IFS=' ' read -r rfile rstart rcount; do
  [ -n "${rfile:-}" ] || continue
  awk -v f="$rfile" -v s="$rstart" -v c="$rcount" \
    '$1 == f && $2 >= s && $2 < s + c { t = $3; for (i = 4; i <= NF; i++) t = t " " $i; print t }' \
    "$tmp/added" | squeeze > "$tmp/run"
  w=1
  while [ "$w" -le $((rcount - BLOCK_MIN + 1)) ]; do
    sed -n "$w,$((w + BLOCK_MIN - 1))p" "$tmp/run" > "$tmp/window"
    first=$(head -n1 "$tmp/window")
    found=''
    if [ -n "$first" ]; then
      while IFS=' ' read -r idx rel; do
        hit=$(grep -nxF -- "$first" "$tmp/sq.$idx" | head -n1 | cut -d: -f1 || :)
        [ -n "$hit" ] || continue
        sed -n "$hit,$((hit + BLOCK_MIN - 1))p" "$tmp/sq.$idx" > "$tmp/other"
        cmp -s "$tmp/window" "$tmp/other" || continue
        emit "$rfile:$((rstart + w - 1))+$BLOCK_MIN" "$rel:$hit" "same $BLOCK_MIN trimmed lines"
        found=1
        break
      done < "$tmp/sqmap"
    fi
    [ -z "$found" ] || break
    w=$((w + 1))
  done
done < "$tmp/runs"

head -n "$CAP" "$tmp/out"
exit 0
