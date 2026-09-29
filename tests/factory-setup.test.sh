#!/bin/sh
# Characterization of the setup scripts: factory-init.sh prints its diff and exits 3 without --yes, applies with
# --yes and has nothing to do on a rerun; factory-doctor.sh exits 0 and reports each check ok, missing or failing
# with its fix, over stubs of gh and glab; session-start.sh gives a registered clone its identity line and an
# unregistered one the nudge; factory-init.sh --from <url> clones the state repo.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset WORK_DIR XDG_CONFIG_HOME

fail=0
has() { # <what> <extended regex> <text>
  if printf '%s\n' "$3" | grep -Eq "$2"; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
code() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s (exit %s)\n' "$1" "$3"; fail=1; fi
}

# --- stubs: no test here reaches the real forge CLIs --------------------------------------------------------------
stub="$tmp/stub"
mkdir -p "$stub"
cat > "$stub/glab" <<'EOF'
#!/bin/sh
case "$1 ${2:-}" in
  "auth status")
    if [ $# -lt 4 ]; then
      for h in ${GSTUB_HOSTS:-}; do echo "  Logged in to $h as tester (keyring)" >&2; done
      exit 0
    fi
    case "$4" in *:*) echo "invalid hostname $4" >&2; exit 1 ;; esac
    case " ${GSTUB_HOSTS:-} " in
      *" $4 "*) echo "  Logged in to $4 as tester (keyring)" >&2 ;;
      *) echo "  $4: no token found" >&2; exit 1 ;;
    esac ;;
  "api --hostname")
    case "$3" in *:*) echo "invalid hostname $3" >&2; exit 1 ;; esac
    cat "$GSTUB_JSON" ;;
  "api projects/"*) [ -n "${GITLAB_HOST:-}" ] || exit 1; echo "$GITLAB_HOST" > "$GSTUB_JSON.host"; cat "$GSTUB_JSON" ;;
  *) exit 1 ;;
esac
EOF
cat > "$stub/gh" <<'EOF'
#!/bin/sh
case "$1 ${2:-}" in
  "auth status")
    [ "${GHSTUB_LOGIN:-0}" = 1 ] || { echo 'You are not logged into any GitHub hosts.' >&2; exit 1; }
    echo "  Logged in to github.com account tester (keyring)" >&2 ;;
  "api "*/protection/required_status_checks)
    if [ "${GHSTUB_REQUIRED:-0}" = 1 ]; then echo '{"strict":false,"contexts":["ci"]}'
    else echo '{"message":"Branch not protected","status":"404"}'; echo 'gh: Branch not protected (HTTP 404)' >&2; exit 1; fi ;;
  "api "*) echo '{"default_branch":"main","allow_merge_commit":true,"allow_squash_merge":true,"allow_rebase_merge":true}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub"/*
PATH="$stub:$PATH"
export PATH

