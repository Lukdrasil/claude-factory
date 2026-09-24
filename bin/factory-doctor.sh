#!/bin/sh
# A report over one product clone in the standalone factory (ADR-0049): the state remote and its credentials,
# registration (one key per clone), toolset, the tools the toolset binds and what they need (a coverage collector,
# a .NET 8 runtime for dotnet-crap), docs/architecture, then the machine checks below for this clone. One line per
# check, `ok: ...`, `missing: <what>, <fix>` or `failing: <what>, <fix>`. Always exit 0: the skill offers the fixes
# to the human, the report gates nothing.
#
# --json walks the steps of the Setup tab instead, machine wide and for every registered repo, and writes them to
# <ui home>/setup/doctor.json (`{at, root, steps: [{id, state: done|missing|failing, detail, fix}]}`, the path on
# stdout); init and add-repo run it after every run. It reads the machine and the forges and writes nothing else:
# a fix is text, applying it is a confirm ask of the session.
#
#   factory-doctor.sh [--root <dir>] [--repo <clone-dir>]
#   factory-doctor.sh --json [--root <dir>] [--ui-home <dir>]
#
# The root is --root, else the parent of the state clone the cwd is in, else WORK_DIR (--json: else ~/factory).
set -eu

root='' repo='' json=0 uihome=''
die() { printf 'factory-doctor: %s\n' "$1" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root|--repo|--ui-home)
      [ $# -ge 2 ] || die "$1 needs a value"
      case "$1" in --root) root=$2 ;; --repo) repo=$2 ;; --ui-home) uihome=$2 ;; esac
      shift 2 ;;
    --json) json=1; shift ;;
    *) die "unknown argument '$1'" ;;
  esac
done
state=''
if [ -z "$root" ]; then
  if cwd_top=$(git rev-parse --show-toplevel 2>/dev/null) && [ -f "$cwd_top/repos.yml" ]; then
    state=$cwd_top root=$(dirname -- "$cwd_top")
  elif [ -n "${WORK_DIR:-}" ]; then root=$WORK_DIR
  elif [ "$json" = 1 ]; then root="$HOME/factory"
  else die "--root <dir> is required"; fi
fi
[ -n "$repo" ] || repo=$(pwd)
root=$(printf '%s' "$root" | sed 's/\\/\//g; s:/*$::')
[ -n "$state" ] || state="$root/state"
plugin=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$plugin/bin/lib-tasks.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

ok() { echo "ok: $1"; }
missing() { echo "missing: $1, $2"; }
# one check: printed as a line of the report, or with --json a row of the steps file
step() { # <id> <done|missing|failing> <detail> [<fix>]
  if [ "$json" = 1 ]; then
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$(flat "$3")" "$(flat "${4:-}")" >> "$tmp/steps"
  else
    case "$2" in
      done) ok "$3" ;;
      missing) missing "$3" "${4:-}" ;;
      *) echo "failing: $3, ${4:-}" ;;
    esac
  fi
}
flat() { printf '%s' "$1" | tr '\t\n\r' '   ' | tr -d '\000-\037'; }

# --- state remote + credentials ----------------------------------------------------------------------------------
# 2026-09-07: a state repo with no remote pushes nowhere (every WIP push of a block "succeeded" locally), and one
# with an https remote and no stored credential prompts inside a hook, where nobody answers. Only checked when the
# root has a state clone at all; a local-only state repo is a choice, so the miss names it as one.
state_remote_report() {
if [ -d "$state/.git" ]; then
  if surl=$(git -C "$state" remote get-url origin 2>/dev/null) && [ -n "$surl" ]; then
    ok "state remote $surl"
    case "$surl" in
      http://*@*|https://*@*) ok "credentials for the state remote (in its url)" ;;
      http://*|https://*)
        if [ -n "$(git -C "$state" config --get credential.helper 2>/dev/null || :)" ]; then
          ok "credentials for the state remote (credential.helper)"
        elif [ -f "${HOME:-/nonexistent}/.git-credentials" ]; then
          ok "credentials for the state remote (~/.git-credentials)"
        elif [ -n "${GIT_ASKPASS:-}" ]; then
          ok "credentials for the state remote (GIT_ASKPASS)"
        else
          missing "credentials for the http(s) state remote" \
            "configure a credential helper for the state remote (e.g. git config credential.helper store, or GIT_ASKPASS with the forge token)"
        fi ;;
    esac
  else
    missing "state remote" "add one (git -C $state remote add origin <url>) or accept a local-only state repo"
  fi
fi
}

# --- the machine and the registered repos (the Setup tab) -----------------------------------------------------------
herdr_min=0.8.2
settings="${HOME:-/nonexistent}/.claude/settings.json"
init_fix="run factory-init.sh --root $root"

version_ge() { # <a> <b>: a >= b, both x.y.z
  printf '%s %s\n' "$1" "$2" | awk '{
    split($1, a, "."); split($2, b, ".")
    for (i = 1; i <= 3; i++) { if (a[i] + 0 > b[i] + 0) exit 0; if (a[i] + 0 < b[i] + 0) exit 1 }
    exit 0 }'
}
on_path() { command -v "$1" >/dev/null 2>&1; }

