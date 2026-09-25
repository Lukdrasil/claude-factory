#!/bin/sh
# The setup flows in a browser: the fixture of tests/ui-fixture.sh with an init session holding the confirm ask of
# the real factory-init.sh preview and a doctor session holding one round with a question per tool, then three
# servers in turn: over the fixture state repo, with only /ui before a factory root exists, and over the state repo
# factory-init.sh --yes made, with a clone registered through factory-add-repo.sh, a CEO session, an onboarding report
# and a pending add-repo file for the Repositories section. tests/ui-setup.test.js drives
# each one in the Playwright container of tests/ui-page.test.sh and prints its own PASS and FAIL lines. Without
# Docker it prints `SKIP ui-setup: no docker`.
set -u
unset FACTORY_UI_HOME FACTORY_UI_CONTAINER WORK_DIR
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$repo/bin"

if ! docker info >/dev/null 2>&1; then
  echo 'SKIP ui-setup: no docker'
  exit 0
fi

tmp=$(mktemp -d)
name="cf-ui-setup-$$"
image="claude-factory-ui:test-$$"
pw_version=1.63.0
pw="cf-ui-playwright:$pw_version"
cleanup() {
  FACTORY_UI_CONTAINER=$name HERDR_ENV=1 timeout 120 sh "$bin/ui-down.sh" >/dev/null 2>&1
  docker rm -f "$name" "$name-free" >/dev/null 2>&1
  docker image rm "$image" >/dev/null 2>&1
  chmod -R u+rwx "$tmp" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

. "$repo/tests/ui-fixture.sh"
unset WORK_DIR

# --- the references ------------------------------------------------------------------------------------------------
refs="$repo/skills/factory/references"
has 'init.md asks the browser UI question'                    '[Bb]rowser UI' "$(cat "$refs/init.md")"
has 'init.md offers the browser UI only inside herdr'         'HERDR_ENV' "$(cat "$refs/init.md")"
has 'init.md turns the answer into --ui docker'               '--ui docker' "$(cat "$refs/init.md")"
has 'init.md restarts the UI with the state repo after the apply step' 'ui-up\.sh --state' "$(cat "$refs/init.md")"
has 'init.md puts the printed diff into the confirm ask as a fenced block' '```|[Ff]enced' "$(cat "$refs/init.md")"
has 'add-repo.md puts the printed diff into the confirm ask as a fenced block' '```|[Ff]enced' "$(cat "$refs/add-repo.md")"
has 'doctor.md offers the fixes as one round'                 '[Oo]ne round' "$(cat "$refs/doctor.md")"
has 'doctor.md asks a question per tool'                      '[Qq]uestion per (missing )?tool' "$(cat "$refs/doctor.md")"
hasnt 'doctor.md no longer asks one ask per missing tool'     'One ask \(`_shared/ask\.md`\) per missing tool' "$(cat "$refs/doctor.md")"

# --- the image from this tree, so the page under test is the one in ui/wwwroot ---------------------------------------
timeout 15m docker build -q -t "$image" "$repo/ui" > "$tmp/build.out" 2>&1 \
  || { bad "building $image failed: $(tail -n 20 "$tmp/build.out")"; exit 1; }
if ! docker image inspect "$pw" >/dev/null 2>&1; then
  printf 'FROM mcr.microsoft.com/playwright:v%s-noble\nRUN npm install -g playwright-core@%s\nENV NODE_PATH=/usr/lib/node_modules\n' \
    "$pw_version" "$pw_version" | timeout 15m docker build -q -t "$pw" - >/dev/null \
    || { bad "the Playwright image $pw could not be built"; exit 1; }
fi

# --- the init and doctor sessions and their asks -------------------------------------------------------------------
root="$tmp/root"
settings="$tmp/settings.json"
printf '{}\n' > "$settings"
sh "$bin/factory-init.sh" --root "$root" --settings "$settings" --spawn herdr --ui docker > "$tmp/init.out" 2>&1
is 'factory-init.sh without --yes exits 3 with its diff'     "$?" 3
has 'factory-init.sh writes setup/doctor.json into the UI home' '"steps"' "$(cat "$ui/setup/doctor.json" 2>/dev/null)"

sh "$bin/ui-session.sh" --session s-doctor --pane w1:p8 --flow doctor --task none --step 'doctor: offer the fixes' \
  || bad 'ui-session.sh s-doctor'
{
  printf -- '---\nask: apply\ntask: none\nflow: init\nstep: init: confirm the diff\nstatus: open\n---\n\n'
  printf '%s\n\n```diff\n' '❓ **Q1** - **Apply the init diff?**: factory-init.sh printed it and wrote nothing.'
  sed '/^pending - rerun with --yes to apply$/d' "$tmp/init.out"
  printf '```\n\n  **A** yes\n  **B** no\n\n➡️ **A**: the state repo, factory.yml and the settings as shown.\n'
} | HERDR_PANE_ID=w1:p9 sh "$bin/ui-ask.sh" --session s-init >/dev/null || bad 'ui-ask.sh s-init apply'
has 'ui-ask.sh registers the unregistered init session with its pane' '^pane: w1:p9$' "$(cat "$ui/sessions/s-init/session.md" 2>/dev/null)"
HERDR_PANE_ID=w1:p7 sh "$bin/ui-ask.sh" --session s-doctor >/dev/null <<'EOF' || bad 'ui-ask.sh s-doctor tools'
---
ask: tools
task: none
flow: doctor
step: doctor: offer the fixes
status: open
---

❓ **Q1** - **Install herdr?**: `missing: spawn: herdr, but herdr is not on PATH`.
  **A** yes
  **B** no

➡️ **A**: install herdr from https://herdr.dev.

---

❓ **Q2** - **Install dotnet-crap?**: `missing: dotnet-crap on PATH`.
  **A** yes
  **B** no

➡️ **A**: dotnet tool install -g Crap4DotNet.
EOF
has 'ui-ask.sh leaves the pane of a registered session as it was' '^pane: w1:p8$' "$(cat "$ui/sessions/s-doctor/session.md" 2>/dev/null)"

browse() { # <phase> <state dir or ''>: tests/ui-setup.test.js against the current server, its lines on stdout
  port=$(cat "$ui/port" 2>/dev/null)
  mount=''
  [ -z "$2" ] || mount="-v $2:$2"
  timeout 15m docker run --rm --network host --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -e PHASE="$1" -e BASE="http://127.0.0.1:$port" -e TOKEN="$(cat "$ui/token")" -e PRINTED="$(head -n1 "$tmp/up.out")" \
    -e UI="$ui" -e STATE="$2" -e ROOT="$root" -v "$ui:$ui" $mount \
    -v "$repo/tests/ui-setup.test.js:/t/ui-setup.test.js:ro" "$pw" node /t/ui-setup.test.js > "$tmp/page-$1.out" 2>&1
  rc=$?
  cat "$tmp/page-$1.out"
  is "the browser checks of phase $1 exit 0"                  "$rc" 0
  has "the browser checks of phase $1 ran"                    '^PASS |^FAIL ' "$(cat "$tmp/page-$1.out")"
}
cid() { docker inspect -f '{{.Id}}' "$name" 2>/dev/null; }
label() { docker inspect -f "{{index .Config.Labels \"$1\"}}" "$name" 2>/dev/null; }
mounts() { docker inspect -f '{{range .Mounts}}{{.Destination}} {{end}}' "$name" 2>/dev/null; }

# --- phase fixture: the server over the fixture state repo ---------------------------------------------------------
up --state "$state1"; rc=$?
is 'ui-up.sh --state over the fixture exits 0'                "$rc" 0
[ "$rc" = 0 ] || { sed 's/^/  up: /' "$tmp/up.err" | tail -n 30; exit 1; }
is 'the server runs the image of this checkout'               "$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)" "$image"
token=$(cat "$ui/token")
ready "$(cat "$ui/port")" || { bad "the server never answered: $(docker logs "$name" 2>&1 | tail -n 20)"; exit 1; }
browse fixture ''

# --- phase bare: no factory root yet, the server with only /ui -------------------------------------------------------
mkdir -p "$tmp/nowhere"
( cd "$tmp/nowhere" && HERDR_ENV=1 timeout 120 sh "$bin/ui-up.sh" --state "$tmp/nowhere" ) > /dev/null 2>&1
isnt 'ui-up.sh --state over a dir with no repos.yml still fails' "$?" 0
id_fixture=$(cid)
( cd "$tmp/nowhere" && up ); rc=$?
is 'ui-up.sh with no state repo to resolve exits 0'           "$rc" 0
[ "$rc" = 0 ] || sed 's/^/  up: /' "$tmp/up.err" | tail -n 10
has 'it prints the URL with the token'                        "^http://127\\.0\\.0\\.1:[0-9]+/#.*$token" "$(cat "$tmp/up.out")"
isnt 'the fixture container was recreated'                    "$(cid)" "$id_fixture"
has 'the container mounts /ui'                                '(^| )/ui ' "$(mounts) "
hasnt 'the container mounts no /state'                        '(^| )/state ' "$(mounts) "
is 'its cf.state label is empty'                              "$(label cf.state)" ''
is 'the token survived the recreation'                        "$(cat "$ui/token")" "$token"
if [ "$rc" = 0 ] && ready "$(cat "$ui/port")"; then
  is 'GET /api/setup with only /ui is 200'                    "$(http "$(cat "$ui/port")" /api/setup -H "X-Factory-Token: $token")" 200
  has 'the setup has no repos.yml'                            '"reposYml":null' "$(cat "$tmp/body")"
  is 'GET /api/board with only /ui is 200'                    "$(http "$(cat "$ui/port")" /api/board -H "X-Factory-Token: $token")" 200
  is 'the board is empty'                                     "$(cat "$tmp/body")" '[]'
  is 'GET /api/sessions with only /ui is 200'                 "$(http "$(cat "$ui/port")" /api/sessions -H "X-Factory-Token: $token")" 200
  has 'the init session is listed'                            '"sid":"s-init"' "$(cat "$tmp/body")"
  browse bare ''
else
  bad 'the server with only /ui never answered, phase bare skipped'
fi

# --- phase state: the answered confirm applied, the server recreated over the new state repo -----------------------
sh "$bin/factory-init.sh" --root "$root" --settings "$settings" --spawn herdr --ui docker --yes > "$tmp/apply.out" 2>&1
is 'factory-init.sh --yes exits 0'                            "$?" 0
sed -i "s/^ui_port:.*/ui_port: $port1/" "$root/state/factory.yml"
id_bare=$(cid)
up --state "$root/state"; rc=$?
is 'ui-up.sh --state over the state repo factory-init.sh made exits 0' "$rc" 0
[ "$rc" = 0 ] || sed 's/^/  up: /' "$tmp/up.err" | tail -n 10
isnt 'the container was recreated'                            "$(cid)" "$id_bare"
has 'the container mounts /state'                             '(^| )/state ' "$(mounts) "
is 'its cf.state label is the new state repo'                 "$(label cf.state)" "$root/state"

mkdir -p "$tmp/demo"
git -C "$tmp/demo" init -q
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' > "$tmp/demo/Demo.csproj"
git -C "$tmp/demo" remote add origin https://example.invalid/acme/demo.git
git -C "$tmp/demo" -c user.name=t -c user.email=t@t add -A
git -C "$tmp/demo" -c user.name=t -c user.email=t@t commit -qm demo
sh "$bin/factory-add-repo.sh" --root "$root" --repo "$tmp/demo" --yes > "$tmp/add.out" 2>&1
is 'factory-add-repo.sh --yes exits 0'                        "$?" 0

# the Repositories section: a CEO to send to, an onboarding report of demo (C5) and a pending add-repo file (C3)
sh "$bin/ui-session.sh" --session s-ceo --pane w1:p9 --flow ceo --task ceo || bad 'ui-session.sh registers the CEO'
{
  printf -- '---\nrepo: demo\nstatus: done\nat: 2026-09-25T12:00:00Z\nsession: 5f1c\nstack: dotnet\n---\n# Onboarding of demo\n\n'
  printf 'An onboarding session reports and proposes; it changes nothing. Send a proposal as a request to have a lead do it.\n\n'
  printf '## Summary\nA **dotnet** fixture.\n\n## Checks\n- done registration: demo is in repos.yml\n'
  printf -- '- failing ci: <script>window.pwned = 1</script> never runs dotnet test Fix: add a test job\n\n'
  printf '## Proposals\n- P1 ci: add a CI job that runs "dotnet test"\n'
} > "$root/state/repos/demo/onboarding.md"
mkdir -p "$ui/setup/add-repo"
printf '{"at":"2026-09-25T12:10:00Z","key":"fresh","url":"https://example.test/g/fresh.git","path":"/c/fresh","state":"pending","detail":"/c/fresh"}\n' \
  > "$ui/setup/add-repo/fresh.json"

if [ "$rc" = 0 ] && ready "$(cat "$ui/port")"; then
  is 'GET /api/setup over the new state repo is 200'          "$(http "$(cat "$ui/port")" /api/setup -H "X-Factory-Token: $token")" 200
  has 'the setup carries the toolset of demo'                 '"repo":"demo"' "$(cat "$tmp/body")"
  browse state "$root/state"
else
  bad 'the server over the new state repo never answered, phase state skipped'
fi

exit $fail
