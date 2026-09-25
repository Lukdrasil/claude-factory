#!/bin/sh
# The onboarding session (add-repo amendments C4, C5, C7): references/onboard.md names the report path, the stub
# commit, the doctor run, the 11 check ids in order, a sample report whose lines the UI's regexes read, and the end
# sequence; the CEO's "Add a repository" section checks the relayed URL before any command and acts on the report
# file; SKILL.md routes onboard; CONTEXT.md defines the three terms. Every script and reference path onboard.md
# names exists in this repo.
set -u
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
onboard="$repo/skills/factory/references/onboard.md"
ceo="$repo/skills/factory/references/ceo.md"
skill="$repo/skills/factory/SKILL.md"
context="$repo/CONTEXT.md"

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}
has() { grep -Eq -- "$2" "$1"; }

ids='registration alias toolset test-globs tools ci analyzers architecture-tests docs-architecture context-md agents-md'
check_re='^- (done|missing|failing) ([a-z][a-z0-9-]*): (.+)$'
prop_re='^- (P[0-9]+) ([a-z][a-z0-9-]*): (.+)$'
header='An onboarding session reports and proposes; it changes nothing. Send a proposal as a request to have a lead do it.'

# --- onboard.md ------------------------------------------------------------------------------------------------
[ -f "$onboard" ]; check 'references/onboard.md exists' $?
[ -f "$onboard" ] || { exit 1; }

has "$onboard" 'repos/<key>/onboarding\.md'; check 'onboard.md names repos/<key>/onboarding.md' $?
has "$onboard" 'state-commit\.sh -m "chore\(<key>\): onboarding started"'; check 'onboard.md commits the stub through state-commit.sh' $?
has "$onboard" 'state-commit\.sh .*-- repos/<key>/onboarding\.md'; check 'state-commit.sh is given only the report path' $?
has "$onboard" 'factory-doctor\.sh --root [^ ]+ --repo'; check 'onboard.md runs factory-doctor.sh --root --repo' $?
has "$onboard" 'doc-cites\.sh'; check 'onboard.md runs doc-cites.sh' $?
has "$onboard" 'template_version'; check 'onboard.md compares the template_version stamp' $?
has "$onboard" 'skills/architecture-docs/references/templates\.md'; check 'onboard.md names templates.md' $?
has "$onboard" 'skills/setup-guardrails/references/<stack>/README\.md'; check 'onboard.md names the setup-guardrails stack guide' $?
has "$onboard" '"Done when"'; check 'onboard.md judges the analyzers against the "Done when"' $?
has "$onboard" 'skills/architecture-tests/references/<stack>'; check 'onboard.md names the architecture-tests stack reference' $?
has "$onboard" 'FACTORY_ROLE=onboard'; check 'onboard.md says it runs as FACTORY_ROLE=onboard' $?
has "$onboard" '[Aa]llowlist'; check 'onboard.md names the onboard allowlist' $?
has "$onboard" 'no build or test run in the clone'; check 'onboard.md says no build or test run in the clone' $?
has "$onboard" '[Aa]sk the human nothing'; check 'onboard.md asks the human nothing' $?
has "$onboard" 'blocking problem is a `failed` report'; check 'a blocking problem is a failed report' $?
has "$onboard" 'herdr agent prompt ceo "onboard <key> done <d> done <m> missing <f> failing <p> proposals"'
check 'onboard.md sends the C4 done line to the CEO' $?
has "$onboard" '(up to|at most) (3|three) (more )?times'; check 'onboard.md sends the done line again when refused, up to 3 times' $?
has "$onboard" 'herdr tab close "\$HERDR_TAB_ID"'; check 'onboard.md closes its own tab' $?

