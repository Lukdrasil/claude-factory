#!/bin/sh
# forge.sh Gitea reads: an issue or pull request URL of the Gitea shape is read through
# `tea api -l <login> repos/<owner>/<repo>/...`, the login being the `tea login list` row whose URL host matches
# the URL's host. No matching login exits 3 after printing the signed-in instances. tea, gh and glab are stubs
# on PATH; tea logs every argument in brackets and prints a login table for `login list`. GitLab reads go through
# `glab ... -R <scheme>://<host>/<project>`, a port kept (F10), and attachments through `glab api`, with
# GITLAB_HOST=<host>:<port> in place of --hostname when the host has a port; glab logs like tea, plus GITLAB_HOST.
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
cat > "$tmp/bin/glab" <<'EOF'
#!/bin/sh
{ printf 'glab'; [ -z "${GITLAB_HOST:-}" ] || printf ' GITLAB_HOST=%s' "$GITLAB_HOST"; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$STUB_LOG"
case "$1" in
  issue|mr) echo '{"description":"![shot](/uploads/0123456789abcdef/shot.png)"}' ;;
  api) echo PNG ;;
  *) exit 1 ;;
esac
EOF
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

# GitLab: the project in -R as a URL, so glab never reads <host>/<group>/<repo> as a gitlab.com path, and a port kept
run mr http://localhost:8929/g/r/-/merge_requests/3
want_exit 'gitlab mr with a port: exit 0' 0
want_call 'gitlab mr with a port: detail through -R http://localhost:8929/g/r' \
  'glab [mr] [view] [3] [-R] [http://localhost:8929/g/r] [-F] [json]'
want_call 'gitlab mr with a port: comments through the same -R' 'glab [mr] [view] [3] [-R] [http://localhost:8929/g/r] [--comments]'
run issue https://gitlab.example.com/group/sub/w/-/issues/5 --assets "$tmp/a1"
want_exit 'gitlab issue: exit 0' 0
want_call 'gitlab issue: detail through -R https://gitlab.example.com/group/sub/w' \
  'glab [issue] [view] [5] [-R] [https://gitlab.example.com/group/sub/w] [-F] [json]'
want_call 'gitlab issue: the attachment through glab api --hostname' \
  'glab [api] [--hostname] [gitlab.example.com] [projects/group%2Fsub%2Fw/uploads/0123456789abcdef/shot.png]'
# glab api --hostname refuses host:port ("invalid hostname"), GITLAB_HOST takes it
run issue http://localhost:8929/g/r/-/issues/4 --assets "$tmp/a2"
want_exit 'gitlab issue with a port: exit 0' 0
want_call 'gitlab issue with a port: the attachment through GITLAB_HOST=localhost:8929' \
  'glab GITLAB_HOST=localhost:8929 [api] [projects/g%2Fr/uploads/0123456789abcdef/shot.png]'
want_out 'gitlab issue with a port: the attachment is saved' "$tmp/out" "$tmp/a2/01234567-shot.png"

exit "$fail"
