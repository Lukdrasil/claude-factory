#!/bin/sh
# The pipeline page in a browser: the fixture of tests/ui-fixture.sh, extended with a block, two more tasks, seven
# more sessions, an ask of every kind, a gone setup session, a grill ask of s6 filed under another task and one naming none, and a drawn
# visual of s2, served through ui-up.sh and driven by tests/ui-page.test.js through the fixture's `browser`, as the
# host uid so the asks it writes mid-run belong to the host.
# The browser checks print their own PASS and FAIL lines. Without Docker it prints `SKIP ui-page: no docker`.
set -u
unset FACTORY_UI_HOME FACTORY_UI_CONTAINER WORK_DIR
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bin="$repo/bin"

if ! docker info >/dev/null 2>&1; then
  echo 'SKIP ui-page: no docker'
  exit 0
fi

tmp=$(mktemp -d)
name="cf-ui-page-$$"
image="claude-factory-ui:test-$$"
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

# --- the page's fixture on top: T-001-01 sorts before T-001 in the board, so the page has to place it -----------
task() { # <id> <status> <goal>
  printf -- '---\nid: %s\nrepo: claude-factory\nstatus: %s\ntier: yellow\narchetype: feature\n---\n\n# Goal\n%s\n' \
    "$1" "$2" "$3" > "$state1/repos/claude-factory/tasks/$1-fixture.md"
}
task T-001-01 in_progress 'Block one of the fixture.'
task T-002 in_progress 'The second fixture task.'
# T-002 is triaged and approved and nothing else, while its session reports step 11
printf '\n## Related issues\nnone\n' >> "$state1/repos/claude-factory/tasks/T-002-fixture.md"
# T-003 is a draft nobody triaged yet: the template's placeholders stand in tier, archetype and complexity
printf -- '---\nid: T-003\nrepo: claude-factory\nstatus: in_progress\ntier: <green|yellow|red>\narchetype: <feature|bugfix|refactor|research|ops>\ncomplexity: <low|medium|high>\n---\n\n# Goal\n%s\n' \
  'The task of a session outside herdr.' > "$state1/repos/claude-factory/tasks/T-003-fixture.md"

session() { sh "$bin/ui-session.sh" "$@" || bad "ui-session.sh $*"; }
session --session s1 --step 'Step 4 of 16: grill T-001'
session --session s2 --pane w1:p2 --flow solve --task T-002 --step 'Step 11 of 16: wave 1 implement, from T-002-01'
session --session s3 --flow solve --task T-003 --step 'Step 9 of 16: approve and claim T-003'
session --session s4 --pane w1:p4 --flow doctor --task none --step 'doctor'
session --session s5 --pane w1:p5 --flow solve --task T-003 --step 'Step 9 of 16: approve and claim T-003'
session --session s6 --pane w1:p6 --flow grill --task T-001 --step 'Step 4 of 16: grill T-001'
session --session s7 --pane w1:p7 --flow add-repo --task none --step 'add-repo ecs'
session --session s8 --pane w1:p8 --flow init --task none --step 'Step 2 of 4: repos'
printf 'gone\n' > "$ui/sessions/s7/agent"

put() { # <sid> <ask> <task> <flow> <mtime>, stdin: the markdown
  { printf -- '---\nask: %s\ntask: %s\nflow: %s\nstep: fixture\nstatus: open\n---\n\n' "$2" "$3" "$4"; cat; } \
    | sh "$bin/ui-ask.sh" --session "$1" >/dev/null || bad "ui-ask.sh --session $1 ($2)"
  touch -d "$5" "$ui/sessions/$1/asks/$2.md"
}
put s2 r1 T-002 solve '2026-09-24 10:01' <<'EOF'
❓ **Q1** - **Which store?**: where the rows live.
  **A** SQLite
  **B** Postgres
  **C** files

➡️ **A**: one writer.

---

❓ **Q2** - **Which port?** (after Q1): the port the server takes.
  **A** 7171
  **B** a random one

➡️ **A**: one URL for every session.

---

❓ **Q3** - **Which runtime?**: where the server runs.
  **A** Docker
  **B** the host

➡️ **A**: nothing on the host.

---

❓ **Q4** - **Which container name?**: one per machine.

➡️ claude-factory-ui, the name ui-up.sh looks for.

---

❓ **Q5** - **Which log level?**: what the container prints.
  **A** info
  **B** debug

➡️ **A**: quiet by default.

---

❓ **Q6** - **Which shell?**: what the scripts run under.
  **A** sh
  **B** bash

