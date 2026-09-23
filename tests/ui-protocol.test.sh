#!/bin/sh
# The ask protocol of the Factory UI over a throwaway UI home, state repo and settings file: ui-ask.sh writes an
# ask atomically, validates it and closes it; ui-session.sh creates then updates session.md; solve-next.sh --ui
# records its step; factory-init.sh --ui docker shows ui:, ui_port: and promptSuggestionEnabled in its diff;
# factory-doctor.sh reports Docker, herdr and that setting; session-start.sh registers a session only with
# ui: docker and HERDR_ENV=1; and skills/_shared/ask.md is the one skill file that names AskUserQuestion.
set -u
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$repo/bin"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unset HARNESS_WORKER HERDR_ENV HERDR_PANE_ID DASHBOARD_URL

fail=0
pass() { printf 'PASS %s\n' "$1"; }
flunk() { printf 'FAIL %s\n' "$1"; fail=1; }
has() { # <what> <extended regex> <text>
  if printf '%s\n' "$3" | grep -Eq "$2"; then pass "$1"; else flunk "$1"; fi
}
hasnt() { # <what> <extended regex> <text>
  if printf '%s\n' "$3" | grep -Eq "$2"; then flunk "$1"; else pass "$1"; fi
}

ui="$tmp/ui"
mkdir -p "$ui"
printf '7272\n' > "$ui/port"
export FACTORY_UI_HOME="$ui"
sid=0b7a1c2e-5f3d-4e6a-9c1b-2d3e4f5a6b7c

ask_md() { # <ask id> [<key to leave out>]
  printf -- '---\n'
  for k in ask task flow step status; do
    [ "$k" != "${2:-}" ] || continue
    case "$k" in
      ask) printf 'ask: %s\n' "$1" ;;
      task) printf 'task: T-204\n' ;;
      flow) printf 'flow: solve\n' ;;
      step) printf 'step: Step 4 of 16\n' ;;
      status) printf 'status: open\n' ;;
    esac
  done
  printf -- '---\n\n## Round 1\n\nQ1. Which port?\n  a) 7171 (recommended)\n  b) 8080\n'
}

# --- ui-ask.sh writes the ask and prints its URL ---------------------------------------------------------------
asks="$ui/sessions/$sid/asks"
out=$(ask_md q1 | sh "$bin/ui-ask.sh" --session "$sid" 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "ui-ask.sh exits 0 on a valid ask" || flunk "ui-ask.sh exits 0 on a valid ask (exit $rc: $out)"
if [ -f "$asks/q1.md" ] && [ "$(cat "$asks/q1.md")" = "$(ask_md q1)" ]; then
  pass "the ask lands verbatim in sessions/<sid>/asks/q1.md"
else
  flunk "the ask lands verbatim in sessions/<sid>/asks/q1.md"
fi
has "the ask URL is printed with the port of the UI home and no token" \
  "^http://127\.0\.0\.1:7272/\?ask=$sid/q1\$" "$out"
first=$(ls -i "$asks/q1.md" 2>/dev/null | awk '{ print $1 }')
ask_md q1 | sh "$bin/ui-ask.sh" --session "$sid" >/dev/null 2>&1
second=$(ls -i "$asks/q1.md" 2>/dev/null | awk '{ print $1 }')
if [ -n "$first" ] && [ -n "$second" ] && [ "$first" != "$second" ]; then
  pass "a rewrite replaces the ask through a rename, not in place"
else
  flunk "a rewrite replaces the ask through a rename, not in place (inode $first then $second)"
fi
left=$(ls -A "$asks" 2>/dev/null | grep -vx 'q1.md')
[ -z "$left" ] && pass "no temp file is left beside the ask" || flunk "no temp file is left beside the ask ($left)"

# --- a missing frontmatter key, or an ask id that is not [a-z0-9-]+, is refused -------------------------------
for k in ask task flow step status; do
  ask_md "no-$k" "$k" | sh "$bin/ui-ask.sh" --session "$sid" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ ! -e "$asks/no-$k.md" ]; then
    pass "an ask without $k: exits non-zero and writes nothing"
  else
    flunk "an ask without $k: exits non-zero and writes nothing (exit $rc)"
  fi