check_tool() { # <id> <why> <install>
  if on_path "$1"; then step "$1" done "$1 on PATH"; else step "$1" missing "$1 is not on PATH, $2" "$3"; fi
}

check_docker() {
  if ! on_path docker; then step docker missing "docker is not on PATH, the Factory UI runs in it" 'install Docker'
  elif docker info >/dev/null 2>&1; then step docker done "the Docker daemon answers"
  else step docker failing "the Docker daemon does not answer" 'start Docker (systemctl start docker) and rerun doctor'; fi
}

check_herdr() {
  if ! on_path herdr; then
    step herdr missing "herdr is not on PATH, every factory session runs in it" "install herdr $herdr_min or later from https://herdr.dev"
    return 0
  fi
  hv=$(herdr --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || :)
  if [ -z "$hv" ]; then step herdr failing "herdr --version prints no version" "reinstall herdr $herdr_min or later from https://herdr.dev"
  elif version_ge "$hv" "$herdr_min"; then step herdr done "herdr $hv"
  else step herdr failing "herdr $hv is older than $herdr_min, the factory parses the $herdr_min shapes" "update herdr to $herdr_min or later"; fi
}

check_herdr_server() {
  if ! on_path herdr; then step herdr-server missing "herdr is not installed" 'install herdr first'; return 0; fi
  hs=$(herdr status 2>&1) && hs_rc=0 || hs_rc=$?
  if [ "$hs_rc" = 0 ] && printf '%s\n' "$hs" | grep -q 'status: running' && printf '%s\n' "$hs" | grep -q 'compatible: yes'; then
    step herdr-server done "the herdr server runs and is compatible"
  else
    step herdr-server failing "herdr status: $(printf '%s\n' "$hs" | grep -v '^[[:space:]]*$' | tail -n1)" \
      'start herdr in a terminal (a restart after an update), then rerun doctor'
  fi
}

check_herdr_integration() {
  if ! on_path herdr; then step herdr-integration missing "herdr is not installed" 'install herdr first'; return 0; fi
  hi=$(herdr integration status 2>/dev/null | grep '^claude:' | head -n1 || :)
  case "$hi" in
    'claude: current'*) step herdr-integration done "herdr integration for Claude ${hi#claude: }" ;;
    ''|'claude: not installed'*)
      step herdr-integration missing "no herdr integration for Claude: no session ids, no resume after a herdr restart" \
        'herdr integration install claude' ;;
    *) step herdr-integration failing "herdr integration for Claude is ${hi#claude: }" 'herdr integration install claude' ;;
  esac
}

check_herdr_toast() {
  tc="${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/herdr/config.toml"
  td=$(awk '
    /^[ \t]*\[/ { on = ($0 ~ /^[ \t]*\[ui\.toast\][ \t]*$/); next }
    on && /^[ \t]*delivery[ \t]*=/ { v = $0; sub(/^[^=]*=[ \t]*/, "", v); sub(/[ \t]*#.*$/, "", v); gsub(/"/, "", v); print v; exit }' \
    "$tc" 2>/dev/null || :)
  case "$td" in
    system|herdr|terminal) step herdr-toast done "herdr toast delivery \"$td\"" ;;
    *) step herdr-toast missing "herdr toasts are off (${td:-no} [ui.toast] delivery in $tc), a waiting question notifies nobody" \
         "set [ui.toast] delivery = \"system\" in $tc, then herdr server reload-config" ;;
  esac
}

check_claude() {
  if ! on_path claude; then step claude missing "Claude Code is not on PATH" 'install Claude Code (https://claude.com/claude-code)'; return 0; fi
  cv=$(claude --version 2>/dev/null | head -n1 | sed 's/ *(Claude Code)//' || :)
  if [ -n "$cv" ]; then step claude done "Claude Code $cv"
  else step claude failing "claude --version prints nothing" 'reinstall Claude Code'; fi
}

# the forge of a repo url: its host, its project path, and the CLI that reads it (forge.sh's rule, gitea aside)
host_of() {
  case "$1" in
    *://*) ho=${1#*://}; ho=${ho#*@}; ho=${ho%%/*}; ho=${ho%%:*} ;;
    *@*:*) ho=${1#*@}; ho=${ho%%:*} ;;
    *) ho='' ;;
  esac
  printf '%s' "$ho"
}
project_of() {
  case "$1" in
    *://*) po=${1#*://}; po=${po#*/} ;;
    *) po=${1#*:} ;;
  esac
  po=${po%/}; printf '%s' "${po%.git}"
}
cli_of() { if [ "$1" = github.com ]; then echo gh; else echo glab; fi; }
logins=' '
logged_in() { # <cli> <host>, one auth status per pair
  case "$logins" in *" $1@$2=1 "*) return 0 ;; *" $1@$2=0 "*) return 1 ;; esac
  if "$1" auth status --hostname "$2" 2>&1 | grep -q "Logged in to $2"; then logins="$logins$1@$2=1 "; return 0; fi
  logins="$logins$1@$2=0 "; return 1
}

