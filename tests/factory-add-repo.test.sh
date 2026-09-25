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

# F12: the credentials of an http(s) origin (user:password@ or token@) never reach repos.yml, its history or the
# output; an scp-style origin is written as it is
mkrepo tags
git -C "$tmp/tags" remote set-url origin http://root:glpat-SECRET1@localhost/root/tags.git
out=$(add --repo "$tmp/tags" --yes)
grep -qE '^tags: \{url: "http://localhost/root/tags\.git", ' "$state/repos.yml"; check 'user:password@ is stripped from an http url' $?
mkrepo tok2
git -C "$tmp/tok2" remote set-url origin https://glpat-SECRET2@gitlab.example.com:8443/g/tok2.git
out="$out$(add --repo "$tmp/tok2" --yes)"
grep -qE '^tok2: \{url: "https://gitlab\.example\.com:8443/g/tok2\.git", ' "$state/repos.yml"; check 'token@ is stripped from an https url, the port kept' $?
! grep -q SECRET "$state/repos.yml"; check 'no credential in repos.yml' $?
! git -C "$state" log -p | grep -q SECRET; check 'no credential in the state history' $?
! printf '%s\n' "$out" | grep -q SECRET; check 'no credential in the output' $?
mkrepo scpform
git -C "$tmp/scpform" remote set-url origin git@gitlab.example.com:g/scpform.git
add --repo "$tmp/scpform" --yes >/dev/null
grep -qE '^scpform: \{url: "git@gitlab\.example\.com:g/scpform\.git", ' "$state/repos.yml"; check 'an scp-style url is written as it is' $?

# --- redact_urls (lib-tasks.sh): the userinfo of every scheme URL in a line is cut out ------------------------------
red=$(. "$bin/lib-tasks.sh"; redact_urls "fatal: unable to access 'https://u:tok-SECRET@h.test/g/x.git/' and ssh://git@h.test/y")
[ "$red" = "fatal: unable to access 'https://h.test/g/x.git/' and ssh://h.test/y" ]; check 'redact_urls cuts user:token@ and user@ out of every URL of the line' $?
red=$(. "$bin/lib-tasks.sh"; redact_urls 'git@h.test:g/x.git and https://h.test/a@b')
[ "$red" = 'git@h.test:g/x.git and https://h.test/a@b' ]; check 'redact_urls keeps an scp-style URL and an @ in the path' $?

# --- --clone: clones a URL into the clones: directory of factory.yml, then registers it --------------------------------
# A factory of its own under $tmp/cf, bare origins served over file://, and the status json of the Setup tab under
# $tmp/ui/setup/add-repo/<key>.json (contract C3 of the add-repo design).
cf="$tmp/cf"
cstate="$cf/state"
mkdir -p "$cstate" "$tmp/clones"
clones=$(CDPATH= cd -P -- "$tmp/clones" && pwd)
: > "$cstate/repos.yml"
printf 'clones: %s\n' "$clones" > "$cstate/factory.yml"
git -C "$cstate" init -q
git -C "$cstate" add -A
git -C "$cstate" -c user.name=t -c user.email=t@t commit -q -m init
mkdir -p "$tmp/ui"

mkorigin() { # <key> [<default branch>]: a bare origin at <tmp>/origin/<key>.git with one dotnet commit
  git init -q --bare "$tmp/origin/$1.git"
  git -C "$tmp/origin/$1.git" symbolic-ref HEAD "refs/heads/${2:-main}"
  mkdir -p "$tmp/seed/$1"
  git -C "$tmp/seed/$1" init -q
  : > "$tmp/seed/$1/App.sln"
  git -C "$tmp/seed/$1" add -A
  git -C "$tmp/seed/$1" -c user.name=t -c user.email=t@t commit -q -m init
  git -C "$tmp/seed/$1" push -q "$tmp/origin/$1.git" "HEAD:refs/heads/${2:-main}"
}
cadd() { sh "$bin/factory-add-repo.sh" --root "$cf" "$@" 2>"$tmp/cerr"; }
aj() { cat "$tmp/ui/setup/add-repo/$1.json" 2>/dev/null; }
has() { printf '%s\n' "$1" | grep -qF -- "$2"; }

