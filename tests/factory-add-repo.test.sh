#!/bin/sh
# factory-add-repo.sh seeds a dotnet repo's toolset from toolsets/dotnet.md. block-verify.sh and block-merge.sh
# split a row on `|`, strip the backquotes of the binding cell and eval the rest, so every binding cell must be
# exactly one backquoted command with nothing around it and no `|` inside. The repos.yml line carries an alias:
# proposed from the first letters of the key (2 to 4 uppercase, unique), or --alias; the diff shows it.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset WORK_DIR
# add-repo refreshes doctor.json: into the scratch UI home, and over stubs instead of the real herdr, forges, Claude
export FACTORY_UI_HOME="$tmp/ui"
mkdir -p "$tmp/stub"
for t in herdr gh glab claude; do printf '#!/bin/sh\nexit 1\n' > "$tmp/stub/$t"; chmod +x "$tmp/stub/$t"; done
PATH="$tmp/stub:$PATH"
export PATH

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

# --- the alias ------------------------------------------------------------------------------------------------------
grep -qE '^fixture: \{.*, alias: FIX[,}]' "$state/repos.yml"; check 'the registered line carries the proposed alias FIX' $?

mkrepo() { # <key>: a dotnet clone whose origin is <tmp>/origin/<key>.git
  git init -q --bare "$tmp/origin/$1.git"
  mkdir -p "$tmp/$1"
  git -C "$tmp/$1" init -q
  : > "$tmp/$1/App.sln"
  git -C "$tmp/$1" add -A
  git -C "$tmp/$1" -c user.name=t -c user.email=t@t commit -q -m init
  git -C "$tmp/$1" remote add origin "$tmp/origin/$1.git"
}
add() { sh "$bin/factory-add-repo.sh" --root "$tmp" "$@" 2>&1; }

mkrepo expiriocredentialservice
out=$(add --repo "$tmp/expiriocredentialservice"); rc=$?
[ "$rc" = 3 ]; check 'a preview exits 3' $?
printf '%s\n' "$out" | grep -qE '^\+ expiriocredentialservice: \{.*, alias: EXP[,}]'; check 'the diff shows the alias EXP, the first letters of the key' $?
! grep -q expiriocredentialservice "$state/repos.yml"; check 'a preview writes nothing' $?
add --repo "$tmp/expiriocredentialservice" --yes >/dev/null
grep -qE '^expiriocredentialservice: \{.*, alias: EXP[,}]' "$state/repos.yml"; check '--yes writes the alias EXP' $?

mkrepo expiriointegrations
out=$(add --repo "$tmp/expiriointegrations")
printf '%s\n' "$out" | grep -qE '^\+ expiriointegrations: \{.*, alias: EXI[,}]'; check 'EXP is taken, so expiriointegrations gets EXI' $?

mkrepo fixtures
out=$(add --repo "$tmp/fixtures")
printf '%s\n' "$out" | grep -qE '^\+ fixtures: \{.*, alias: FIT[,}]'; check 'FIX is taken, so fixtures gets FIT' $?

mkrepo claude-factory
out=$(add --repo "$tmp/claude-factory")
printf '%s\n' "$out" | grep -qE '^\+ claude-factory: \{.*, alias: CF[,}]'; check 'a key of two words gets their initials CF' $?
out=$(add --repo "$tmp/claude-factory" --alias ZZ)
printf '%s\n' "$out" | grep -qE '^\+ claude-factory: \{.*, alias: ZZ[,}]'; check '--alias ZZ overrides the proposal' $?
out=$(add --repo "$tmp/claude-factory" --alias zz); rc=$?
[ "$rc" = 1 ]; check '--alias zz is refused (2 to 4 uppercase letters)' $?
out=$(add --repo "$tmp/claude-factory" --alias ABCDE); rc=$?
[ "$rc" = 1 ]; check '--alias ABCDE is refused' $?
out=$(add --repo "$tmp/claude-factory" --alias EXP); rc=$?
[ "$rc" = 1 ]; check '--alias EXP is refused, expiriocredentialservice has it' $?
printf '%s\n' "$out" | grep -q expiriocredentialservice; check 'the refusal names the repo that has it' $?

# a repo registered before aliases gets one added to its line
mkrepo legacy
printf 'legacy: {url: "%s", default_branch: main, path: "%s"}\n' "$tmp/origin/legacy.git" "$tmp/legacy" >> "$state/repos.yml"
git -C "$state" -c user.name=t -c user.email=t@t commit -qam 'legacy registered'
out=$(add --repo "$tmp/legacy"); rc=$?
[ "$rc" = 3 ]; check 'a registered repo without an alias is pending' $?
printf '%s\n' "$out" | grep -qE '^- legacy: \{url: .*path: "[^"]*"\}'; check 'the diff shows the old line' $?
printf '%s\n' "$out" | grep -qE '^\+ legacy: \{url: .*path: "[^"]*", alias: LEG\}'; check 'the diff shows the line with the alias LEG' $?
add --repo "$tmp/legacy" --yes >/dev/null
grep -qxF "legacy: {url: \"$tmp/origin/legacy.git\", default_branch: main, path: \"$tmp/legacy\", alias: LEG}" "$state/repos.yml"
check '--yes adds the alias to that line and keeps the rest' $?
git -C "$state" log --format=%s | grep -qx 'chore(legacy): alias LEG'; check 'the alias is its own commit' $?
out=$(add --repo "$tmp/legacy"); rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^nothing to do'; check 'a rerun has nothing to do' $?
out=$(add --repo "$tmp/legacy" --alias LGC); rc=$?
[ "$rc" = 1 ]; check '--alias over a registered alias is refused' $?

exit "$fail"
