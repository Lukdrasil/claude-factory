#!/bin/sh
# forge.sh Gitea reads: an issue or pull request URL of the Gitea shape is read through
# `tea api -l <login> repos/<owner>/<repo>/...`, the login being the `tea login list` row whose URL host matches
# the URL's host. No matching login exits 3 after printing the signed-in instances. tea, gh and glab are stubs
# on PATH; tea logs every argument in brackets and prints a login table for `login list`.
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM
fail=0
log=$tmp/tea.log
mkdir -p "$tmp/bin"

cat > "$tmp/bin/tea" <<'EOF'
#!/bin/sh
{ printf 'tea'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$STUB_LOG"
case "$1" in
  login|logins)
    case "$*" in
      *tsv*)
        printf 'Name\tURL\tSSHHost\tUser\tDefault\n'
        printf 'work\thttps://gitea.example.com\tgitea.example.com\tme\tfalse\n'
        printf 'home\thttps://git.home.test:3000/\tgit.home.test\tme\ttrue\n' ;;
      *csv*)
        printf 'Name,URL,SSHHost,User,Default\n'
        printf 'work,https://gitea.example.com,gitea.example.com,me,false\n'
        printf 'home,https://git.home.test:3000/,git.home.test,me,true\n' ;;
      *)
        printf '| NAME | URL | SSH HOST | USER | DEFAULT |\n'
        printf '| work | https://gitea.example.com | gitea.example.com | me | false |\n'
        printf '| home | https://git.home.test:3000/ | git.home.test | me | true |\n' ;;
    esac ;;
  api)
    for a in "$@"; do e=$a; done
    printf '{"endpoint":"%s"}\n' "$e" ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/gh"
printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/glab"
chmod +x "$tmp/bin/tea" "$tmp/bin/gh" "$tmp/bin/glab"

run() { # <args...>: forge.sh with the stubs on PATH; exit code in $got, stdout in $tmp/out
  : > "$log"
  PATH="$tmp/bin:$PATH" STUB_LOG=$log sh "$root/bin/forge.sh" "$@" >"$tmp/out" 2>"$tmp/err"
  got=$?
}
ok() { printf 'PASS %s\n' "$1"; }
no() { printf 'FAIL %s: %s\n' "$1" "$2"; fail=1; }
want_exit() { if [ "$got" -eq "$2" ]; then ok "$1"; else no "$1" "want exit $2, got $got: $(head -c 300 "$tmp/err")"; fi; }
want_call() { # <label> <exact log line>
  if grep -qxF -- "$2" "$log"; then ok "$1"; else no "$1" "no '$2' in $(tr '\n' ';' < "$log")"; fi
}
want_out() { # <label> <file> <fragment>
  if grep -qF -- "$3" "$2"; then ok "$1"; else no "$1" "'$3' missing from: $(head -c 300 "$2")"; fi
}

# issue: detail and comments through the login whose URL host matches
run issue https://gitea.example.com/acme/widgets/issues/5
want_exit 'issue: exit 0' 0
want_call 'issue: detail through -l work' 'tea [api] [-l] [work] [repos/acme/widgets/issues/5]'
want_call 'issue: comments through -l work' 'tea [api] [-l] [work] [repos/acme/widgets/issues/5/comments]'
want_out 'issue: detail printed' "$tmp/out" '{"endpoint":"repos/acme/widgets/issues/5"}'
want_out 'issue: comments separator printed' "$tmp/out" '--- comments ---'
if grep -q '^tea \[api\] \[gitea.example.com\]' "$log"; then no 'issue: host is not passed as the endpoint' "$(cat "$log")"; else ok 'issue: host is not passed as the endpoint'; fi

# mr: the pull detail, the comments under issues/<n>/comments; a login URL with a port and trailing slash
run mr https://git.home.test:3000/me/tool/pulls/12
want_exit 'mr: exit 0' 0
want_call 'mr: detail through -l home' 'tea [api] [-l] [home] [repos/me/tool/pulls/12]'
want_call 'mr: comments through -l home' 'tea [api] [-l] [home] [repos/me/tool/issues/12/comments]'

# a host with no tea login: exit 3, the signed-in instances on stderr, no api call
run issue https://other.example.org/acme/widgets/issues/5
want_exit 'no login: exit 3' 3
want_out 'no login: signed-in instances printed' "$tmp/err" 'tea: '
if grep -q '^tea \[api\]' "$log"; then no 'no login: no api call' "$(cat "$log")"; else ok 'no login: no api call'; fi

exit "$fail"