done
ask_md '../escape' | sh "$bin/ui-ask.sh" --session "$sid" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$ui/sessions/$sid/escape.md" ]; then
  pass "an ask id outside [a-z0-9-]+ exits non-zero and writes nothing"
else
  flunk "an ask id outside [a-z0-9-]+ exits non-zero and writes nothing (exit $rc)"
fi
ask_md 'Bad_Id' | sh "$bin/ui-ask.sh" --session "$sid" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && [ ! -e "$asks/Bad_Id.md" ]; then
  pass "an ask id with upper case or _ exits non-zero and writes nothing"
else
  flunk "an ask id with upper case or _ exits non-zero and writes nothing (exit $rc)"
fi

# --- --close sets status: answered and keeps the rest -----------------------------------------------------------
ask_md q2 | sh "$bin/ui-ask.sh" --session "$sid" >/dev/null 2>&1
sh "$bin/ui-ask.sh" --session "$sid" --close q2 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "--close exits 0" || flunk "--close exits 0 (exit $rc)"
closed=$(cat "$asks/q2.md" 2>/dev/null)
has "--close sets status: answered" '^status: answered$' "$closed"
hasnt "--close leaves no status: open" '^status: open$' "$closed"
if [ "$(printf '%s\n' "$closed" | sed 's/^status: answered$/status: open/')" = "$(ask_md q2)" ]; then
  pass "--close changes nothing but the status line"
else
  flunk "--close changes nothing but the status line"
fi
has "--close leaves the other ask open" '^status: open$' "$(cat "$asks/q1.md" 2>/dev/null)"

# --- ui-session.sh creates, then updates, session.md ------------------------------------------------------------
smd="$ui/sessions/$sid/session.md"
sh "$bin/ui-session.sh" --session "$sid" --pane p-3 --flow solve --task T-204 --step 'Step 3 of 16' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "ui-session.sh exits 0 on create" || flunk "ui-session.sh exits 0 on create (exit $rc)"
s=$(cat "$smd" 2>/dev/null)
has "session.md opens with a frontmatter fence" '^---$' "$(printf '%s\n' "$s" | head -n1)"
has "session.md records sid"  "^sid: \"?$sid\"?\$" "$s"
has "session.md records pane" '^pane: "?p-3"?$' "$s"
has "session.md records flow" '^flow: "?solve"?$' "$s"
has "session.md records task" '^task: "?T-204"?$' "$s"
has "session.md records step" '^step: "?Step 3 of 16"?$' "$s"
has "session.md records updated" '^updated: .+' "$s"
sh "$bin/ui-session.sh" --session "$sid" --step 'Step 4 of 16' >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && pass "ui-session.sh exits 0 on update" || flunk "ui-session.sh exits 0 on update (exit $rc)"
s=$(cat "$smd" 2>/dev/null)
has "an update sets the new step" '^step: "?Step 4 of 16"?$' "$s"
n=$(printf '%s\n' "$s" | grep -c '^step:')
[ "$n" -eq 1 ] && pass "an update leaves one step: line" || flunk "an update leaves one step: line ($n)"
has "an update keeps the pane" '^pane: "?p-3"?$' "$s"
has "an update keeps the flow" '^flow: "?solve"?$' "$s"
has "an update keeps the task" '^task: "?T-204"?$' "$s"

# --- the new scripts use no node -------------------------------------------------------------------------------
for f in ui-ask.sh ui-session.sh; do
  if [ -f "$bin/$f" ] && ! grep -qw node "$bin/$f"; then pass "$f exists and uses no node"; else flunk "$f exists and uses no node"; fi
done

# --- solve-next.sh --ui records its step through ui-session.sh ------------------------------------------------
root="$tmp/factory"
state="$root/state"
mkdir -p "$state/repos/demo/tasks"
cat > "$state/repos/demo/tasks/T-001.md" <<'EOF'
---
id: T-001
repo: demo
status: draft
---