# --- factory-init.sh ------------------------------------------------------------------------------------------
settings="$tmp/settings.json"
printf '{\n  "theme": "dark"\n}\n' > "$settings"
out=$(sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" 2>&1); rc=$?
code "init without --yes exits 3" 3 "$rc"
has "the diff adds curation: auto" '^\+curation: auto$' "$out"
has "the diff sets WORK_DIR" "^\+.*\"WORK_DIR\": \"$tmp/f\"" "$out"
has "the diff ends in the pending line" '^pending - rerun with --yes to apply$' "$out"
out=$(sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" --yes 2>&1); rc=$?
code "init --yes exits 0" 0 "$rc"
has "init --yes says applied" '^applied$' "$out"
has "the settings keep their keys" '"theme": "dark"' "$(cat "$settings")"
has "the state repo has its first commit" 'chore: init state repo' "$(git -C "$tmp/f/state" log --oneline 2>&1)"
out=$(sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" 2>&1); rc=$?
code "a rerun exits 0" 0 "$rc"
has "a rerun has nothing to do" '^nothing to do' "$out"
plug=$(dirname -- "$bin")
allow=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).permissions.allow.join("\n"))' "$settings" 2>&1)
for r in "Read(/$tmp/f/**)" "Read(/$plug/**)" "Edit(/$tmp/f/state/**)" "Bash(sh $plug/bin/*)" "Bash($plug/bin/*)"; do
  if printf '%s\n' "$allow" | grep -qxF -- "$r"; then printf 'PASS init --yes allows %s\n' "$r"
  else printf 'FAIL init --yes allows %s\n' "$r"; fail=1; fi
done
# sim F40: Claude Code matches file writes only against Edit(path) rules and warns about a Write(path) rule at
# every session start
if printf '%s\n' "$allow" | grep -q '^Write('; then printf 'FAIL init --yes writes no Write(path) rule\n'; fail=1
else printf 'PASS init --yes writes no Write(path) rule\n'; fi
node -e 'const f=process.argv[1],fs=require("fs"),o=JSON.parse(fs.readFileSync(f,"utf8"));o.permissions.allow=["Bash(ls)",o.permissions.allow[0]];fs.writeFileSync(f,JSON.stringify(o,null,2))' "$settings"
out=$(sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" 2>&1); rc=$?
code "a missing allow rule is pending" 3 "$rc"
has "the diff adds the missing rule" "^\+ +\"Bash\(sh $plug/bin/\*\)\"" "$out"
sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" --yes >/dev/null 2>&1
has "an allow rule of the user's own is kept" '"Bash\(ls\)"' "$(cat "$settings")"

# --- factory-doctor.sh ----------------------------------------------------------------------------------------
git init -q "$tmp/clone"
git -C "$tmp/clone" remote add origin https://forge.test/acme/clone.git
out=$(HOME="$tmp/home" sh "$bin/factory-doctor.sh" --root "$tmp/f" --repo "$tmp/clone" 2>&1); rc=$?
code "doctor exits 0" 0 "$rc"
has "doctor reports the unregistered clone" '^missing: clone in state/repos.yml' "$out"

# --- session-start.sh -----------------------------------------------------------------------------------------
wd="$tmp/wd"
mkdir -p "$wd/state"
git init -q "$tmp/prod"
git init -q "$tmp/stranger"
printf 'prod: {url: "https://forge.test/acme/prod.git", default_branch: main, path: "%s"}\n' "$tmp/prod" > "$wd/state/repos.yml"
start() { # <cwd>
  printf '{"session_id":"s-1","cwd":"%s","hook_event_name":"SessionStart"}' "$1" \
    | HOME="$tmp/home" WORK_DIR="$wd" sh "$bin/session-start.sh" 2>&1
}
out=$(start "$tmp/prod"); rc=$?
code "session-start exits 0 for a registered clone" 0 "$rc"
has "a registered clone gets its identity line" 'Session identity: session_id s-1, owner string factory@[^:]+:s-1' "$out"
has "a registered clone gets its factory context" 'Factory context for repo prod' "$out"
out=$(start "$tmp/stranger"); rc=$?
code "session-start exits 0 for an unregistered clone" 0 "$rc"
has "an unregistered clone gets the nudge" 'This clone is not registered' "$out"
has "an unregistered clone gets its identity line" 'Session identity: session_id s-1, owner string factory@[^:]+:s-1' "$out"

# --- factory-init.sh: a new factory.yml -----------------------------------------------------------------------------
yml=$(cat "$tmp/f/state/factory.yml")
has "a new factory.yml carries curation: and context_window: only" '^curation: auto context_window: 1000000 $' \
  "$(grep -v '^#' "$tmp/f/state/factory.yml" | tr '\n' ' ')"
# F7: without the key compact-tripwire.sh assumes 200000 and a 1M-context session trips at 101 %
has "a new factory.yml sets context_window: 1000000" '^context_window: 1000000$' "$yml"

# --- factory-init.sh --from <url>: the state repo is a clone of an existing one ------------------------------------
git init -q --bare -b main "$tmp/remote.git"
git init -q -b main "$tmp/seed"
printf '# the registry of the seed\n' > "$tmp/seed/repos.yml"
git -C "$tmp/seed" add -A
git -C "$tmp/seed" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$tmp/seed" push -q "$tmp/remote.git" main
settings3="$tmp/settings3.json"
out=$(sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" --from "$tmp/remote.git" 2>&1); rc=$?
code "init --from without --yes exits 3" 3 "$rc"
has "the diff clones the state repo" "^\+ git clone $tmp/remote\.git $tmp/h/state$" "$out"
has "the cloned repos.yml is adopted" 'repos\.yml .*adopted' "$out"
has "the diff adds the factory.yml the clone lacks" '^\+curation: auto$' "$out"
[ ! -e "$tmp/h/state" ]; code "init --from without --yes clones nothing" 0 "$?"
out=$(sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" --from "$tmp/remote.git" --yes 2>&1); rc=$?
code "init --from --yes exits 0" 0 "$rc"
has "the state repo's origin is the url" "^$tmp/remote\.git$" "$(git -C "$tmp/h/state" remote get-url origin 2>&1)"
has "repos.yml is the remote's byte for byte" '^# the registry of the seed$' "$(cat "$tmp/h/state/repos.yml" 2>&1)"
has "the clone keeps the remote's history" 'seed' "$(git -C "$tmp/h/state" log --format=%s 2>&1)"
has "factory.yml is committed on top" '^curation: auto$' "$(git -C "$tmp/h/state" show HEAD:factory.yml 2>&1)"
out=$(sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" --from "$tmp/remote.git" 2>&1); rc=$?
code "a rerun of init --from exits 0" 0 "$rc"
has "a rerun of init --from has nothing to do" '^nothing to do' "$out"
out=$(sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" --from "$tmp/other.git" 2>&1); rc=$?
code "init --from over a state repo of another origin exits 1" 1 "$rc"
has "it names the origin it found" "origin $tmp/remote\.git" "$out"
# F12: the credentials of an http(s) --from url are never printed (git itself redacts them in its own messages)
out=$(GIT_TERMINAL_PROMPT=0 sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" \
  --from "http://u:tok-SECRET1@127.0.0.1:1/x.git" 2>&1); rc=$?
code "init --from a credentialed url over another origin exits 1" 1 "$rc"
has "that refusal names the url without its credentials" 'not http://127\.0\.0\.1:1/x\.git$' "$out"
out=$(GIT_TERMINAL_PROMPT=0 sh "$bin/factory-init.sh" --root "$tmp/k" --settings "$settings3" \
  --from "https://tok-SECRET2@127.0.0.1:1/x.git" 2>&1); rc=$?
code "init --from a credentialed url that cannot be cloned exits 1" 1 "$rc"
has "that failure names the url without its credentials" 'cannot clone https://127\.0\.0\.1:1/x\.git:' "$out"
case "$out" in *SECRET*) code "no credential of a --from url is printed" 0 1 ;; *) code "no credential of a --from url is printed" 0 0 ;; esac

# --- factory-doctor.sh over registered repos: state push, aliases, MR class, workflows -------------------------------
w="$tmp/w" dhome="$tmp/dhome"
st="$w/state"
git init -q --bare -b main "$tmp/state-origin.git"
git init -q -b main "$st"
git -C "$st" remote add origin "$tmp/state-origin.git"
for r in alpha beta gamma; do git init -q "$tmp/$r"; done
git -C "$tmp/alpha" remote add origin https://gl.test/grp/alpha.git
git -C "$tmp/beta" remote add origin https://github.com/acme/beta.git
git -C "$tmp/gamma" remote add origin https://gl.test/grp/gamma.git
printf '%s\n' \
  "alpha: {url: \"https://gl.test/grp/alpha.git\", default_branch: main, path: \"$tmp/alpha\", alias: ALP}" \
  "beta: {url: \"https://github.com/acme/beta.git\", default_branch: main, path: \"$tmp/beta\", alias: BET}" \
  "gamma: {url: \"https://gl.test/grp/gamma.git\", default_branch: main, path: \"$tmp/gamma\"}" > "$st/repos.yml"
mkdir -p "$st/repos/alpha" "$st/repos/beta" "$st/repos/gamma"
for r in alpha beta gamma; do printf -- '---\nstack: dotnet\n---\n' > "$st/repos/$r/toolset.md"; done
printf 'curation: auto\n' > "$st/factory.yml"
git -C "$st" add -A
git -C "$st" -c user.name=t -c user.email=t@t commit -qm init
git -C "$st" push -q origin main
mkdir -p "$dhome/.claude"
printf '{\n  "env": {"WORK_DIR": "%s"}\n}\n' "$w" > "$dhome/.claude/settings.json"
printf '{"merge_method":"merge","squash_option":"default_off","only_allow_merge_if_pipeline_succeeds":false,"allow_merge_on_skipped_pipeline":false}\n' > "$tmp/class-a.json"
printf '{"merge_method":"ff","squash_option":"always","only_allow_merge_if_pipeline_succeeds":true,"allow_merge_on_skipped_pipeline":true}\n' > "$tmp/class-b.json"
printf '{"merge_method":"merge","squash_option":"default_off","only_allow_merge_if_pipeline_succeeds":true,"allow_merge_on_skipped_pipeline":false}\n' > "$tmp/class-c.json"
GSTUB_JSON="$tmp/class-a.json" GSTUB_HOSTS=gl.test GHSTUB_LOGIN=1
export GSTUB_JSON GSTUB_HOSTS GHSTUB_LOGIN
report() { # <clone>: the text report over that clone
  HOME="$dhome" sh "$bin/factory-doctor.sh" --root "$w" --repo "$1" 2>&1
}

out=$(report "$tmp/alpha"); rc=$?
code "doctor over a registered clone exits 0" 0 "$rc"
has "nothing unpushed is ok" '^ok: every state commit is pushed$' "$out"
has "unique aliases are ok" '^ok: 2 aliases, all unique$' "$out"
has "this clone's alias is ok" '^ok: alpha alias ALP, its new ids are T-ALP-<n>$' "$out"
has "a class A GitLab repo is ok" '^ok: alpha is class A' "$out"
out=$(report "$tmp/gamma")
has "a repo without an alias is missing, with its legacy ids named" '^missing: gamma has no alias, .*legacy' "$out"
has "its fix is add-repo, which proposes one" 'factory-add-repo\.sh .*--repo .*gamma' "$out"
out=$(report "$tmp/beta")
has "a GitHub repo without required checks is class A" '^ok: beta is class A' "$out"
has "a GitHub repo without workflows is ok" '^ok: the workflows of beta filter on main, or there are none$' "$out"

# a state remote with credentials in its url: doctor names the remote, never the secret
git -C "$st" remote set-url origin https://oauth2:SECRET@gitlab.example.com/g/state.git
out=$(report "$tmp/alpha")
has "the state remote with credentials is still read" '^ok: state remote https://gitlab\.example\.com/g/state\.git$' "$out"
if printf '%s\n' "$out" | grep -q SECRET; then printf 'FAIL the report prints the credentials of the state remote\n'; fail=1
else printf 'PASS the report prints no credentials of the state remote\n'; fi
git -C "$st" remote set-url origin "$tmp/state-origin.git"

out=$(export GSTUB_HOSTS=''; report "$tmp/alpha")
has "not logged in: the MR class is not read, cleanly" '^missing: MR class of alpha not read: glab is not logged in to gl\.test' "$out"
has "its fix is the login" 'glab auth login --hostname gl\.test' "$out"
out=$(export GSTUB_JSON="$tmp/class-b.json"; report "$tmp/alpha")
has "ff, squash always, pipeline required, skipped counts is class B" '^ok: alpha is class B' "$out"
out=$(export GSTUB_JSON="$tmp/class-c.json"; report "$tmp/alpha")
has "pipeline required and skipped not counted is class C, failing" '^failing: alpha is class C' "$out"
has "the class C fix names the setting" 'allow_merge_on_skipped_pipeline' "$out"

# F10: an http(s) origin with a port, a self-hosted GitLab on :8929: the host keeps its port, and glab reads it
# without --hostname, which refuses a host:port
sed -i 's#https://gl.test/grp/alpha.git#http://localhost:8929/g/r.git#' "$st/repos.yml"
out=$(export GSTUB_HOSTS='localhost:8929 gl.test'; report "$tmp/alpha")
has "the MR class of a host:port origin is read" '^ok: alpha is class A' "$out"
has "glab api gets the host:port through GITLAB_HOST" '^localhost:8929$' "$(cat "$tmp/class-a.json.host" 2>/dev/null)"
git -C "$st" checkout -q -- repos.yml

mkdir -p "$tmp/beta/.github/workflows"
printf 'on:\n  pull_request:\n  push:\njobs: {}\n' > "$tmp/beta/.github/workflows/ci.yml"
out=$(report "$tmp/beta")
has "a workflow without a branch filter is failing" '^failing: workflows of beta without a branch filter on main: *ci\.yml' "$out"
printf 'on:\n  pull_request:\n    branches: [main]\n  push:\n    branches:\n      - main\njobs: {}\n' > "$tmp/beta/.github/workflows/ci.yml"
out=$(report "$tmp/beta")
has "a workflow filtered on the default branch is ok" '^ok: the workflows of beta filter on main' "$out"
out=$(export GHSTUB_REQUIRED=1; report "$tmp/beta")
# block-mr.sh writes skipped_counts_as_success: false for every GitHub repo, so required checks make it class C
has "a GitHub repo with required checks is class C, failing" '^failing: beta is class C' "$out"
has "its fix filters the workflows or drops the required check on the work branch" \
  'filter .*workflows.* on main.*drop the required .*check.* work branch' "$out"

sed -i 's/^gamma: \(.*\)}$/gamma: \1, alias: ALP}/' "$st/repos.yml"
out=$(report "$tmp/alpha")
has "two repos with one alias are failing" '^failing: one alias on two repos:.*ALP.*alpha.*gamma' "$out"
git -C "$st" checkout -q -- repos.yml

printf 'x\n' > "$st/new.md"
git -C "$st" add new.md
git -C "$st" -c user.name=t -c user.email=t@t commit -qm new
out=$(report "$tmp/alpha")
has "a recent unpushed commit is ok" '^ok: 1 state commit\(s\) unpushed for less than 10 minutes$' "$out"
printf 'x\n' > "$st/old.md"
git -C "$st" add old.md
old=$(( $(date +%s) - 1200 ))
GIT_COMMITTER_DATE="$old +0000" git -C "$st" -c user.name=t -c user.email=t@t commit -qm old
out=$(report "$tmp/alpha")
has "a commit unpushed for more than 10 minutes is failing" '^failing: 2 state commit\(s\) unpushed' "$out"
has "its fix is state-push.sh" 'state-push\.sh' "$out"

# --- herdr, for the herd lane: checked only when it is on PATH ---------------------------------------------------
# a machine of the tester's own with herdr installed has nothing to assert here
if ! command -v herdr >/dev/null 2>&1; then
  if printf '%s\n' "$out" | grep -q 'herdr'; then printf 'FAIL no herdr on PATH gives no herdr line\n'; fail=1
  else printf 'PASS no herdr on PATH gives no herdr line\n'; fi
fi
cat > "$stub/herdr" <<'EOF'
#!/bin/sh
case "$1 ${2:-}" in
  "--version "*) echo "herdr ${HSTUB_VERSION:-0.8.2}" ;;
  "status "*) printf 'server:\n  status: running\n  compatible: yes\n' ;;
  "integration status") echo "claude: ${HSTUB_INTEGRATION:-current (v8)} (/x/hook.sh)" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$stub/herdr"
out=$(report "$tmp/alpha")
has "herdr 0.8.2 is ok" '^ok: herdr 0\.8\.2$' "$out"
has "a running compatible herdr server is ok" '^ok: the herdr server runs and is compatible$' "$out"
has "the current Claude integration is ok" '^ok: herdr integration for Claude current' "$out"
out=$(export HSTUB_VERSION=0.8.1 HSTUB_INTEGRATION='not installed'; report "$tmp/alpha")
has "herdr 0.8.1 is failing" '^failing: herdr 0\.8\.1 is older than 0\.8\.2' "$out"
has "no Claude integration is missing, with its fix" '^missing: no herdr integration for Claude.*herdr integration install claude' "$out"
rm -f "$stub/herdr"

# --- memory over budget: consolidate takes repo: and global scopes, a repo-agent scope gets the daily pass -----------
for d in repos/alpha/memory repos/alpha/agents/scout/memory; do
  mkdir -p "$st/$d"
  i=0; while [ "$i" -lt 41 ]; do : > "$st/$d/l$i.md"; i=$((i + 1)); done
done
out=$(report "$tmp/alpha")
has "a repo scope over budget is told to consolidate" '^missing: memory over budget in repo:alpha, run factory consolidate repo:alpha' "$out"
has "a repo-agent scope over budget is told the daily pass" \
  '^missing: memory over budget in repo-agent:alpha/scout, .*/claude-factory:memory-daily repo-agent:alpha/scout$' "$out"
if printf '%s\n' "$out" | grep -q 'consolidate repo-agent:'; then
  printf 'FAIL no consolidate for a repo-agent scope\n'; fail=1
else printf 'PASS no consolidate for a repo-agent scope\n'; fi
rm -rf "$st/repos/alpha/memory" "$st/repos/alpha/agents"

exit $fail
