#!/bin/sh
# Characterization of the setup scripts the UI setting extends: factory-init.sh prints its diff and exits 3
# without --yes, applies with --yes and has nothing to do on a rerun; factory-doctor.sh reports the spawn mode
# and exits 0; session-start.sh gives a registered clone its identity line and an unregistered one the nudge.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset HARNESS_WORKER HERDR_ENV HERDR_PANE_ID DASHBOARD_URL
export FACTORY_UI_HOME="$tmp/ui"

fail=0
has() { # <what> <extended regex> <text>
  if printf '%s\n' "$3" | grep -Eq "$2"; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
code() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s (exit %s)\n' "$1" "$3"; fail=1; fi
}

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

exit $fail