# Goal
feat(demo): the parent
EOF
sid2=1c2d3e4f-0000-4000-8000-000000000002
out=$(sh "$bin/solve-next.sh" T-001 --state "$state" --ui "$sid2" 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "solve-next.sh --ui exits 0" || flunk "solve-next.sh --ui exits 0 (exit $rc: $out)"
has "solve-next.sh --ui still prints its step" '^## Step 3 of 16: triage T-001' "$out"
has "solve-next.sh --ui records its step in session.md" '^step: "?Step 3 of 16' \
  "$(cat "$ui/sessions/$sid2/session.md" 2>/dev/null)"
before=$(ls "$ui/sessions" 2>/dev/null)
sh "$bin/solve-next.sh" T-001 --state "$state" >/dev/null 2>&1
[ "$(ls "$ui/sessions" 2>/dev/null)" = "$before" ] \
  && pass "solve-next.sh without --ui writes no session" || flunk "solve-next.sh without --ui writes no session"

# --- factory-init.sh --ui ----------------------------------------------------------------------------------------
settings="$tmp/settings.json"
printf '{\n  "theme": "dark"\n}\n' > "$settings"
out=$(sh "$bin/factory-init.sh" --root "$tmp/init" --settings "$settings" --spawn manual --ui docker 2>&1); rc=$?
[ "$rc" -eq 3 ] && pass "init --ui docker without --yes exits 3" || flunk "init --ui docker without --yes exits 3 (exit $rc: $out)"
has "the diff adds ui: docker to factory.yml"  '^\+ui: docker$' "$out"
has "the diff adds ui_port: 7171 to factory.yml" '^\+ui_port: 7171$' "$out"
has "the diff sets promptSuggestionEnabled false in the settings" '^\+.*"promptSuggestionEnabled": false' "$out"
[ ! -e "$tmp/init/state" ] && [ "$(cat "$settings")" = "$(printf '{\n  "theme": "dark"\n}')" ] \
  && pass "init without --yes writes nothing" || flunk "init without --yes writes nothing"
out=$(sh "$bin/factory-init.sh" --root "$tmp/init" --settings "$settings" --spawn manual --ui docker --yes 2>&1); rc=$?
[ "$rc" -eq 0 ] && pass "init --ui docker --yes exits 0" || flunk "init --ui docker --yes exits 0 (exit $rc: $out)"
has "factory.yml carries ui: docker" '^ui: docker$' "$(cat "$tmp/init/state/factory.yml" 2>/dev/null)"
has "factory.yml carries ui_port: 7171" '^ui_port: 7171$' "$(cat "$tmp/init/state/factory.yml" 2>/dev/null)"
has "the settings file carries promptSuggestionEnabled false" '"promptSuggestionEnabled": false' "$(cat "$settings")"
has "the settings file keeps its other keys" '"theme": "dark"' "$(cat "$settings")"
settings_off="$tmp/settings-off.json"
out=$(sh "$bin/factory-init.sh" --root "$tmp/init-off" --settings "$settings_off" --spawn manual --ui off 2>&1)
has "init --ui off writes ui: off" '^\+ui: off$' "$out"
hasnt "init --ui off leaves promptSuggestionEnabled alone" 'promptSuggestionEnabled' "$out"

# --- factory-doctor.sh with ui: docker -------------------------------------------------------------------------
droot="$tmp/doc"
mkdir -p "$droot/state" "$tmp/stub" "$tmp/home/.claude"
git init -q "$tmp/clone"
git -C "$tmp/clone" remote add origin https://forge.test/acme/clone.git
printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/docker"
printf '#!/bin/sh\nexit 0\n' > "$tmp/stub/herdr"
chmod +x "$tmp/stub/docker" "$tmp/stub/herdr"
doctor() { HOME="$tmp/home" PATH="$tmp/stub:$PATH" sh "$bin/factory-doctor.sh" --root "$droot" --repo "$tmp/clone" 2>&1; }
printf 'curation: auto\nspawn: manual\nui: docker\nui_port: 7171\n' > "$droot/state/factory.yml"
printf '{ "promptSuggestionEnabled": false }\n' > "$tmp/home/.claude/settings.json"
out=$(doctor)
has "doctor reports Docker" '^ok: .*[Dd]ocker' "$out"
has "doctor reports herdr for the UI" '^ok: .*herdr' "$out"
has "doctor reports promptSuggestionEnabled false" '^ok: .*promptSuggestionEnabled' "$out"
printf '{ "promptSuggestionEnabled": true }\n' > "$tmp/home/.claude/settings.json"
has "doctor flags promptSuggestionEnabled true" '^missing: .*promptSuggestionEnabled' "$(doctor)"
printf 'curation: auto\nspawn: manual\nui: off\n' > "$droot/state/factory.yml"
hasnt "doctor with ui: off says nothing about promptSuggestionEnabled" 'promptSuggestionEnabled' "$(doctor)"

# --- session-start.sh registers the session only with ui: docker and HERDR_ENV=1 ------------------------------
wd="$tmp/wd"
mkdir -p "$wd/state"
git init -q "$tmp/prod"
printf 'prod: {url: "https://forge.test/acme/prod.git", default_branch: main, path: "%s"}\n' "$tmp/prod" > "$wd/state/repos.yml"
git init -q "$tmp/stranger"
start() { # <session id> <cwd> [env assignments...]
  s_sid=$1 s_cwd=$2; shift 2
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"SessionStart"}' "$s_sid" "$s_cwd" \
    | env HOME="$tmp/home" WORK_DIR="$wd" "$@" sh "$bin/session-start.sh" >/dev/null 2>&1
}
printf 'spawn: manual\nui: docker\n' > "$wd/state/factory.yml"
start s-reg "$tmp/prod" HERDR_ENV=1 HERDR_PANE_ID=pane-7
s=$(cat "$ui/sessions/s-reg/session.md" 2>/dev/null)
has "ui: docker in herdr registers the session" '^sid: "?s-reg"?$' "$s"
has "the registration carries the herdr pane" '^pane: "?pane-7"?$' "$s"
start s-noherdr "$tmp/prod" HERDR_PANE_ID=pane-8
[ ! -e "$ui/sessions/s-noherdr" ] && pass "no HERDR_ENV, no registration" || flunk "no HERDR_ENV, no registration"
start s-stranger "$tmp/stranger" HERDR_ENV=1 HERDR_PANE_ID=pane-9
[ ! -e "$ui/sessions/s-stranger" ] && pass "an unregistered clone is not registered" || flunk "an unregistered clone is not registered"
printf 'spawn: manual\nui: off\n' > "$wd/state/factory.yml"
start s-off "$tmp/prod" HERDR_ENV=1 HERDR_PANE_ID=pane-10
[ ! -e "$ui/sessions/s-off" ] && pass "ui: off, no registration" || flunk "ui: off, no registration"