# the URL guard runs before anything else: a charset with no quote, space or shell character, no leading - (a git
# option), and http, https, ssh, file or the scp form; a refused URL writes no json
for bad in '-uhttps://h.test/g/badurl.git' "https://h.test/g/badurl.git';id" 'https://h.test/g/bad url.git' \
  'ftp://h.test/g/badurl.git' 'h.test/g/badurl.git'; do
  out=$(cadd --clone "$bad"); rc=$?
  [ "$rc" = 1 ] && grep -qF 'is not a URL' "$tmp/cerr"; check "--clone '$bad' is refused with exit 1" $?
done
[ ! -e "$tmp/ui/setup/add-repo/badurl.json" ]; check 'a refused URL writes no json' $?
out=$(cadd --clone "file://$tmp/origin/x.git" --repo "$tmp/fixture"); rc=$?
[ "$rc" = 1 ] && grep -qF 'exclude each other' "$tmp/cerr"; check '--clone and --repo exclude each other' $?

# the clones directory: only clones: of factory.yml, absolute, resolved with cd -P, outside the root
mkorigin nodir
curl_nodir="file://$tmp/origin/nodir.git"
: > "$cstate/factory.yml"
out=$(cadd --clone "$curl_nodir"); rc=$?
[ "$rc" = 1 ] && grep -qF "no clones directory: add clones: <absolute dir> to $cstate/factory.yml" "$tmp/cerr"
check 'no clones: in factory.yml exits 1 with the fix' $?
has "$(aj nodir)" '"state":"failed"' && has "$(aj nodir)" '"detail":"no clones directory: add clones: <absolute dir> to '
check 'the refusal is a failed json with the reason as its detail' $?
printf 'clones: clones\n' > "$cstate/factory.yml"
out=$(cadd --clone "$curl_nodir"); rc=$?
[ "$rc" = 1 ] && grep -qF 'no clones directory' "$tmp/cerr"; check 'a relative clones: exits 1' $?
printf 'clones: %s/missing\n' "$tmp" > "$cstate/factory.yml"
out=$(cadd --clone "$curl_nodir"); rc=$?
[ "$rc" = 1 ] && grep -qF 'no clones directory' "$tmp/cerr"; check 'a clones: that is no directory exits 1' $?
printf 'clones: %s\n' "$cf" > "$cstate/factory.yml"
out=$(cadd --clone "$curl_nodir"); rc=$?
[ "$rc" = 1 ] && grep -qF 'no clones directory' "$tmp/cerr"; check 'clones: equal to the root exits 1' $?
mkdir -p "$cf/sub"
printf 'clones: %s/sub\n' "$cf" > "$cstate/factory.yml"
out=$(cadd --clone "$curl_nodir"); rc=$?
[ "$rc" = 1 ] && grep -qF 'no clones directory' "$tmp/cerr"; check 'clones: under the root exits 1' $?
ln -s "$cf/sub" "$tmp/link"
printf 'clones: %s/link\n' "$tmp" > "$cstate/factory.yml"
out=$(cadd --clone "$curl_nodir"); rc=$?
[ "$rc" = 1 ] && grep -qF 'no clones directory' "$tmp/cerr"; check 'clones: a symlink into the root exits 1' $?
[ -z "$(ls -A "$cf/sub")" ] && [ -z "$(ls -A "$clones")" ]; check 'a refused clones directory is left empty' $?
printf 'clones: %s\n' "$clones" > "$cstate/factory.yml"

