#!/bin/sh
# issue-create.sh: the one script that creates an issue, always with the ai-drafted label. It resolves the clone
# of a repo-key from repos.yml, takes host and owner/repo from its origin, and runs gh for github.com (the label
# ensured first, its failure ignored) and glab for every other host. gh and glab are stubs on PATH that log
# every argument in brackets and the body file they were handed.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
fail=0
state=$tmp/work/state
log=$tmp/forge.log
mkdir -p "$tmp/bin" "$state/repos" "$tmp/clones"

for tool in gh glab; do
  cat > "$tmp/bin/$tool" <<EOF
#!/bin/sh
{ printf '$tool'; for a in "\$@"; do printf ' [%s]' "\$a"; done; printf '\n'; } >> "\$STUB_LOG"
prev=''
for a in "\$@"; do
  case "\$prev" in --body-file|--description-file) printf 'body %s\n' "\$(cat "\$a" 2>/dev/null || echo UNREADABLE)" >> "\$STUB_LOG" ;; esac
  prev=\$a
done
case "\$1 \$2" in
  'label create') [ -z "\${GH_LABEL_FAIL:-}" ] || { echo 'label "ai-drafted" already exists' >&2; exit 1; } ;;
  'issue create') echo 'https://forge.test/issues/7' ;;
esac
exit 0
EOF
  chmod +x "$tmp/bin/$tool"
done

clone() { # <key> <origin url or empty>
  git init -q "$tmp/clones/$1"
  [ -z "$2" ] || git -C "$tmp/clones/$1" remote add origin "$2"
  printf '%s: {url: "%s", default_branch: main, path: "%s"}\n' "$1" "${2:-https://forge.test/x.git}" "$tmp/clones/$1" >> "$state/repos.yml"
}
clone ghhttps https://github.com/acme/widgets
clone ghscp git@github.com:acme/widgets.git
clone glhttps https://gitlab.example.com/group/sub/widgets.git
clone glscp git@gitlab.example.com:group/widgets.git
clone glsshport ssh://git@gitlab.example.com:2222/g/r.git
clone glhttpsport https://gitlab.example.com:8443/g/r
clone glhttpport http://localhost:8929/g/r.git
clone noorigin ''
printf 'noclone: {url: "https://github.com/acme/gone.git", default_branch: main, path: "%s"}\n' "$tmp/clones/gone" >> "$state/repos.yml"

printf 'The export stops at the first empty row.\n' > "$tmp/body.md"
title='fix: export fails on empty rows'

run() { # <args...>: issue-create.sh with the stubs on PATH; exit code in $got, stdout in $tmp/out
  : > "$log"
  PATH="$tmp/bin:$PATH" STUB_LOG=$log sh "$root/bin/issue-create.sh" "$@" >"$tmp/out" 2>"$tmp/err"
  got=$?
}
ok() { printf 'PASS %s\n' "$1"; }
no() { printf 'FAIL %s: %s\n' "$1" "$2"; fail=1; }
has() { grep -qF -- "$2" "$1"; }
line() { awk -v p="$1" 'index($0, p) == 1 { print; exit }' "$log"; }
want_line() { # <label> <line prefix> <fragment>...
  l=$1 p=$2; shift 2
  ln=$(line "$p")
  [ -n "$ln" ] || { no "$l" "no '$p' call in $(tr '\n' ';' < "$log")"; return; }
  for f in "$@"; do
    case "$ln" in *"$f"*) ;; *) no "$l" "'$f' missing from: $ln"; return ;; esac
  done
  ok "$l"
}
want_exit() { if [ "$got" -eq "$2" ]; then ok "$1"; else no "$1" "want exit $2, got $got: $(head -c 200 "$tmp/err")"; fi; }
want_no_forge() { if [ -s "$log" ]; then no "$1" "a forge was called: $(tr '\n' ';' < "$log")"; else ok "$1"; fi; }

# github.com over https: the label first, then the issue with -R, the body file and the label
run ghhttps --title "$title" --body-file "$tmp/body.md" --state "$state"
want_exit 'github https: exit 0' 0
want_line 'github https: gh label create ai-drafted' 'gh [label] [create]' \
  '[ai-drafted]' '[-c] [7057ff]' '[-d] [Drafted by an agent]'
want_line 'github https: gh issue create with -R, title, body file and label' 'gh [issue] [create]' \
  '[-R] [github.com/acme/widgets]' "[--title] [$title]" "[--body-file] [$tmp/body.md]" '[--label] [ai-drafted]'
if [ "$(grep -n '^gh \[label\] \[create\]' "$log" | cut -d: -f1)" = 1 ] && grep -q '^gh \[issue\] \[create\]' "$log"; then
  ok 'github https: the label is created before the issue'
else
  no 'github https: the label is created before the issue' "$(tr '\n' ';' < "$log")"
fi
if has "$log" 'body The export stops at the first empty row.'; then ok 'github https: gh reads the body file'; else no 'github https: gh reads the body file' "$(tr '\n' ';' < "$log")"; fi
if has "$tmp/out" 'https://forge.test/issues/7'; then ok 'github https: prints the issue URL'; else no 'github https: prints the issue URL' "$(cat "$tmp/out")"; fi
if grep -q '^glab' "$log"; then no 'github https: glab is not called' "$(tr '\n' ';' < "$log")"; else ok 'github https: glab is not called'; fi