# --- the skills name AskUserQuestion in one place ------------------------------------------------------------
if [ -f "$repo/skills/_shared/ask.md" ] && grep -q AskUserQuestion "$repo/skills/_shared/ask.md"; then
  pass "skills/_shared/ask.md names AskUserQuestion"
else
  flunk "skills/_shared/ask.md names AskUserQuestion"
fi
others=$(cd "$repo" && grep -rl AskUserQuestion skills | grep -v _shared/ask.md)
[ -z "$others" ] && pass "no other skill file names AskUserQuestion" || flunk "no other skill file names AskUserQuestion: $(echo $others)"
for f in skills/factory/SKILL.md skills/factory/references/approve.md skills/factory/references/doctor.md \
  skills/factory/references/herd.md skills/factory/references/add-repo.md skills/factory/references/curate.md \
  skills/factory/references/init.md skills/factory/references/solve-quick.md skills/herdr/SKILL.md; do
  grep -q '_shared/ask\.md' "$repo/$f" && pass "$f points to _shared/ask.md" || flunk "$f points to _shared/ask.md"
done
grep -Eq 'solve-next\.sh .*--ui' "$repo/skills/factory/references/solve.md" \
  && pass "solve.md passes --ui to solve-next.sh" || flunk "solve.md passes --ui to solve-next.sh"
for term in ask 'answer file' relay 'UI home'; do
  grep -qi "\*\*$term\*\*" "$repo/CONTEXT.md" 2>/dev/null && pass "CONTEXT.md defines $term" || flunk "CONTEXT.md defines $term"
done

exit $fail