➡️ **A**: POSIX only.
EOF
put s2 c1 T-002 solve '2026-09-24 10:03' <<'EOF'
❓ **Q1** - **Approve T-002?**: the cut is checked and every block is a draft.
  **A** yes
  **B** no

➡️ **A**: the cut check passed.
EOF
put s3 o1 T-003 solve '2026-09-24 09:30' <<'EOF'
❓ **Q1** - **Which outside answer?**: a session outside herdr asks this in its terminal.
  **A** the terminal one
  **B** the other one

➡️ **A**: it is answered where it was asked.
EOF
put s3 m1 T-003 solve '2026-09-24 09:31' <<'EOF'
The preamble sentence of m1, before its first question.

❓ **Q1** - **Which runner?**: how the page is started.

The paragraph under Q1 of m1.

| runner | start | stop |
|---|---|---|
| script | ui-up.sh | ui-down.sh |
| compose | docker compose up | docker compose down |

### The section of m1

The sentence under the section of m1.

  **A** the script alone
  **B** run `ui-up.sh` then `ui-down.sh`

➡️ **B**: one pair of commands.
EOF
put s4 d1 none doctor '2026-09-24 10:00' <<'EOF'
# Doctor

Docker is running. herdr is running. promptSuggestionEnabled is false.
EOF
put s5 g1 T-003 solve '2026-09-24 09:10' <<'EOF'
❓ **Q1** - **Which gone answer?**: the session of this ask has ended.
  **A** the queued one
  **B** the other one

➡️ **A**: the relay queues it.
EOF
put s6 k1 T-002 grill '2026-09-24 10:04' <<'EOF'
❓ **Q1** - **Which grill answer?**: the grill of s6 asks this for T-002.
  **A** the grill one
  **B** the other one

➡️ **A**: it belongs to T-002.
EOF
printf -- '---\nask: k2\nflow: grill\nstep: fixture\nstatus: open\n---\n\nThe grill notice of s6, naming no task.\n' > "$ui/sessions/s6/asks/k2.md"
touch -d '2026-09-24 09:55' "$ui/sessions/s6/asks/k2.md"
printf 'gone\n' > "$ui/sessions/s5/agent"
printf '<!doctype html>\n<p id="out">the drawing of s2</p>\n' > "$ui/sessions/s2/visual.html"
printf -- '---\nrow: 2\nversion: 1\nstatus: current\n---\n' > "$ui/sessions/s2/visual.md"
touch -d '2026-09-24 09:00' "$ui/sessions/s1/asks/q1.md"
touch -d '2026-09-24 10:02' "$ui/sessions/s1/asks/q3.md"
mkdir -p "$ui/sessions/s1/answers"
printf 'Q1 A' > "$ui/sessions/s1/answers/1-q1.txt"
printf '1 blocked\n' > "$ui/sessions/s1/relay"

has 'CONTEXT.md defines the drawer'                           '^- \*\*drawer\*\*:' "$(cat "$repo/CONTEXT.md")"

# --- the image from this tree, so the page under test is the one in ui/wwwroot, then the server and the browser ---
timeout 15m docker build -q -t "$image" "$repo/ui" > "$tmp/build.out" 2>&1 \
  || { bad "building $image failed: $(tail -n 20 "$tmp/build.out")"; exit 1; }
up --state "$state1"; rc=$?
is 'ui-up.sh exits 0'                                         "$rc" 0
[ "$rc" = 0 ] || { sed 's/^/  up: /' "$tmp/up.err" | tail -n 30; exit 1; }
is 'the server runs the image of this checkout'               "$(docker inspect -f '{{.Config.Image}}' "$name" 2>/dev/null)" "$image"
port=$(cat "$ui/port" 2>/dev/null)
token=$(cat "$ui/token" 2>/dev/null)
ready "$port" || { bad "the server never answered / on $port: $(docker logs "$name" 2>&1 | tail -n 20)"; exit 1; }

url=$(sh "$bin/ui-ask.sh" --session s2 < "$ui/sessions/s2/asks/c1.md")
touch -d '2026-09-24 10:03' "$ui/sessions/s2/asks/c1.md"
is 'ui-ask.sh prints the link of c1 with the port and the token' "$url" "http://127.0.0.1:$port/?ask=s2/c1#token=$token"
printf '%s\n' "$url" > "$ui/c1.url"

browser "$repo/tests/ui-page.test.js"
rc=$?
cat "$tmp/browser.out"
is 'the browser checks exit 0'                                "$rc" 0
has 'the browser checks ran'                                  '^PASS |^FAIL ' "$(cat "$tmp/browser.out")"

exit $fail