# the preview asks the remote (git ls-remote) for its default branch and prints the clone and the registration
mkorigin demo trunk
curl="file://$tmp/origin/demo.git"
out=$(cadd --clone "$curl"); rc=$?
[ "$rc" = 3 ]; check 'a --clone preview exits 3' $?
[ "$(printf '%s\n' "$out" | head -n1)" = demo ]; check 'the first stdout line is the key' $?
has "$out" "+ git clone $curl $clones/demo   (default branch trunk)"; check 'the preview prints the clone line with the remote default branch' $?
has "$out" 'note: alias DEM proposed from the key'; check 'the preview proposes the alias' $?
has "$out" "+ demo: {url: \"$curl\", default_branch: trunk, path: \"$clones/demo\", alias: DEM}   in $cstate/repos.yml"
check 'the preview prints the repos.yml line with the path under the clones directory' $?
has "$out" "+ $cstate/repos/demo/toolset.md   from the stack found after the clone"; check 'the preview names the toolset' $?
[ "$(printf '%s\n' "$out" | tail -n1)" = 'pending - rerun with --yes to apply' ]; check 'the preview ends pending' $?
[ -z "$(ls -A "$clones")" ] && ! grep -q '^demo:' "$cstate/repos.yml"; check 'a preview clones and writes nothing' $?
j=$(aj demo)
has "$j" '"key":"demo"' && has "$j" "\"url\":\"$curl\"" && has "$j" "\"path\":\"$clones/demo\"" \
  && has "$j" '"state":"pending"' && has "$j" "\"detail\":\"$clones/demo\""
check 'the preview writes json pending with the clone target as its detail' $?
printf '%s\n' "$j" | grep -qE '^\{"at":"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z",'; check 'the json at is a UTC ISO time' $?
[ -z "$(find "$tmp/ui/setup/add-repo" -name '*.tmp')" ]; check 'the json temp file is renamed away' $?
out=$(FACTORY_UI_HOME="$tmp/noui" cadd --clone "$curl"); rc=$?
[ "$rc" = 3 ] && [ ! -e "$tmp/noui/setup/add-repo" ]; check 'without a UI home: the same exit, no json' $?

# F3: a remote that cannot be reached exits 4 fast, and the token of the URL reaches no line and no file
start=$(date +%s)
out=$(cadd --clone 'http://u:tok-SECRET@127.0.0.1:9/g/farhost.git'); rc=$?
[ "$rc" = 4 ]; check 'an unreachable URL exits 4' $?
[ $(($(date +%s) - start)) -lt 30 ]; check 'an unreachable URL exits fast' $?
grep -qF 'cannot reach http://127.0.0.1:9/g/farhost.git: ' "$tmp/cerr"; check 'the reason names the URL without its userinfo' $?
grep -qF 'git ls-remote http://127.0.0.1:9/g/farhost.git works in your terminal' "$tmp/cerr"; check 'the fix says to try git ls-remote' $?
j=$(aj farhost)
has "$j" '"state":"failed"' && has "$j" '"url":"http://127.0.0.1:9/g/farhost.git"' && has "$j" '"detail":"cannot reach '
check 'an unreachable URL writes json failed with the reason' $?
! grep -q SECRET "$tmp/cerr" && ! has "$out" SECRET && ! has "$j" SECRET; check 'the token is in no stdout, stderr or json line' $?
[ ! -e "$clones/farhost" ] && [ ! -e "$clones/.farhost.cf-clone" ]; check 'an unreachable URL leaves no directory' $?

# a git that echoes the URL as given, token included, in the lines before its fatal: and a hint after it: the reason
# carries the lines up to the fatal: one, redacted, and not the hint
mkdir -p "$tmp/gitstub"
realgit=$(command -v git)
cat > "$tmp/gitstub/git" <<EOF
#!/bin/sh
case " \$* " in
  *" ls-remote "*)
    printf 'remote: HTTP Basic: Access denied to %s\nfatal: Authentication failed for %s\nhint: see git help credentials\n' "\$4" "\$4" >&2
    exit 128 ;;
esac
exec "$realgit" "\$@"
EOF
chmod +x "$tmp/gitstub/git"
out=$(PATH="$tmp/gitstub:$PATH" cadd --clone 'https://oauth2:glpat-SECRET3@h.test/g/denied.git'); rc=$?
[ "$rc" = 4 ]; check 'an auth failure exits 4' $?
grep -qF "cannot reach https://h.test/g/denied.git: remote: HTTP Basic: Access denied to https://h.test/g/denied.git / fatal: Authentication failed for https://h.test/g/denied.git" "$tmp/cerr"
check 'the reason joins the git lines up to fatal:, each URL redacted' $?
! grep -q 'hint:' "$tmp/cerr"; check 'the reason drops what git prints after fatal:' $?
! grep -q SECRET "$tmp/cerr" && ! has "$(aj denied)" SECRET; check 'the token of an exit 4 git line reaches neither stderr nor the json' $?

exit "$fail"
