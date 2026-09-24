#!/bin/sh
# Duplicate-code candidates of one diff (T-163): what the added lines repeat of code the repo already has.
# Deterministic and cheap, no model call anywhere in here: it hands the coordinator a short list of pairs to
# ask about, and the asking is done by `scout` spawns per skills/_shared/delegation.md.
#
#   dup-check.sh <diff-file> <repo-dir>
#
# Two kinds of candidate come out of the added lines (`+`, never `+++`) of the diff:
#
#   * a new function or method signature, in C#, sh, python or typescript/javascript, whose **normalized**
#     name (lower case, `_` and `-` removed) already names a definition in another file of the same language;
#     one line per added name, however often the diff adds it;
#   * an added run of six or more non-blank lines whose trimmed text appears, in the same order, somewhere
#     else in the repo.
#
# The repo files are the tracked ones (`git ls-files`), never untracked output, never markdown and never the
# diff's own files, so a block never matches itself. Both searches compare text trimmed at the ends with runs
# of blanks squeezed, so indentation alone never hides a copy. The definitions and the windows of the repo are
# indexed in one POSIX awk pass (T-228-04). Prints one candidate per line on stdout, at most 20, whitespace
# separated:
#
#     <added symbol or block> <existing path:line> <why>
#
# Exit 0 whether or not there are candidates; the empty list is the normal answer. Exit 1 on a bad argument,
# a missing diff file or a repo directory that is not a git work tree.
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
[ -s "$tmp/added" ] || exit 0
awk '{ print $1 }' "$tmp/added" | sort -u > "$tmp/files"

git -C "$repo" ls-files > "$tmp/tracked" 2>/dev/null || die "the repo directory is not a git work tree: $repo"

# see: the four signature shapes understood here are the ones the header names
awk -v repo="$repo" -v min="$BLOCK_MIN" -v cap="$CAP" -v files="$tmp/files" -v tracked="$tmp/tracked" '
  function lang(p) {
    if (p ~ /\.cs$/) return "cs"
    if (p ~ /\.sh$/) return "sh"
    if (p ~ /\.py$/) return "py"
    if (p ~ /\.(ts|tsx|js)$/) return "js"
    return ""
  }
  function norm(s) { s = tolower(s); gsub(/[_-]/, "", s); return s }
  function squeeze(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); gsub(/[ \t]+/, " ", s); return s }
  function defname(t,   s) {
    if (t ~ /^[ \t]*(def|function)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*/) {
      s = t; sub(/^[ \t]*(def|function)[ \t]+/, "", s); sub(/[^A-Za-z0-9_$].*$/, "", s); return s
    }
    if (t ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_-]*[ \t]*\(\)[ \t]*\{/) {
      s = t; sub(/^[ \t]*/, "", s); sub(/[ \t]*\(\).*$/, "", s); return s
    }
    if (t ~ /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z_$][A-Za-z0-9_$]*[ \t]*=[ \t]*(async[ \t]+)?(\(|function)/) {
      s = t; sub(/^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+/, "", s); sub(/[^A-Za-z0-9_$].*$/, "", s); return s
    }
    if (t ~ /(public|private|protected|internal|static|async|override|virtual|sealed|partial)[ \t]/ &&
        t ~ /[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/) {
      s = t; sub(/\(.*$/, "", s); sub(/^.*[^A-Za-z0-9_]/, "", s)
      if (s ~ /^(if|for|while|switch|catch|return|using|lock|new|nameof|typeof|sizeof|default|base|this|await|throw|when)$/) return ""
      return s
    }
    return ""
  }
  function saverun(   w, i, key) {
    runs++; rfile[runs] = rf; rstart[runs] = rs; rcount[runs] = cnt
    for (w = 1; w <= cnt - min + 1; w++) {
      key = buf[w]
      for (i = 1; i < min; i++) key = key "\034" buf[w + i]
      rwin[runs, w] = key; wanted[key] = 1
    }
  }
  BEGIN {
    while ((getline f < files) > 0) indiff[f] = 1
    close(files)
  }
  {
    file = $1; lno = $2; t = $0; sub(/^[^ ]* [^ ]* ?/, "", t)
    L = lang(file)
    name = (L == "") ? "" : defname(t)
    k = L SUBSEP norm(name)
    if (name != "" && norm(name) != "" && !(k in want)) {
      want[k] = 1; names++; nname[names] = name; nkey[names] = k; nat[names] = file ":" lno
    }
    blank = (t ~ /^[ \t]*$/)
    if (blank || file != rf || lno != expect) { if (cnt >= min) saverun(); cnt = 0 }
    if (blank) { rf = ""; next }
    if (cnt == 0) { rf = file; rs = lno }
    expect = lno + 1
    buf[++cnt] = squeeze(t)
  }
  END {
    if (cnt >= min) saverun()
    while ((getline p < tracked) > 0) {
      if (p in indiff) continue
      L = lang(p)
      if (L == "") continue
      path = repo "/" p
      n = 0
      while ((getline line < path) > 0) {
        n++
        name = defname(line)
        if (name != "") {
          k = L SUBSEP norm(name)
          if ((k in want) && !(k in found)) found[k] = p ":" n
        }
        for (i = 1; i < min; i++) win[i] = win[i + 1]
        win[min] = squeeze(line)
        if (n < min) continue
        key = win[1]
        for (i = 2; i <= min; i++) key = key "\034" win[i]
        if ((key in wanted) && !(key in wfound)) wfound[key] = p ":" (n - min + 1)
      }
      close(path)
    }
    out = 0
    for (i = 1; i <= names && out < cap; i++)
      if (nkey[i] in found) { print nname[i], found[nkey[i]], "same normalized name, added at " nat[i]; out++ }
    for (r = 1; r <= runs && out < cap; r++)
      for (w = 1; w <= rcount[r] - min + 1; w++)
        if ((r, w) in rwin && rwin[r, w] in wfound) {
          print rfile[r] ":" (rstart[r] + w - 1) "+" min, wfound[rwin[r, w]], "same " min " trimmed lines"
          out++
          break
        }
  }
' "$tmp/added"
exit 0