# github.com over scp-style ssh, .git stripped
run ghscp --title "$title" --body-file "$tmp/body.md" --state "$state"
want_exit 'github scp: exit 0' 0
want_line 'github scp: -R github.com/acme/widgets' 'gh [issue] [create]' '[-R] [github.com/acme/widgets]' '[--label] [ai-drafted]'

# the label already exists: gh label create fails and the issue is still created
: > "$log"
GH_LABEL_FAIL=1 PATH="$tmp/bin:$PATH" STUB_LOG=$log sh "$root/bin/issue-create.sh" ghhttps --title "$title" \
  --body-file "$tmp/body.md" --state "$state" >"$tmp/out" 2>"$tmp/err"
got=$?
want_exit 'a failing gh label create is ignored: exit 0' 0
want_line 'a failing gh label create is ignored: the issue is created' 'gh [issue] [create]' '[--label] [ai-drafted]'

# every other host goes to glab, the body as --description-file, the whole group path in -R, as a URL: glab reads
# a bare <host>/<group>/<repo> whose host it does not know (localhost, one not yet logged in) as a gitlab.com path
run glhttps --title "$title" --body-file "$tmp/body.md" --state "$state"
want_exit 'gitlab https: exit 0' 0
want_line 'gitlab https: glab issue create with -R, title, description file and label' 'glab [issue] [create]' \
  '[-R] [https://gitlab.example.com/group/sub/widgets]' "[--title] [$title]" "[--description-file] [$tmp/body.md]" \
  '[--label] [ai-drafted]'
if grep -q '^gh' "$log"; then no 'gitlab https: gh is not called' "$(tr '\n' ';' < "$log")"; else ok 'gitlab https: gh is not called'; fi
if has "$tmp/out" 'https://forge.test/issues/7'; then ok 'gitlab https: prints the issue URL'; else no 'gitlab https: prints the issue URL' "$(cat "$tmp/out")"; fi

run glscp --title "$title" --body-file "$tmp/body.md" --state "$state"
want_exit 'gitlab scp: exit 0' 0
want_line 'gitlab scp: -R https://gitlab.example.com/group/widgets' 'glab [issue] [create]' \
  '[-R] [https://gitlab.example.com/group/widgets]' '[--label] [ai-drafted]'

# the port of an ssh origin is the ssh daemon's, not the forge's, so it is dropped; the port of an http(s) origin is
# the forge's own (F10: a self-hosted GitLab on :8929 was called on https://localhost), so it stays, with the scheme
run glsshport --title "$title" --body-file "$tmp/body.md" --state "$state"
want_exit 'gitlab ssh with a port: exit 0' 0
want_line 'gitlab ssh with a port: -R https://gitlab.example.com/g/r' 'glab [issue] [create]' '[-R] [https://gitlab.example.com/g/r]'
run glhttpsport --title "$title" --body-file "$tmp/body.md" --state "$state"
want_exit 'gitlab https with a port: exit 0' 0
want_line 'gitlab https with a port: -R https://gitlab.example.com:8443/g/r' 'glab [issue] [create]' \
  '[-R] [https://gitlab.example.com:8443/g/r]'
run glhttpport --title "$title" --body-file "$tmp/body.md" --state "$state"
want_exit 'gitlab http with a port: exit 0' 0
want_line 'gitlab http with a port: -R http://localhost:8929/g/r' 'glab [issue] [create]' '[-R] [http://localhost:8929/g/r]'

# the state clone from $WORK_DIR/state when --state is not given
: > "$log"
WORK_DIR=$tmp/work PATH="$tmp/bin:$PATH" STUB_LOG=$log sh "$root/bin/issue-create.sh" ghhttps --title "$title" \
  --body-file "$tmp/body.md" >"$tmp/out" 2>"$tmp/err"
got=$?
want_exit 'the state clone from WORK_DIR: exit 0' 0
want_line 'the state clone from WORK_DIR: gh issue create' 'gh [issue] [create]' '[-R] [github.com/acme/widgets]'

# a relative body file is read from the caller's cwd, not the clone's
: > "$log"
(cd "$tmp" && PATH="$tmp/bin:$PATH" STUB_LOG=$log sh "$root/bin/issue-create.sh" ghhttps --title "$title" \
  --body-file body.md --state "$state" >"$tmp/out" 2>"$tmp/err")
got=$?
want_exit 'a relative body file: exit 0' 0
if has "$log" 'body The export stops at the first empty row.'; then ok 'a relative body file reaches gh readable'; else no 'a relative body file reaches gh readable' "$(tr '\n' ';' < "$log")"; fi

# exit 1 with a reason, and no forge call, on a missing key, clone, origin or body file
for c in \
  'an unknown key|nosuchkey|--body-file|'"$tmp/body.md" \
  'a key whose clone is missing|noclone|--body-file|'"$tmp/body.md" \
  'a clone without an origin|noorigin|--body-file|'"$tmp/body.md" \
  'a missing body file|ghhttps|--body-file|'"$tmp/nope.md"
do
  IFS='|' read -r lbl key opt f <<EOF
$c
EOF
  run "$key" --title "$title" "$opt" "$f" --state "$state"
  want_exit "$lbl: exit 1" 1
  if [ -s "$tmp/err" ]; then ok "$lbl: a reason on stderr"; else no "$lbl: a reason on stderr" 'stderr is empty'; fi
  want_no_forge "$lbl: no forge call"
done

run --title "$title" --body-file "$tmp/body.md" --state "$state"
want_exit 'no repo-key at all: exit 1' 1
want_no_forge 'no repo-key at all: no forge call'

exit $fail
