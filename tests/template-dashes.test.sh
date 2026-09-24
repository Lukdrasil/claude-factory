#!/bin/sh
# dash-gate denies an added line carrying U+2014 or U+2013, so a fenced template under skills/ or agents/ that
# holds one is a line a session is told to write and then refused. No fenced block there may hold either
# dash. The scanner is first run over a fixture, so a scanner that sees no fence at all cannot pass vacuously.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

em=$(printf '\342\200\224')
en=$(printf '\342\200\223')

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

# invariant: a fence opens on a line of three or more backticks or tildes, indented or not, and closes on a
# invariant: line of the same character at least as long, so a ``` inside a ```` block does not close it
fenced_dashes() { # <file>...
  awk -v em="$em" -v en="$en" '
    FNR == 1 { ch = ""; len = 0 }
    {
      line = $0
      sub(/^[ \t]+/, "", line)
      c = substr(line, 1, 1)
      if (c == "`" || c == "~") {
        n = 0
        while (substr(line, n + 1, 1) == c) n++
        rest = substr(line, n + 1)
        if (ch == "" && n >= 3) { ch = c; len = n; next }
        if (ch == c && n >= len && rest ~ /^[ \t]*$/) { ch = ""; len = 0; next }
      }
      if (ch != "" && (index($0, em) || index($0, en))) print FILENAME ":" FNR ": " $0
    }
  ' "$@"
}

fixture="$tmp/fixture.md"
{
  printf 'prose with an em dash %s is not fenced\n' "$em"
  printf '````markdown\n'
  printf '```sh\n'
  printf 'inner %s em\n' "$em"
  printf '```\n'
  printf 'outer %s en, still inside the four-backtick fence\n' "$en"
  printf '````\n'
  printf 'after %s the fence\n' "$em"
  printf '   ~~~\n'
  printf '   indented %s tilde fence\n' "$en"
  printf '   ~~~\n'
} > "$fixture"
hits=$(fenced_dashes "$fixture")
printf '%s\n' "$hits" | grep -q ':4: inner'; check 'the scanner sees an em dash in a nested fence' $?
printf '%s\n' "$hits" | grep -q ':6: outer'; check 'a shorter fence line does not close a longer fence' $?
printf '%s\n' "$hits" | grep -q ':10: '; check 'the scanner sees an en dash in an indented tilde fence' $?
[ "$(printf '%s\n' "$hits" | grep -c .)" = 3 ]; check 'a dash outside a fence is not reported' $?

files=$(find "$root/skills" "$root/agents" -type f \( -name '*.md' -o -name '*.md.template' \) | sort)
[ -n "$files" ]; check 'skills/ and agents/ hold markdown to scan' $?
# shellcheck disable=SC2086
found=$(fenced_dashes $files | sed "s|^$root/||")
if [ -n "$found" ]; then
  printf '%s\n' "$found"
  printf 'FAIL no fenced block under skills/ or agents/ holds U+2014 or U+2013 (%s lines)\n' \
    "$(printf '%s\n' "$found" | grep -c .)"
  fail=1
else
  printf 'PASS no fenced block under skills/ or agents/ holds U+2014 or U+2013\n'
fi

exit $fail
