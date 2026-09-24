#!/bin/sh
# factory-add-repo.sh seeds a dotnet repo's toolset from toolsets/dotnet.md. block-verify.sh and block-merge.sh
# split a row on `|`, strip the backquotes of the binding cell and eval the rest, so every binding cell must be
# exactly one backquoted command with nothing around it and no `|` inside.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

state="$tmp/state"
mkdir -p "$state"
: > "$state/repos.yml"
git -C "$state" init -q
git -C "$state" add -A
git -C "$state" -c user.name=t -c user.email=t@t commit -q -m init

git init -q --bare "$tmp/origin/fixture.git"
repo="$tmp/fixture"
mkdir -p "$repo"
git -C "$repo" init -q
: > "$repo/App.sln"
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m init
git -C "$repo" remote add origin "$tmp/origin/fixture.git"

sh "$bin/factory-add-repo.sh" --root "$tmp" --repo "$repo" --yes >/dev/null 2>"$tmp/err"
check 'add-repo seeds the fixture dotnet repo' $?
[ -s "$tmp/err" ] && cat "$tmp/err"

toolset="$state/repos/fixture/toolset.md"
[ -f "$toolset" ]; check 'the toolset is written' $?

rows=$(grep '^|' "$toolset" | grep -v '^| command | binding |$' | grep -v '^|---|---|$')
[ -n "$rows" ]; check 'the toolset has binding rows' $?
bad=$(printf '%s\n' "$rows" | grep -v '^| `[^`]*` | `[^`|]*` |$')
[ -z "$bad" ]; check 'every binding cell is one backquoted span with nothing around it and no |' $?
[ -n "$bad" ] && printf '  %s\n' "$bad"

tf=$(printf '%s\n' "$rows" | grep '^| `test-filter ')
printf '%s\n' "$tf" | grep -qF -- '--filter "<expr>"'; check 'test-filter holds --filter "<expr>"' $?
! printf '%s\n' "$tf" | grep -qF -- '--filter-query'; check 'test-filter holds no --filter-query' $?

! grep -qF '{{solution}}' "$toolset"; check 'no {{solution}} is left' $?
grep -qF 'dotnet build App.sln ' "$toolset"; check 'the solution is filled in' $?

exit "$fail"
