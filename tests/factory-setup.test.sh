#!/bin/sh
# Characterization of the setup scripts the UI setting extends: factory-init.sh prints its diff and exits 3
# without --yes, applies with --yes and has nothing to do on a rerun; factory-doctor.sh reports the spawn mode
# and exits 0; session-start.sh gives a registered clone its identity line and an unregistered one the nudge.
# factory-doctor.sh --json writes <ui home>/setup/doctor.json, the steps of the Setup tab, each done, missing or
# failing with its fix, over stubs of herdr, gh, glab, claude, python3 and docker; init and add-repo refresh it;
# factory-init.sh --from <url> clones the state repo.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset HERDR_ENV HERDR_PANE_ID WORK_DIR XDG_CONFIG_HOME
export FACTORY_UI_HOME="$tmp/ui"

fail=0
has() { # <what> <extended regex> <text>
  if printf '%s\n' "$3" | grep -Eq "$2"; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
code() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s (exit %s)\n' "$1" "$3"; fail=1; fi
}

# --- stubs: no test here reaches the real herdr, forge CLIs or Claude Code -------------------------------------
stub="$tmp/stub"
mkdir -p "$stub"
cat > "$stub/herdr" <<'EOF'
#!/bin/sh
case "$1 ${2:-}" in
  "--version "*) echo "herdr ${HSTUB_VERSION:-0.8.2}" ;;
  "status "*)
    [ "${HSTUB_SERVER:-running}" = running ] || { echo 'error: the herdr server does not answer' >&2; exit 1; }
    printf 'client:\n  version: %s\n\nserver:\n  status: running\n  version: %s\n  compatible: yes\n' \
      "${HSTUB_VERSION:-0.8.2}" "${HSTUB_VERSION:-0.8.2}" ;;
  "integration status")
    echo "pi: current (v8) (/x/pi.ts)"
    echo "claude: ${HSTUB_INTEGRATION:-current (v8)} (/x/.claude/hooks/herdr-agent-state.sh)" ;;
  "agent get")
    if [ "${HSTUB_CEO:-0}" = 1 ]; then echo '{"result":{"agent":{"name":"ceo","agent_status":"idle"}}}'
    else echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1; fi ;;
  *) exit 0 ;;