repo_keys() {
  [ -f "$state/repos.yml" ] || return 0
  awk '/^[A-Za-z0-9_-]+:/ { k = $1; sub(/:$/, "", k); if (!(k in seen)) { seen[k] = 1; print k } }' "$state/repos.yml"
}
# `<key> <alias>` of every repo that has an alias: line, valid or not
alias_rows() {
  [ -f "$state/repos.yml" ] || return 0
  awk '
    /^[A-Za-z0-9_-]+:/ { k = $1; sub(/:$/, "", k) }
    k != "" && match($0, /(^|[{, \t])alias[ \t]*:[ \t]*["'"'"']?[^,}"'"'"' \t]+/) {
      v = substr($0, RSTART, RLENGTH); sub(/.*:[ \t]*/, "", v); gsub(/["'"'"']/, "", v); print k, v
    }' "$state/repos.yml"
}

check_forge_login() {
  fl_hosts=$(for k in $(repo_keys); do host_of "$(yml_field "$k" url)"; echo; done | sort -u | grep -v '^$' || :)
  if [ -z "$fl_hosts" ]; then
    if on_path glab || on_path gh; then step forge-login done "no forge host registered yet"
    else step forge-login missing "neither glab nor gh is on PATH" 'install glab (GitLab) or gh (GitHub)'; fi
    return 0
  fi
  fl_bad='' fl_fix='' fl_good=''
  for h in $fl_hosts; do
    c=$(cli_of "$h")
    if ! on_path "$c"; then fl_bad="$fl_bad $h ($c is not installed)"; fl_fix="$fl_fix; install $c"
    elif ! logged_in "$c" "$h"; then fl_bad="$fl_bad $h ($c is not logged in)"; fl_fix="$fl_fix; $c auth login --hostname $h"
    else fl_good="$fl_good $h"; fi
  done
  if [ -n "$fl_bad" ]; then step forge-login missing "no forge login for$fl_bad" "${fl_fix#; }"
  else step forge-login done "logged in to$fl_good"; fi
}

check_state_repo() {
  if [ -d "$state/.git" ] && [ -f "$state/repos.yml" ]; then step state-repo done "state repo $state"
  else
    step state-repo missing "no state repo at $state" \
      "$init_fix for a new one, or factory-init.sh --root $root --from <url> for a clone of the existing one"
  fi
}

