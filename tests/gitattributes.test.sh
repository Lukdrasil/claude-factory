#!/bin/sh
# Git for Windows checks text out with CRLF under core.autocrlf=true, and `sh` then fails on `$'\r'`.
# `.gitattributes` pins every text file to LF, and no file is committed with CRLF in the index.
set -u
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

[ "$(git -C "$repo" check-attr eol -- bin/task-new.sh)" = 'bin/task-new.sh: eol: lf' ]
check 'bin/task-new.sh checks out with eol=lf' $?

crlf=$(git -C "$repo" ls-files --eol | grep 'i/crlf')
[ -z "$crlf" ]; check 'no file is stored with CRLF in the index' $?
[ -n "$crlf" ] && printf '%s\n' "$crlf"

exit "$fail"