esac
EOF
cat > "$stub/glab" <<'EOF'
#!/bin/sh
case "$1 ${2:-}" in
  "auth status")
    case " ${GSTUB_HOSTS:-} " in
      *" $4 "*) echo "  Logged in to $4 as tester (keyring)" >&2 ;;
      *) echo "  $4: no token found" >&2; exit 1 ;;
    esac ;;
  "api --hostname") cat "$GSTUB_JSON" ;;
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
printf '#!/bin/sh\necho "2.1.300 (Claude Code)"\n' > "$stub/claude"
printf '#!/bin/sh\nexit 0\n' > "$stub/python3"
printf '#!/bin/sh\nexit "${DSTUB_RC:-0}"\n' > "$stub/docker"
chmod +x "$stub"/*
PATH="$stub:$PATH"
export PATH

# --- factory-init.sh ------------------------------------------------------------------------------------------
settings="$tmp/settings.json"
printf '{\n  "theme": "dark"\n}\n' > "$settings"
out=$(sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" --spawn manual 2>&1); rc=$?
code "init without --yes exits 3" 3 "$rc"
has "the diff adds curation: auto" '^\+curation: auto$' "$out"
has "the diff adds spawn: manual" '^\+spawn: manual$' "$out"
has "the diff sets WORK_DIR" "^\+.*\"WORK_DIR\": \"$tmp/f\"" "$out"
has "the diff ends in the pending line" '^pending - rerun with --yes to apply$' "$out"
out=$(sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" --spawn manual --yes 2>&1); rc=$?
code "init --yes exits 0" 0 "$rc"
has "init --yes says applied" '^applied$' "$out"
has "the settings keep their keys" '"theme": "dark"' "$(cat "$settings")"
has "the state repo has its first commit" 'chore: init state repo' "$(git -C "$tmp/f/state" log --oneline 2>&1)"
out=$(sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" --spawn manual 2>&1); rc=$?
code "a rerun exits 0" 0 "$rc"
has "a rerun has nothing to do" '^nothing to do' "$out"

# --- factory-init.sh --ui over an existing factory.yml: a missing or differing ui: and a missing ui_port: are pending
settings2="$tmp/settings2.json"
sh "$bin/factory-init.sh" --root "$tmp/g" --settings "$settings2" --spawn manual --ui docker --yes >/dev/null 2>&1
printf 'curation: manual\nspawn: manual\n' > "$tmp/g/state/factory.yml"
git -C "$tmp/g/state" -c user.name=t -c user.email=t@t commit -qm 'the factory.yml of before the UI' -- factory.yml
out=$(sh "$bin/factory-init.sh" --root "$tmp/g" --settings "$settings2" --spawn manual --ui docker 2>&1); rc=$?
code "--ui docker over a factory.yml without ui: exits 3" 3 "$rc"
has "the diff adds ui: docker" '^\+ui: docker$' "$out"
has "the diff adds ui_port: 7171" '^\+ui_port: 7171$' "$out"
has "without --yes factory.yml is unchanged" '^curation: manual spawn: manual $' "$(tr '\n' ' ' < "$tmp/g/state/factory.yml")"
out=$(sh "$bin/factory-init.sh" --root "$tmp/g" --settings "$settings2" --spawn manual --ui docker --yes 2>&1); rc=$?
code "--ui docker --yes exits 0" 0 "$rc"
yml=$(cat "$tmp/g/state/factory.yml")
has "--yes writes ui: docker" '^ui: docker$' "$yml"
has "--yes writes ui_port: 7171" '^ui_port: 7171$' "$yml"
has "--yes keeps curation: manual" '^curation: manual$' "$yml"
has "--yes keeps spawn: manual" '^spawn: manual$' "$yml"
out=$(sh "$bin/factory-init.sh" --root "$tmp/g" --settings "$settings2" --spawn manual --ui docker 2>&1); rc=$?
code "a rerun with ui: docker in place exits 0" 0 "$rc"
has "a rerun with ui: docker in place has nothing to do" '^nothing to do' "$out"
sed -i 's/^ui_port:.*/ui_port: 7272/' "$tmp/g/state/factory.yml"
out=$(sh "$bin/factory-init.sh" --root "$tmp/g" --settings "$settings2" --spawn manual --ui off 2>&1); rc=$?
code "--ui off over ui: docker exits 3" 3 "$rc"
has "the diff sets ui: off" '^\+ui: off$' "$out"
out=$(sh "$bin/factory-init.sh" --root "$tmp/g" --settings "$settings2" --spawn manual --ui off --yes 2>&1); rc=$?
code "--ui off --yes exits 0" 0 "$rc"
yml=$(cat "$tmp/g/state/factory.yml")
has "--yes writes ui: off" '^ui: off$' "$yml"
has "an existing ui_port is kept" '^ui_port: 7272$' "$yml"
printf 'curation: manual\nspawn: manual\nui:  docker\nui_port: 7171' > "$tmp/g/state/factory.yml"
git -C "$tmp/g/state" -c user.name=t -c user.email=t@t commit -qm 'a hand-written factory.yml' -- factory.yml
out=$(sh "$bin/factory-init.sh" --root "$tmp/g" --settings "$settings2" --spawn manual --ui docker 2>&1); rc=$?
code "--ui docker over ui:  docker with no final newline exits 0" 0 "$rc"
has "--ui docker over ui:  docker with no final newline has nothing to do" '^nothing to do' "$out"

# --- factory-doctor.sh ----------------------------------------------------------------------------------------
git init -q "$tmp/clone"
git -C "$tmp/clone" remote add origin https://forge.test/acme/clone.git
out=$(HOME="$tmp/home" sh "$bin/factory-doctor.sh" --root "$tmp/f" --repo "$tmp/clone" 2>&1); rc=$?
code "doctor exits 0" 0 "$rc"
has "doctor reports spawn: manual" '^ok: spawn: manual' "$out"
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

# --- factory-init.sh: a new factory.yml carries the capacity defaults of PLAN 3.3 ----------------------------------
yml=$(cat "$tmp/f/state/factory.yml")
has "a new factory.yml has capacity:" '^capacity:$' "$yml"
has "a new factory.yml caps sessions at 10" '^  sessions: 10$' "$yml"
has "a new factory.yml caps repo-lead at 3" '^  roles: \{repo-lead: 3, scout: 8,' "$yml"