check_state_remote() {
  if [ ! -d "$state/.git" ]; then step state-remote missing "no state repo yet" "$init_fix"; return 0; fi
  sr=$(state_remote_report)
  srm=$(printf '%s\n' "$sr" | grep '^missing: ' | head -n1 || :)
  if [ -n "$srm" ]; then
    srm=${srm#missing: }
    step state-remote missing "${srm%%, *}" "${srm#*, }"
  else
    step state-remote done "$(printf '%s\n' "$sr" | sed 's/^ok: //' | paste -sd ';' - | sed 's/;/; /g')"
  fi
}

# PLAN 3.5: the writers commit locally and state-push.sh carries the commits in the background; a commit that stays
# local for more than 10 minutes means that push stopped running or keeps being refused
check_state_push() {
  if [ ! -d "$state/.git" ]; then step state-push missing "no state repo yet" "$init_fix"; return 0; fi
  if ! git -C "$state" remote get-url origin >/dev/null 2>&1; then step state-push done "no state remote, nothing to push"; return 0; fi
  sp=$(git -C "$state" log --format=%ct HEAD --not --remotes=origin 2>/dev/null || :)
  if [ -z "$sp" ]; then step state-push done "every state commit is pushed"; return 0; fi
  sp_n=$(printf '%s\n' "$sp" | wc -l | tr -d ' ')
  sp_age=$(( $(date +%s) - $(printf '%s\n' "$sp" | sort -n | head -n1) ))
  if [ "$sp_age" -gt 600 ]; then
    step state-push failing "$sp_n state commit(s) unpushed, the oldest for $((sp_age / 60)) minutes" \
      "sh $plugin/bin/state-push.sh --state $state (the monitor pass and the CEO loop run it), and read why it failed"
  else
    step state-push done "$sp_n state commit(s) unpushed for less than 10 minutes"
  fi
}

check_work_dir() {
  wd=$(sed -n 's/.*"WORK_DIR"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$settings" 2>/dev/null | head -n1 || :)
  wd=${wd%/}
  if [ "$wd" = "$root" ]; then step work-dir done "WORK_DIR=$root in $settings"
  elif [ -z "$wd" ]; then step work-dir missing "no WORK_DIR in $settings" "$init_fix"
  else step work-dir failing "WORK_DIR is $wd in $settings, not $root" "$init_fix"; fi
}

check_prompt_suggestion() {
  if grep -Eq '"promptSuggestionEnabled"[[:space:]]*:[[:space:]]*false' "$settings" 2>/dev/null; then
    step prompt-suggestion done "promptSuggestionEnabled: false in $settings"
  else
    step prompt-suggestion missing "promptSuggestionEnabled is not false in $settings, a suggestion would be typed into a UI answer" \
      "$init_fix --ui docker"
  fi
}

check_repos() {
  rn=$(repo_keys | wc -l | tr -d ' ')
  if [ "$rn" -gt 0 ]; then step repos done "$rn repositories registered"
  else step repos missing "no repository registered" "run factory-add-repo.sh --root $root in each product clone"; fi
}

check_aliases() {
  ar=$(alias_rows)
  ar_bad=$(printf '%s\n' "$ar" | awk 'NF == 2 && $2 !~ /^[A-Z][A-Z][A-Z]?[A-Z]?$/ { printf " %s (%s)", $1, $2 }')
  ar_dup=$(printf '%s\n' "$ar" | grep -v '^$' | sort -k2,2 -k1,1 \
    | awk '$2 == prev { printf " %s on %s and %s", $2, pk, $1 } { prev = $2; pk = $1 }')
  if [ -n "$ar_dup" ]; then
    step aliases failing "one alias on two repos:$ar_dup, their ids would collide" "give one of them another alias: in $state/repos.yml"
  elif [ -n "$ar_bad" ]; then
    step aliases failing "an alias that is not 2 to 4 uppercase letters:$ar_bad" "correct it in $state/repos.yml"
  else
    step aliases done "$(printf '%s\n' "$ar" | grep -c . || :) aliases, all unique"
  fi
}

check_repo_path() { # <key>
  rp=$(yml_field "$1" path)
  if [ -z "$rp" ]; then step "repo:$1:path" missing "$1 has no path: in repos.yml" "run factory-add-repo.sh --root $root in its clone"
  elif git -C "$rp" rev-parse --git-dir >/dev/null 2>&1; then step "repo:$1:path" done "$1 at $rp"
  else step "repo:$1:path" failing "the path of $1, $rp, is no git clone" "clone it there or change its path: in $state/repos.yml"; fi
}

check_repo_alias() { # <key>
  ra=$(repo_alias "$1") && ra_rc=0 || ra_rc=$?
  if [ "$ra_rc" != 0 ]; then
    step "repo:$1:alias" failing "the alias of $1 is not 2 to 4 uppercase letters" "correct it in $state/repos.yml"
  elif [ -n "$ra" ]; then
    step "repo:$1:alias" done "$1 alias $ra, its new ids are T-$ra-<n>"
  else
    step "repo:$1:alias" missing "$1 has no alias, its new tasks get legacy T-<n> ids" \
      "run factory-add-repo.sh --root $root --repo $(yml_field "$1" path) (it proposes an alias, --alias <ALIAS> overrides)"
  fi
}

check_repo_toolset() { # <key>
  if [ -f "$state/repos/$1/toolset.md" ]; then step "repo:$1:toolset" done "repos/$1/toolset.md"
  else step "repo:$1:toolset" missing "$1 has no repos/$1/toolset.md" "run factory-add-repo.sh --root $root --repo $(yml_field "$1" path)"; fi
}

# PLAN 3.4: the class of a repo decides how a block MR skips its pipeline. A: the pipeline is not required. B: it
# is required and a skipped pipeline counts as success (an empty [skip ci] head commit). C: required and a skipped
# one does not count, so every block MR runs the full pipeline. Read only, and skipped cleanly (missing, with the
# login as its fix) when the forge CLI is absent or not logged in.
json_val() { # <json> <field>
  printf '%s' "$1" | grep -oE "\"$2\"[[:space:]]*:[[:space:]]*(\"[^\"]*\"|true|false|null|[0-9]+)" | head -n1 \
    | sed 's/^[^:]*:[[:space:]]*//; s/"//g'
}
check_repo_mr_class() { # <key>
  mu=$(yml_field "$1" url); mh=$(host_of "$mu")
  [ -n "$mh" ] || return 0
  mp=$(project_of "$mu"); mc=$(cli_of "$mh"); id="repo:$1:mr-class"
  if ! on_path "$mc"; then step "$id" missing "MR class of $1 not read: $mc is not installed" "install $mc, then rerun doctor"; return 0; fi
  if ! logged_in "$mc" "$mh"; then step "$id" missing "MR class of $1 not read: $mc is not logged in to $mh" "$mc auth login --hostname $mh"; return 0; fi
  if [ "$mc" = glab ]; then
    mj=$(glab api --hostname "$mh" "projects/$(printf '%s' "$mp" | sed 's#/#%2F#g')" 2>/dev/null) || mj=''
    if [ -z "$mj" ]; then step "$id" failing "MR class of $1 not read: glab api projects/$mp failed on $mh" "check that $mu exists and glab reaches $mh"; return 0; fi
    mm=$(json_val "$mj" merge_method); sq=$(json_val "$mj" squash_option)
    req=$(json_val "$mj" only_allow_merge_if_pipeline_succeeds); skp=$(json_val "$mj" allow_merge_on_skipped_pipeline)
    if [ "$req" = true ] && [ "$skp" != true ]; then
      step "$id" failing "$1 is class C: the pipeline must succeed and a skipped pipeline does not count (merge method $mm), so every block MR runs the full pipeline" \
        "in $mp on $mh: Settings > Merge requests > Merge checks, tick \"Skipped pipelines are considered successful\" (allow_merge_on_skipped_pipeline: true)"
    elif [ "$req" = true ]; then
      step "$id" done "$1 is class B: merge method $mm, squash $sq, the pipeline must succeed, a skipped one counts"
    else
      step "$id" done "$1 is class A: merge method $mm, the pipeline is not required"
    fi
  else
    mb=$(yml_field "$1" default_branch); mb=${mb:-main}
    if ! gh api "repos/$mp" >/dev/null 2>&1; then step "$id" failing "MR class of $1 not read: gh api repos/$mp failed" "check that $mu exists and gh reaches it"; return 0; fi
    if gh api "repos/$mp/branches/$mb/protection/required_status_checks" >/dev/null 2>&1; then
      step "$id" done "$1 is class B: $mb requires status checks, a skipped check counts"
    else
      step "$id" done "$1 is class A: $mb requires no status checks"
    fi
  fi
}

# PLAN 3.4, GitHub: a block PR targets the work branch, so a workflow that triggers on pull_request or push without a
# branch filter on the default branch runs for every block
check_repo_workflows() { # <key>
  wu=$(yml_field "$1" url)
  [ "$(host_of "$wu")" = github.com ] || return 0
  wp=$(yml_field "$1" path); wb=$(yml_field "$1" default_branch); wb=${wb:-main}
  wf_bad=''
  for f in "$wp"/.github/workflows/*.yml "$wp"/.github/workflows/*.yaml; do
    [ -f "$f" ] || continue
    grep -qE '(^|[^a-z_])(pull_request|push)([^a-z_]|$)' "$f" || continue
    grep -qE "branches:.*(^|[^A-Za-z0-9_./-])$wb([^A-Za-z0-9_./-]|\$)" "$f" && continue
    grep -qE "^[[:space:]]*-[[:space:]]*[\"']?$wb[\"']?[[:space:]]*\$" "$f" && continue
    wf_bad="$wf_bad ${f##*/}"
  done
  if [ -n "$wf_bad" ]; then
    step "repo:$1:workflows" failing "workflows of $1 without a branch filter on $wb:$wf_bad, they run for every block PR" \
      "filter their pull_request and push triggers with branches: [$wb]"
  else
    step "repo:$1:workflows" done "the workflows of $1 filter on $wb, or there are none"
  fi
}

check_capacity() {
  caps=$(awk '
    on && /^[^ \t#]/ { exit }
    /^capacity:/ { on = 1; sub(/^capacity:/, "") }
    on {
      s = $0; sub(/#.*/, "", s)
      while (match(s, /[A-Za-z0-9_-]+[ \t]*:[ \t]*[0-9]+/)) {
        p = substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH)
        k = p; sub(/[ \t]*:.*/, "", k); v = p; sub(/.*:[ \t]*/, "", v)
        print k, v
      }
    }' "$state/factory.yml" 2>/dev/null || :)
  cs=$(printf '%s\n' "$caps" | awk '$1 == "sessions" { print $2; exit }')
  if [ -n "$cs" ]; then
    step capacity done "capacity: sessions $cs, $(printf '%s\n' "$caps" | grep -vc '^sessions ' || :) roles capped"
  else
    step capacity missing "no capacity: sessions in $state/factory.yml, nothing is capped" \
      "add to $state/factory.yml: capacity: {sessions: 10, roles: {repo-lead: 3, scout: 8, triage-analyst: 2, researcher: 4, plan-architect: 2, architecture-auditor: 2, test-designer: 3, implementer: 4, implementer-senior: 2, code-reviewer: 2}}"
  fi
}

check_green() {
  gf=$(awk -F '\t' '$2 == "failing"' "$tmp/steps" | wc -l | tr -d ' ')
  gm=$(awk -F '\t' '$2 == "missing"' "$tmp/steps" | wc -l | tr -d ' ')
  if [ "$gf" -gt 0 ]; then step doctor failing "$gf failing and $gm missing" 'fix the failing steps first, then rerun doctor'
  elif [ "$gm" -gt 0 ]; then step doctor missing "$gm missing" 'fix the missing steps, then rerun doctor'
  else step doctor done "every step is done"; fi
}

check_ceo() {
  if on_path herdr && herdr agent get ceo >/dev/null 2>&1; then step ceo done "the CEO runs (herdr agent ceo)"
  else step ceo missing "the CEO is not running" "open a herdr tab in $state and run: claude '/claude-factory:factory ceo'"; fi
}

if [ "$json" = 1 ]; then
  : > "$tmp/steps"
  check_tool git 'the factory is git' 'install git'
  check_tool node 'init and the hooks parse JSON with it' 'install Node.js'
  check_tool python3 'the herdr integration hook of Claude needs it' 'install python3'
  check_docker
  check_herdr
  check_herdr_server
  check_forge_login
  check_claude
  check_state_repo
  check_state_remote
  check_state_push
  check_work_dir
  check_prompt_suggestion
  check_herdr_integration
  check_herdr_toast
  check_repos
  check_aliases
  for k in $(repo_keys); do
    check_repo_path "$k"
    check_repo_alias "$k"
    check_repo_toolset "$k"
    check_repo_mr_class "$k"
    check_repo_workflows "$k"
  done
  check_capacity
  check_green
  check_ceo
  out="${uihome:-${FACTORY_UI_HOME:-$HOME/.claude-factory/ui}}/setup"
  mkdir -p "$out" || die "cannot create $out"
  awk -F '\t' -v at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" -v root="$root" '
    function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    BEGIN { printf "{\n  \"at\": \"%s\",\n  \"root\": \"%s\",\n  \"steps\": [", at, esc(root) }
    { printf "%s\n    {\"id\": \"%s\", \"state\": \"%s\", \"detail\": \"%s\", \"fix\": \"%s\"}", (NR > 1 ? "," : ""), esc($1), $2, esc($3), esc($4) }
    END { printf "\n  ]\n}\n" }' "$tmp/steps" > "$out/.doctor.json.tmp"
  mv -f "$out/.doctor.json.tmp" "$out/doctor.json"
  echo "$out/doctor.json"
  exit 0
fi

top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null | sed 's/\\/\//g') || die "$repo is not a git clone"
[ -n "$top" ] || die "$repo is not a git clone"
url=$(git -C "$top" remote get-url origin 2>/dev/null) || die "$top has no origin remote"
key=${url%/}; key=${key##*[/:]}; key=${key%.git}

add_repo="run factory-add-repo.sh --root $root --repo $top"

state_remote_report

# --- registration ----------------------------------------------------------------------------------------------
if [ -f "$state/repos.yml" ] && grep -q "^$key:.*path:" "$state/repos.yml"; then
  # a registered path that no longer points at this clone is worse than none: the readers resolve the key from it
  regpath=$(sed -n "s/^$key:.*path:[[:space:]]*//p" "$state/repos.yml" | head -n1 \
    | sed 's/^["'\'']//; s/["'\''}].*$//; s:[[:space:]]*$::; s:/*$::')
  if [ "$regpath" = "$top" ]; then
    ok "$key registered in state/repos.yml with path"
  else
    missing "a current path for $key in state/repos.yml (registered: $regpath, this clone: $top)" \
      "change its path: to \"$top\", or run doctor from $regpath"
  fi
elif [ -f "$state/repos.yml" ] && grep -q "^$key:" "$state/repos.yml"; then
  missing "path for $key in state/repos.yml" "add path: \"$top\" to its line"
else
  missing "$key in state/repos.yml" "$add_repo"
fi

# --- one key per clone -------------------------------------------------------------------------------------------
# 2026-09-07: two keys registered for the same directory made repo_key_of_cwd pick one and the tasks the other,
# the toolset, memory and tripwire state of a session split across two keys. The same awk as lib-tasks.sh's
# repo_clone_paths, paths compared with forward slashes and no trailing slash.
if [ -f "$state/repos.yml" ]; then
  dups=$(awk '
    /^[A-Za-z0-9_-]+:/ { key = $1; sub(/:$/, "", key) }
    /path:/ && key != "" {
      p = $0; sub(/.*path:[ \t]*/, "", p); sub(/[ \t]*[,}].*$/, "", p); sub(/[ \t]+#.*$/, "", p)
      gsub(/^["'"'"']|["'"'"']$/, "", p); gsub(/\\/, "/", p); sub(/\/+$/, "", p)
      if (p != "") print p "\t" key
    }' "$state/repos.yml" | sort \
    | awk -F '\t' '$1 == prev { print pk " and " $2 " both point at " $1 } { prev = $1; pk = $2 }')
  if [ -n "$dups" ]; then
    printf '%s\n' "$dups" | while IFS= read -r d; do
      missing "one key per clone in state/repos.yml ($d)" "remove one and re-point the tasks that use it"
    done
  else
    ok "one key per clone in state/repos.yml"
  fi
fi

# --- the MR title cap ----------------------------------------------------------------------------------------
# E (2026-09-22, MR !412): the factory opened a 113-character title and the repo's own commitlint job refused
# it at 100. When the clone lints its titles, its registry entry has to carry a cap no larger than that lint's,
# or the factory will keep authoring goals the forge cannot take.
if cc=$(commitlint_cap "$top"); then
  cc_max=$(printf '%s' "$cc" | cut -f1)
  cc_src=$(printf '%s' "$cc" | cut -f2)
  cur=''
  [ ! -f "$state/repos.yml" ] || cur=$(awk -v want="$key" '
    /^[A-Za-z0-9_-]+:/ { k = $1; sub(/:$/, "", k) }
    /mr_title_max:/ && k == want {
      v = $0; sub(/.*mr_title_max:[ \t]*/, "", v); sub(/[ \t]*[,}].*$/, "", v); sub(/[ \t]+#.*$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v); if (v ~ /^[0-9]+$/) { print v; exit }
    }' "$state/repos.yml")
  if [ -z "$cur" ]; then
    missing "mr_title_max for $key in state/repos.yml ($cc_src caps the MR title at $cc_max)" \
      "add mr_title_max: $cc_max to its line, otherwise the factory authors goals the title lint refuses"
  elif [ "$cur" -gt "$cc_max" ]; then
    missing "an mr_title_max for $key no larger than the repo's own lint (is $cur, $cc_src caps at $cc_max)" \
      "lower mr_title_max to $cc_max in its line"
  else
    ok "mr_title_max $cur for $key ($cc_src caps at $cc_max)"
  fi
fi

# --- toolset + stack ---------------------------------------------------------------------------------------------
toolset="$state/repos/$key/toolset.md"
stack=''
if [ -f "$toolset" ]; then
  ok "repos/$key/toolset.md"
  stack=$(awk 'NR == 1 && $0 != "---" { exit } NR > 1 && /^---$/ { exit } /^stack:[[:space:]]*/ { sub(/^stack:[[:space:]]*/, ""); print; exit }' "$toolset")
  if [ -n "$stack" ]; then ok "stack $stack"; else missing "stack in repos/$key/toolset.md" "add stack: <stack> to its frontmatter"; fi
else
  missing "repos/$key/toolset.md" "$add_repo"
fi

# --- how tasks are dispatched -------------------------------------------------------------------------------
spawn=manual
[ ! -f "$state/factory.yml" ] || spawn=$(sed -n 's/^spawn:[[:space:]]*//p' "$state/factory.yml" | head -n1 \
  | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
[ -n "$spawn" ] || spawn=unset
case "$spawn" in
  manual) ok "spawn: manual (session-monitor.sh prints the commands)" ;;
  herdr)
    if command -v herdr >/dev/null 2>&1; then
      ok "spawn: herdr, herdr on PATH"
    else
      missing "spawn: herdr, but herdr is not on PATH" \
        'install herdr from https://herdr.dev, or set spawn: manual in factory.yml'
    fi ;;
  unset) missing "spawn: in factory.yml" 'add `spawn: manual` or `spawn: herdr` to it' ;;
  *) missing "spawn: $spawn in factory.yml" 'it takes herdr or manual' ;;
esac

# --- the Factory UI ------------------------------------------------------------------------------------------
ui=off
[ ! -f "$state/factory.yml" ] || ui=$(sed -n 's/^ui:[[:space:]]*//p' "$state/factory.yml" | head -n1 \
  | sed 's/[[:space:]]*#.*//; s/[[:space:]]*$//')
if [ "$ui" = docker ]; then
  if docker info >/dev/null 2>&1; then ok "ui: docker, the Docker daemon answers"
  else missing "ui: docker, but the Docker daemon does not answer" 'install and start Docker, or set ui: off in factory.yml'; fi
  if command -v herdr >/dev/null 2>&1; then ok "ui: docker, herdr on PATH"
  else missing "ui: docker, but herdr is not on PATH" 'install herdr from https://herdr.dev, or set ui: off in factory.yml'; fi
  if grep -Eq '"promptSuggestionEnabled"[[:space:]]*:[[:space:]]*false' "${HOME:-/nonexistent}/.claude/settings.json" 2>/dev/null; then
    ok "ui: docker, promptSuggestionEnabled: false in ~/.claude/settings.json"
  else
    missing "ui: docker, but promptSuggestionEnabled is not false in ~/.claude/settings.json" \
      "run factory-init.sh --root $root --ui docker"
  fi
fi

# --- the tools the toolset binds ---------------------------------------------------------------------------------
tool() { # <binary> <install command>
  if command -v "$1" >/dev/null 2>&1; then ok "$1 on PATH"; else missing "$1 on PATH" "$2"; fi
}
# only the tools this toolset actually binds: a repo that deleted the row it cannot run must not be told to
# install the tool behind it (ADR-0039, a command the toolset lacks does not exist for the repo)
binds() { # <command name> → true when the toolset has a table row for it
  [ -f "$toolset" ] && grep -q "^|[[:space:]]*\`$1" "$toolset"
}
if [ "$stack" = dotnet ]; then
  ! binds coverage || tool reportgenerator 'dotnet tool install -g dotnet-reportgenerator-globaltool'
  ! binds crap || tool dotnet-crap 'dotnet tool install -g Crap4DotNet'
  ! binds mutation || tool dotnet-stryker 'dotnet tool install -g dotnet-stryker'
fi
! binds arch-build || tool likec4 'npm i -g likec4'

# --- test-globs ----------------------------------------------------------------------------------------------------
globs=''
[ ! -f "$toolset" ] || globs=$(awk '/^test-globs:[[:space:]]*$/ { g=1; next }
     g && /^[[:space:]]*-[[:space:]]/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/"/, ""); print; next }
     g { exit }' "$toolset" | tr '\n' ' ' | sed 's/ $//')
if [ -n "$globs" ]; then ok "test-globs ($globs)"; else missing "test-globs in repos/$key/toolset.md" "add the frontmatter list (the plugin's toolsets/dotnet.md shows it)"; fi

# --- what the dotnet coverage and crap rows need beyond the binaries ------------------------------------------------
if [ "$stack" = dotnet ]; then
  # 2026-09-07: `coverage` ran green and produced no cobertura file, so `crap` had nothing to score and the gate
  # could never be met, no test project referenced a collector. A test project is a *.csproj under a path one of
  # the test-globs matches (`**/` → any directories, `*` → one segment) or one that declares itself a test project.
  if binds coverage || binds crap; then
    glob_re=''
    p1=$(printf '\001'); p2=$(printf '\002')
    for gl in $globs; do
      re=$(printf '%s' "$gl" | sed "s/[.]/\\\\./g; s#\\*\\*/#$p1#g; s#\\*\\*#$p2#g; s/\\*/[^\\/]*/g; s#$p1#(.*/)?#g; s#$p2#.*#g")
      glob_re="${glob_re:+$glob_re|}^($re)\$"
    done
    testprojs=$(find "$top" -name '*.csproj' -not -path '*/bin/*' -not -path '*/obj/*' -not -path '*/.git/*' 2>/dev/null \
      | while IFS= read -r f; do
          rel=${f#"$top"/}
          if { [ -n "$glob_re" ] && printf '%s\n' "$rel" | grep -qE "$glob_re"; } \
            || grep -qiE '<IsTestProject>[[:space:]]*true|Microsoft\.NET\.Test\.Sdk|Microsoft\.Testing\.Platform' "$f" 2>/dev/null; then
            printf '%s\n' "$f"
          fi
        done)
    collector=''
    if [ -n "$testprojs" ]; then
      # Directory.Build.props/targets can carry the PackageReference for every test project at once
      collector=$( { printf '%s\n' "$testprojs"; find "$top" -name 'Directory.Build.props' -o -name 'Directory.Build.targets' 2>/dev/null; } \
        | xargs -r grep -liE 'coverlet\.collector|Microsoft\.Testing\.Extensions\.CodeCoverage|coverlet\.msbuild' 2>/dev/null | head -n 1 || :)
    fi
    if [ -n "$collector" ]; then
      ok "a coverage collector in a test project (${collector#"$top"/})"
    else
      missing "a coverage collector in a test project" \
        "add coverlet.collector (VSTest) or Microsoft.Testing.Extensions.CodeCoverage (MTP) to a test project, otherwise the crap gate can never be met"
    fi
  fi
  # 2026-09-07: Crap4DotNet targets net8.0 and refuses to start on a machine with only a newer runtime unless told
  # to roll forward, the toolset's crap row carries DOTNET_ROLL_FORWARD=Major, this names the other way out
  if command -v dotnet-crap >/dev/null 2>&1 && command -v dotnet >/dev/null 2>&1; then
    if dotnet --list-runtimes 2>/dev/null | grep -q '^Microsoft\.NETCore\.App 8\.'; then
      ok "a .NET 8 runtime for dotnet-crap"
    else
      missing "a .NET 8 runtime for dotnet-crap" \
        "run it with DOTNET_ROLL_FORWARD=Major (the toolset's crap row does) or install the 8.0 runtime"
    fi
  fi
fi

# --- docs/architecture ---------------------------------------------------------------------------------------------
if [ -d "$top/docs/architecture" ]; then ok "docs/architecture in $top"; else missing "docs/architecture" "run the architecture-docs bootstrap"; fi

# --- curation --------------------------------------------------------------------------------------------------
curation=auto
[ ! -f "$state/factory.yml" ] || curation=$(sed -n 's/^curation:[[:space:]]*//p' "$state/factory.yml" | head -n 1 | sed 's/[[:space:]]*$//')
case "${curation:-auto}" in
  auto|manual) ok "curation ${curation:-auto}" ;;
  *) missing "factory.yml curation must be auto|manual (is '$curation')" "set curation: auto or curation: manual in $state/factory.yml" ;;
esac

# --- context_window (T-056) -------------------------------------------------------------------------------------
# the compact tripwire's window: absent stays the 200000 default (no line, not a miss), present has to be a
# positive integer, same ok:/missing: shape as curation. A leading zero (007) is refused outright rather than
# read as 7 with the zero stripped, a hand-edited typo should not turn into a legitimate-looking tiny window,
# and this is the same value compact-tripwire.sh's cfg_window guard refuses (T-056-04).
context_window=
[ ! -f "$state/factory.yml" ] || context_window=$(sed -n 's/^context_window:[[:space:]]*//p' "$state/factory.yml" | head -n 1 | sed 's/[[:space:]]*#.*$//' | sed 's/[[:space:]]*$//')
if [ -n "$context_window" ]; then
  case "$context_window" in
    *[!0-9]*|'') missing "factory.yml context_window must be a positive integer (is '$context_window')" "set context_window: <tokens> in $state/factory.yml or remove the key to use the default" ;;
    0?*) missing "factory.yml context_window must not have a leading zero (is '$context_window')" "set context_window: <tokens> in $state/factory.yml or remove the key to use the default" ;;
    *[!0]*) ok "context_window $context_window" ;;
    *) missing "factory.yml context_window must be a positive integer (is '$context_window')" "set context_window: <tokens> in $state/factory.yml or remove the key to use the default" ;;
  esac
fi

# --- memory budget ----------------------------------------------------------------------------------------------
if [ -f "$plugin/bin/memory-budget.sh" ]; then
  if out=$(sh "$plugin/bin/memory-budget.sh" --all --state "$state" 2>&1); then
    over=$(printf '%s\n' "$out" | awk '$0 == "over budget" { print scope; next } { scope = $1 }')
    if [ -n "$over" ]; then
      for scope in $over; do missing "memory over budget in $scope" "run factory consolidate $scope"; done
    else
      ok "memory within budget"
    fi
  else
    missing "memory budget unreadable" "$(printf '%s\n' "$out" | tail -n 1 | sed 's/^memory-budget: //')"
  fi
fi

# --- the machine checks of the Setup tab that touch this clone's sessions ------------------------------------------
check_tool python3 'the herdr integration hook of Claude needs it' 'install python3'
check_herdr
check_herdr_server
check_herdr_integration
check_herdr_toast
check_state_push
check_aliases
if [ -f "$state/repos.yml" ] && grep -q "^$key:" "$state/repos.yml"; then
  check_repo_alias "$key"
  check_repo_mr_class "$key"
  check_repo_workflows "$key"
fi
check_capacity
exit 0