# the end: report commit, then the done line, then the tab close, in that order
end=$(awk '/^## / { on = ($0 == "## End"); next } on { print }' "$onboard")
[ -n "$end" ]; check 'onboard.md has an ## End section' $?
order=$(printf '%s\n' "$end" | awk '
  /chore\(<key>\): onboarding report/ && !c { c = NR }
  /herdr agent prompt ceo/ && !p { p = NR }
  /herdr tab close/ && !t { t = NR }
  END { print ((c && p && t && c < p && p < t) ? "ok" : "bad") }')
[ "$order" = ok ]; check 'the end commits the report, then prompts the CEO, then closes the tab' $?

# the checks table, in C5 order
table=$(awk '/^## / { on = ($0 == "## Checks"); next } on && /^\| `[a-z-]+` \|/ { sub(/^\| `/, ""); sub(/`.*/, ""); print }' "$onboard" \
  | tr '\n' ' ' | sed 's/ $//')
[ "$table" = "$ids" ]; check "the ## Checks table lists the 11 check ids in C5 order (got: $table)" $?

# the sample report: the fenced block that holds `# Onboarding of`
sample=$(awk '
  /^```/ { if (inf) { if (keep) exit; inf = 0; buf = ""; next } inf = 1; next }
  inf { buf = buf $0 "\n"; if ($0 ~ /^# Onboarding of /) keep = 1; if (keep) { printf "%s", buf; buf = "" } }
' "$onboard")
[ -n "$sample" ]; check 'onboard.md holds a sample report block' $?
printf '%s\n' "$sample" | grep -q '^status: done$'; check 'the sample carries status: done' $?
printf '%s\n' "$sample" | grep -q '^session: '; check 'the sample carries session:' $?
printf '%s\n' "$sample" | grep -Eq '^stack: (dotnet|python|typescript|unknown)$'; check 'the sample carries a stack' $?
first=$(printf '%s\n' "$sample" | awk '/^# Onboarding of / { on = 1; next } on && NF { print; exit }')
[ "$first" = "$header" ]; check 'the first line under the title is the F18 header sentence' $?
has "$onboard" "$header"; check 'onboard.md states the header sentence' $?

section() { # <name> -> the non-empty lines of that section of the sample
  printf '%s\n' "$sample" | awk -v s="## $1" '/^## / { on = ($0 == s); next } on && NF { print }'
}
checks=$(section Checks)
props=$(section Proposals)
[ -n "$checks" ]; check 'the sample has check lines' $?
bad=$(printf '%s\n' "$checks" | grep -Evc "$check_re")
[ "$bad" = 0 ]; check 'every sample check line matches the C5 check regex' $?
got=$(printf '%s\n' "$checks" | sed -E "s/$check_re/\\2/" | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "$ids" ]; check "the sample checks carry the 11 ids in C5 order (got: $got)" $?
printf '%s\n' "$checks" | grep -q ' Fix: '; check 'a sample check line carries a Fix:' $?
printf '%s\n' "$checks" | grep -Eq '^- done '; check 'the sample has a done check' $?
printf '%s\n' "$checks" | grep -Eq '^- missing '; check 'the sample has a missing check' $?
printf '%s\n' "$checks" | grep -Eq '^- failing '; check 'the sample has a failing check' $?
[ -n "$props" ]; check 'the sample has proposal lines' $?
bad=$(printf '%s\n' "$props" | grep -Evc "$prop_re")
[ "$bad" = 0 ]; check 'every sample proposal line matches the C5 proposal regex' $?
areas=$(printf '%s\n' "$props" | sed -E "s/$prop_re/\\2/" | grep -Evc '^(analyzers|architecture-tests|docs|agents-md|ci)$')
[ "$areas" = 0 ]; check 'every sample proposal area is one of the five C5 areas' $?

# every script and skill reference it names exists in this repo
for s in $(grep -Eo '[a-z][a-z0-9-]*\.sh' "$onboard" | sort -u); do
  [ -f "$repo/bin/$s" ]; check "bin/$s exists" $?
done
for d in skills/setup-guardrails/references skills/architecture-tests/references skills/architecture-docs/references/templates.md; do
  [ -e "$repo/$d" ]; check "$d exists" $?
done

! grep -q 'task-new\.sh' "$onboard"; check 'onboard.md never names task-new.sh' $?
! grep -q 'map\.sh new' "$onboard"; check 'onboard.md never names map.sh new' $?
! grep -q 'claude -p' "$onboard"; check 'onboard.md never names claude -p' $?

# --- ceo.md ----------------------------------------------------------------------------------------------------
add=$(awk '/^## / { on = ($0 == "## Add a repository"); next } on { print }' "$ceo")
[ -n "$add" ]; check 'ceo.md has an "Add a repository" section' $?
sec() { printf '%s\n' "$add" | grep -Eq -- "$1"; }
sec '`add repo <url>'; check 'the section takes the line add repo <url>' $?
sec '`onboard repo <key>`'; check 'the section takes the line onboard repo <key>' $?
sec 'factory-add-repo\.sh --root [^ ]+ --clone'; check 'the section runs factory-add-repo.sh --clone' $?
sec 'session-monitor\.sh --step onboard --scope <key>'; check 'the section runs session-monitor.sh --step onboard --scope' $?
sec '[Ee]xit 4'; check 'the section handles exit 4' $?
sec '`add-repo-<key>`'; check 'the confirm ask id is add-repo-<key>' $?
sec '`add-repo-<key>-error`'; check 'the error notice id is add-repo-<key>-error' $?
sec 'before any command'; check 'the URL is checked before any command' $?
sec '\^\[A-Za-z0-9\._~:/@\+-\]\+\$'; check 'the section names the C2 URL charset' $?
sec 'start(s)? with `-`'; check 'the section refuses a leading -' $?
sec 'waits for a free session'; check 'full capacity is one notice ask' $?
! sec '[Rr]etry|again after the next freed lease'; check 'full capacity has no retry loop' $?
sec 'onboarding\.md' && sec '`status:`'; check 'the done line is checked against the report file status' $?
! sec 'capacity\.sh release'; check 'the CEO releases nothing for an onboarding session' $?
intake=$(awk '/^## / { on = ($0 == "## Intake"); next } on && /^2\. / { p = 1 } on && /^3\. / { p = 0 } p { print }' "$ceo")
printf '%s\n' "$intake" | grep -q 'onboarding\.md' && printf '%s\n' "$intake" | grep -q '## Summary'
check 'Intake routing reads the ## Summary of onboarding.md' $?

# --- SKILL.md --------------------------------------------------------------------------------------------------
grep -Eq '^\| `onboard` \|.*`references/onboard\.md` \|$' "$skill"; check 'SKILL.md routes onboard to references/onboard.md' $?
grep -Eq '^\| `add-repo` \|.*--clone' "$skill"; check 'SKILL.md add-repo mentions --clone' $?

# --- CONTEXT.md ------------------------------------------------------------------------------------------------
for t in 'onboarding session' 'onboarding report' 'clones directory'; do
  grep -q "^- \*\*$t\*\*: " "$context"; check "CONTEXT.md defines $t" $?
done

# --- no en or em dash in the files of this change ---------------------------------------------------------------
dash=$(printf '\342\200\224|\342\200\223')
! grep -Eq "$dash" "$onboard" "$ceo" "$skill" "$context" "$0"; check 'no U+2013 or U+2014 in the changed files' $?

# sim F38: after the clone the CEO followed add-repo.md's toolset offer and doctor, asked in the terminal and never
# started the onboarding; a missing toolset is the onboarding's toolset check, so step 3 goes on to step 4 anyway
has "$ceo" 'no toolsets/<stack>\.md.*step 4|step 4.*no toolsets/<stack>\.md'; check 'a missing toolset still goes on to the onboarding' $?
# sim F39: the onboarding session of a fresh clone stops at Claude Code's folder trust dialog, and trusting runs the
# clone's own .claude/ settings and hooks, so the human decides: one confirm ask, the answer typed by send-keys
has "$ceo" 'still at a dialog'; check 'step 4 handles a session still at a dialog' $?
has "$ceo" 'add-repo-<key>-trust'; check 'the trust dialog is the confirm ask add-repo-<key>-trust' $?
has "$ceo" '\.claude/.*\.mcp\.json|\.mcp\.json.*\.claude/'; check 'the trust ask names the clone .claude/ and .mcp.json' $?
has "$ceo" 'herdr agent send-keys onboard_<key>'; check 'the answer goes to the dialog by send-keys' $?
exit "$fail"