# --- factory-init.sh --from <url>: the state repo is a clone of an existing one ------------------------------------
git init -q --bare -b main "$tmp/remote.git"
git init -q -b main "$tmp/seed"
printf '# the registry of the seed\n' > "$tmp/seed/repos.yml"
git -C "$tmp/seed" add -A
git -C "$tmp/seed" -c user.name=t -c user.email=t@t commit -qm seed
git -C "$tmp/seed" push -q "$tmp/remote.git" main
settings3="$tmp/settings3.json"
out=$(sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" --spawn manual --from "$tmp/remote.git" 2>&1); rc=$?
code "init --from without --yes exits 3" 3 "$rc"
has "the diff clones the state repo" "^\+ git clone $tmp/remote\.git $tmp/h/state$" "$out"
has "the cloned repos.yml is adopted" 'repos\.yml .*adopted' "$out"
has "the diff adds the factory.yml the clone lacks" '^\+curation: auto$' "$out"
[ ! -e "$tmp/h/state" ]; code "init --from without --yes clones nothing" 0 "$?"
out=$(sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" --spawn manual --from "$tmp/remote.git" --yes 2>&1); rc=$?
code "init --from --yes exits 0" 0 "$rc"
has "the state repo's origin is the url" "^$tmp/remote\.git$" "$(git -C "$tmp/h/state" remote get-url origin 2>&1)"
has "repos.yml is the remote's byte for byte" '^# the registry of the seed$' "$(cat "$tmp/h/state/repos.yml" 2>&1)"
has "the clone keeps the remote's history" 'seed' "$(git -C "$tmp/h/state" log --format=%s 2>&1)"
has "factory.yml is committed on top" '^curation: auto$' "$(git -C "$tmp/h/state" show HEAD:factory.yml 2>&1)"
out=$(sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" --spawn manual --from "$tmp/remote.git" 2>&1); rc=$?
code "a rerun of init --from exits 0" 0 "$rc"
has "a rerun of init --from has nothing to do" '^nothing to do' "$out"
out=$(sh "$bin/factory-init.sh" --root "$tmp/h" --settings "$settings3" --spawn manual --from "$tmp/other.git" 2>&1); rc=$?
code "init --from over a state repo of another origin exits 1" 1 "$rc"
has "it names the origin it found" "origin $tmp/remote\.git" "$out"

# --- init and add-repo refresh <ui home>/setup/doctor.json ----------------------------------------------------------
rm -f "$FACTORY_UI_HOME/setup/doctor.json"
sh "$bin/factory-init.sh" --root "$tmp/f" --settings "$settings" --spawn manual >/dev/null 2>&1
[ -s "$FACTORY_UI_HOME/setup/doctor.json" ]; code "init refreshes doctor.json" 0 "$?"
rm -f "$FACTORY_UI_HOME/setup/doctor.json"
sh "$bin/factory-add-repo.sh" --root "$tmp/f" --repo "$tmp/clone" >/dev/null 2>&1
[ -s "$FACTORY_UI_HOME/setup/doctor.json" ]; code "add-repo refreshes doctor.json" 0 "$?"
rm -f "$FACTORY_UI_HOME/setup/doctor.json"
HOME="$tmp/home" sh "$bin/factory-doctor.sh" --json --root "$tmp/f" >/dev/null 2>&1
[ -s "$FACTORY_UI_HOME/setup/doctor.json" ]; code "doctor --json without --ui-home writes under FACTORY_UI_HOME" 0 "$?"

# --- factory-doctor.sh --json: the fixture ------------------------------------------------------------------------
w="$tmp/w" uih="$tmp/uih" dhome="$tmp/dhome"
st="$w/state"
git init -q --bare -b main "$tmp/state-origin.git"
git init -q -b main "$st"
git -C "$st" remote add origin "$tmp/state-origin.git"
for r in alpha beta gamma; do git init -q "$tmp/$r"; done
git -C "$tmp/alpha" remote add origin https://gl.test/grp/alpha.git
printf '%s\n' \
  "alpha: {url: \"https://gl.test/grp/alpha.git\", default_branch: main, path: \"$tmp/alpha\", alias: ALP}" \
  "beta: {url: \"https://github.com/acme/beta.git\", default_branch: main, path: \"$tmp/beta\", alias: BET}" \
  "gamma: {url: \"https://gl.test/grp/gamma.git\", default_branch: main, path: \"$tmp/gamma\"}" > "$st/repos.yml"
mkdir -p "$st/repos/alpha" "$st/repos/beta" "$st/repos/gamma"
for r in alpha beta gamma; do printf -- '---\nstack: dotnet\n---\n' > "$st/repos/$r/toolset.md"; done
printf 'curation: auto\nspawn: herdr\n' > "$st/factory.yml"
git -C "$st" add -A
git -C "$st" -c user.name=t -c user.email=t@t commit -qm init
git -C "$st" push -q origin main
mkdir -p "$dhome/.claude" "$dhome/.config/herdr"
printf '{\n  "env": {"WORK_DIR": "%s"},\n  "promptSuggestionEnabled": false\n}\n' "$w" > "$dhome/.claude/settings.json"
printf '[ui]\nsidebar = true\n\n[ui.toast]\ndelivery = "system"\n' > "$dhome/.config/herdr/config.toml"
printf '{"merge_method":"merge","squash_option":"default_off","only_allow_merge_if_pipeline_succeeds":false,"allow_merge_on_skipped_pipeline":false}\n' > "$tmp/class-a.json"
printf '{"merge_method":"ff","squash_option":"always","only_allow_merge_if_pipeline_succeeds":true,"allow_merge_on_skipped_pipeline":true}\n' > "$tmp/class-b.json"
printf '{"merge_method":"merge","squash_option":"default_off","only_allow_merge_if_pipeline_succeeds":true,"allow_merge_on_skipped_pipeline":false}\n' > "$tmp/class-c.json"
GSTUB_JSON="$tmp/class-a.json" GSTUB_HOSTS=gl.test GHSTUB_LOGIN=1
export GSTUB_JSON GSTUB_HOSTS GHSTUB_LOGIN
dj="$uih/setup/doctor.json"
djson() { HOME="$dhome" sh "$bin/factory-doctor.sh" --json --root "$w" --ui-home "$uih" >/dev/null 2>&1; }
step() { # <id>: `<state> <detail> | <fix>` of that step in the last doctor.json, `none` without it
  node -e '
    const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
    const s = j.steps.find(x => x.id === process.argv[2]);
    console.log(s ? s.state + " " + s.detail + " | " + s.fix : "none");' "$dj" "$1" 2>/dev/null || echo unreadable
}

rm -rf "$uih"
djson; code "doctor --json exits 0" 0 "$?"
[ -s "$dj" ]; code "doctor --json writes <ui home>/setup/doctor.json" 0 "$?"
shape=$(node -e '
  const j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const ok = Array.isArray(j.steps) && j.steps.length > 0 && j.steps.every(s =>
    typeof s.id === "string" && ["done", "missing", "failing"].includes(s.state)
    && typeof s.detail === "string" && s.detail !== "" && typeof s.fix === "string");
  console.log(ok ? "shape ok" : "shape bad");
  console.log("ids " + j.steps.map(s => s.id).join(" "));' "$dj" 2>&1)
has "every step has id, state done|missing|failing, detail and fix" '^shape ok$' "$shape"
has "the steps walk the Setup tab in order" "^ids git node python3 docker herdr herdr-server forge-login claude state-repo state-remote state-push work-dir prompt-suggestion herdr-integration herdr-toast repos aliases repo:alpha:path repo:alpha:alias repo:alpha:toolset repo:alpha:mr-class repo:beta:path repo:beta:alias repo:beta:toolset repo:beta:mr-class repo:beta:workflows repo:gamma:path repo:gamma:alias repo:gamma:toolset repo:gamma:mr-class capacity doctor ceo$" "$shape"

# --- each check done over the fixture -----------------------------------------------------------------------------
has "python3 is done" '^done ' "$(step python3)"
has "herdr 0.8.2 is done" '^done .*0\.8\.2' "$(step herdr)"
has "a running compatible herdr server is done" '^done ' "$(step herdr-server)"
has "the claude integration current is done" '^done ' "$(step herdr-integration)"
has "toast delivery system is done" '^done .*system' "$(step herdr-toast)"
has "the Claude Code version is read" '^done .*2\.1\.300' "$(step claude)"
has "a login on gl.test and github.com is done" '^done ' "$(step forge-login)"
has "the state repo is done" '^done ' "$(step state-repo)"
has "WORK_DIR in the settings is done" '^done ' "$(step work-dir)"
has "promptSuggestionEnabled false is done" '^done ' "$(step prompt-suggestion)"
has "nothing unpushed is done" '^done ' "$(step state-push)"
has "unique aliases are done" '^done ' "$(step aliases)"
has "an alias is done" '^done .*ALP' "$(step repo:alpha:alias)"
has "a repo without an alias is missing, with its legacy ids named" '^missing .*legacy' "$(step repo:gamma:alias)"
has "its fix is add-repo, which proposes one" '\| .*factory-add-repo\.sh .*--repo .*gamma' "$(step repo:gamma:alias)"
has "a class A GitLab repo is done" '^done .*class A' "$(step repo:alpha:mr-class)"
has "a GitHub repo without required checks is class A" '^done .*class A' "$(step repo:beta:mr-class)"
has "a GitHub repo without workflows is done" '^done ' "$(step repo:beta:workflows)"
has "no capacity: is missing" '^missing .*capacity' "$(step capacity)"
has "the capacity fix is the block of PLAN 3.3" '\| .*sessions: 10.*repo-lead: 3' "$(step capacity)"
has "doctor is not green while a step is missing" '^missing ' "$(step doctor)"
has "the CEO is not running" '^missing ' "$(step ceo)"
has "the ceo fix is the command" "\| .*$st.*claude.*/claude-factory:factory ceo" "$(step ceo)"
HSTUB_CEO=1 djson
has "a live ceo agent is done" '^done ' "$(step ceo)"

# --- each check missing or failing ----------------------------------------------------------------------------------
sys="$tmp/sys"
mkdir -p "$sys"
for t in sh awk sed grep cat date mkdir mv rm tr head tail sort uniq cut dirname basename find xargs wc env git \
  mktemp tee ls cp chmod id expr od; do
  p=$(command -v "$t" 2>/dev/null) || continue
  case "$p" in /*) ln -s "$p" "$sys/$t" ;; esac
done
rm -rf "$uih"
env PATH="$sys" HOME="$dhome" sh "$bin/factory-doctor.sh" --json --root "$w" --ui-home "$uih" >/dev/null 2>&1
code "doctor --json on a bare PATH exits 0" 0 "$?"
has "no python3 is missing, the integration hook needs it" '^missing .*python3' "$(step python3)"
has "no herdr is missing" '^missing ' "$(step herdr)"
has "no node is missing" '^missing ' "$(step node)"
has "no docker is missing" '^missing ' "$(step docker)"
has "no Claude Code is missing" '^missing ' "$(step claude)"
has "no forge CLI is missing" '^missing ' "$(step forge-login)"
has "no glab: the MR class is not read, cleanly" '^missing .*not read' "$(step repo:alpha:mr-class)"

HSTUB_VERSION=0.8.1 djson
has "herdr 0.8.1 is failing" '^failing .*0\.8\.1.*0\.8\.2' "$(step herdr)"
HSTUB_SERVER=down djson
has "a herdr server that does not answer is failing" '^failing ' "$(step herdr-server)"
HSTUB_INTEGRATION='outdated (v7)' djson
has "an outdated claude integration is failing" '^failing ' "$(step herdr-integration)"
has "its fix installs the integration" '\| .*herdr integration install claude' "$(step herdr-integration)"
HSTUB_INTEGRATION='not installed' djson
has "no claude integration is missing" '^missing ' "$(step herdr-integration)"
DSTUB_RC=1 djson
has "a Docker daemon that does not answer is failing" '^failing ' "$(step docker)"
GSTUB_HOSTS='' djson
has "no login on gl.test is missing" '^missing .*gl\.test' "$(step forge-login)"
has "not logged in: the MR class is not read, cleanly" '^missing .*not read' "$(step repo:alpha:mr-class)"
has "its fix is the login" '\| .*glab auth login --hostname gl\.test' "$(step repo:alpha:mr-class)"
GSTUB_JSON="$tmp/class-b.json" djson
has "ff, squash always, pipeline required, skipped counts is class B" '^done .*class B' "$(step repo:alpha:mr-class)"
GSTUB_JSON="$tmp/class-c.json" djson
has "pipeline required and skipped not counted is class C, failing" '^failing .*class C' "$(step repo:alpha:mr-class)"
has "the class C fix names the setting" '\| .*allow_merge_on_skipped_pipeline' "$(step repo:alpha:mr-class)"
has "doctor is failing while a step fails" '^failing ' "$(step doctor)"

mv "$dhome/.config/herdr/config.toml" "$tmp/config.toml.off"
djson
has "no toast delivery is missing" '^missing ' "$(step herdr-toast)"
has "its fix names the setting" '\| .*\[ui\.toast\].*delivery = "system"' "$(step herdr-toast)"
mv "$tmp/config.toml.off" "$dhome/.config/herdr/config.toml"

mkdir -p "$tmp/beta/.github/workflows"
printf 'on:\n  pull_request:\n  push:\njobs: {}\n' > "$tmp/beta/.github/workflows/ci.yml"
djson
has "a workflow without a branch filter is failing" '^failing .*ci\.yml' "$(step repo:beta:workflows)"
printf 'on:\n  pull_request:\n    branches: [main]\n  push:\n    branches:\n      - main\njobs: {}\n' > "$tmp/beta/.github/workflows/ci.yml"
djson
has "a workflow filtered on the default branch is done" '^done ' "$(step repo:beta:workflows)"
GHSTUB_REQUIRED=1 djson
# block-mr.sh writes skipped_counts_as_success: false for every GitHub repo, so required checks make it class C
has "a GitHub repo with required checks is class C, failing" '^failing .*class C' "$(step repo:beta:mr-class)"
has "its fix filters the workflows or drops the required check on the work branch" \
  '\| .*filter .*workflows.* on main.*drop the required .*check.* work branch' "$(step repo:beta:mr-class)"

sed -i 's/^gamma: \(.*\)}$/gamma: \1, alias: ALP}/' "$st/repos.yml"
djson
has "two repos with one alias are failing" '^failing .*ALP.*alpha.*gamma' "$(step aliases)"
git -C "$st" checkout -q -- repos.yml

printf 'curation: auto\nspawn: herdr\ncapacity:\n  sessions: 10\n  roles: {repo-lead: 3, scout: 8}\n' > "$st/factory.yml"
git -C "$st" -c user.name=t -c user.email=t@t commit -qam capacity
djson
has "a recent unpushed commit is done" '^done ' "$(step state-push)"
has "capacity: present is done" '^done .*sessions 10' "$(step capacity)"
printf 'x\n' > "$st/old.md"
git -C "$st" add old.md
old=$(( $(date +%s) - 1200 ))
GIT_COMMITTER_DATE="$old +0000" git -C "$st" -c user.name=t -c user.email=t@t commit -qm old
djson
has "a commit unpushed for more than 10 minutes is failing" '^failing .*unpushed' "$(step state-push)"
has "its fix is state-push.sh" '\| .*state-push\.sh' "$(step state-push)"

# --- the text report carries the new checks -------------------------------------------------------------------------
out=$(HOME="$dhome" sh "$bin/factory-doctor.sh" --root "$w" --repo "$tmp/alpha" 2>&1); rc=$?
code "doctor text mode exits 0" 0 "$rc"
has "the text report has python3" '^ok: python3' "$out"
has "the text report has the herdr version" '^ok: herdr 0\.8\.2' "$out"
has "the text report has the toast delivery" '^ok: .*toast' "$out"
has "the text report has this clone's alias" '^ok: .*alias ALP' "$out"

# --- memory over budget: consolidate takes repo: and global scopes, a repo-agent scope gets the daily pass -----------
for d in repos/alpha/memory repos/alpha/agents/scout/memory; do
  mkdir -p "$st/$d"
  i=0; while [ "$i" -lt 41 ]; do : > "$st/$d/l$i.md"; i=$((i + 1)); done
done
out=$(HOME="$dhome" sh "$bin/factory-doctor.sh" --root "$w" --repo "$tmp/alpha" 2>&1)
has "a repo scope over budget is told to consolidate" '^missing: memory over budget in repo:alpha, run factory consolidate repo:alpha' "$out"
has "a repo-agent scope over budget is told the daily pass" \
  '^missing: memory over budget in repo-agent:alpha/scout, .*/claude-factory:memory-daily repo-agent:alpha/scout.*CEO' "$out"
if printf '%s\n' "$out" | grep -q 'consolidate repo-agent:'; then
  printf 'FAIL no consolidate for a repo-agent scope\n'; fail=1
else printf 'PASS no consolidate for a repo-agent scope\n'; fi
rm -rf "$st/repos/alpha/memory" "$st/repos/alpha/agents"

# --- doctor --json from inside a state clone, no --root ------------------------------------------------------------
rm -rf "$uih"
(cd "$st" && HOME="$dhome" sh "$bin/factory-doctor.sh" --json --ui-home "$uih" >/dev/null 2>&1)
has "doctor --json in a state clone finds it without --root" '^done ' "$(step state-repo)"

exit $fail
