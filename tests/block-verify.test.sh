#!/bin/sh
# block-verify.sh over a throwaway state clone and a Node fixture repo (package.json with "test": "node --test",
# one passing and one failing test file). A changed `*.test.sh` runs as `sh <file>` and a changed `*Tests.cs`
# only through a `test-filter <expr>` binding, as before. A changed `*.test.js`/`*.spec.js` of a repo whose
# toolset stack is node runs as `node --test <file>`. Any other changed test file runs through a `test-filter`
# binding that takes `<file>`, else through the plain `test` binding, once per verify and not once per file.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
unset WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; fail=1; fi
}
has() { # <what> <text> <haystack>
  case "$3" in *"$2"*) printf 'PASS %s\n' "$1" ;; *) printf 'FAIL %s: no [%s] in [%s]\n' "$1" "$2" "$3"; fail=1 ;; esac
}

state="$tmp/state"
mkdir -p "$state/repos/demo/tasks"
printf -- '---\nid: T-900\nrepo: demo\nbranch: feat/T-900\nstatus: in_progress\n---\n\n# Goal\nx\n' \
  > "$state/repos/demo/tasks/T-900.md"
printf -- '---\nid: T-900-01\nrepo: demo\nbranch: block/T-900-01\nstatus: in_progress\n---\n\n# Goal\nx\n' \
  > "$state/repos/demo/tasks/T-900-01.md"

toolset() { # <stack> [<command>|<binding>]...: the repo toolset, one table row per pair
  ts_stack=$1; shift
  {
    printf -- '---\nstack: %s\ntest-globs:\n  - "**/test/**"\n  - "**/*.test.js"\n  - "**/*.test.sh"\n  - "**/*Tests.cs"\n---\n\n' "$ts_stack"
    printf '| command | binding |\n|---|---|\n'
    while [ $# -ge 2 ]; do printf '| `%s` | `%s` |\n' "$1" "$2"; shift 2; done
  } > "$state/repos/demo/toolset.md"
}

# the fixture: a Node repo at a base commit, then the block's changes left in the working tree, which is what
# block-verify.sh diffs against the base
repo() { # <dir>
  mkdir -p "$1/test"
  git init -q -b main "$1"
  printf '{"name": "demo", "version": "1.0.0", "scripts": {"test": "node --test"}}\n' > "$1/package.json"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@t commit -q -m init
}
passing() { printf "const test = require('node:test');\ntest('ok', () => {});\n" > "$1"; }
failing() { printf "const test = require('node:test');\ntest('bad', () => { throw new Error('red'); });\n" > "$1"; }

verify() { # <worktree> -> stdout in $out, stderr in $err, exit code in $rc
  git -C "$1" add -A
  out=$(sh "$bin/block-verify.sh" T-900-01 --state "$state" --worktree "$1" --base main 2>"$tmp/err"); rc=$?
  err=$(cat "$tmp/err")
}

# --- a node stack: each changed JS test file runs directly -------------------------------------------------------
repo "$tmp/both"
passing "$tmp/both/test/a.test.js"
failing "$tmp/both/test/b.test.js"
toolset node 'test' 'timeout 5m npm test' 'test-filter <expr>' 'timeout 5m node --test --test-name-pattern "<expr>"'
verify "$tmp/both"
has 'node stack: one passing and one failing file run one by one' 'tests: 2 run, 1 passed, 1 failed' "$out"
has 'node stack: red' 'verdict: red' "$out"
check 'node stack: exit 1' 1 "$rc"
has 'node stack: the failing command is node --test on the failing file' 'first failing command: timeout 10m node --test test/b.test.js' "$err"

repo "$tmp/green"
passing "$tmp/green/test/a.test.js"
passing "$tmp/green/test/c.spec.js"
verify "$tmp/green"
has 'node stack: a .test.js and a .spec.js both run' 'tests: 2 run, 2 passed, 0 failed' "$out"
has 'node stack: green' 'verdict: green' "$out"
check 'node stack: exit 0' 0 "$rc"

# --- another stack: the plain `test` binding, once per verify -----------------------------------------------------
toolset js 'test' 'timeout 5m npm test' 'test-filter <expr>' 'timeout 5m node --test --test-name-pattern "<expr>"'
verify "$tmp/both"
has 'test binding: two changed files are one run of npm test' 'tests: 1 run, 0 passed, 1 failed' "$out"
has 'test binding: the failing command is the test binding' 'first failing command: timeout 5m npm test' "$err"
check 'test binding: exit 1' 1 "$rc"

mkdir -p "$tmp/green/test/sub"
passing "$tmp/green/test/sub/d.test.js"
verify "$tmp/green"
has 'test binding: three passing files are one green run' 'tests: 1 run, 1 passed, 0 failed' "$out"
check 'test binding: exit 0' 0 "$rc"

# --- a test-filter that takes a file: one run per file ------------------------------------------------------------
toolset js 'test' 'timeout 5m npm test' 'test-filter <file>' 'timeout 5m node --test <file>'
verify "$tmp/both"
has 'test-filter <file>: one run per file' 'tests: 2 run, 1 passed, 1 failed' "$out"
has 'test-filter <file>: the file is substituted' 'first failing command: timeout 5m node --test test/b.test.js' "$err"

# --- sh and .NET stay as they were ---------------------------------------------------------------------------------
repo "$tmp/sh"
printf 'exit 0\n' > "$tmp/sh/test/x.test.sh"
printf 'class XTests {}\n' > "$tmp/sh/test/XTests.cs"
toolset sh
verify "$tmp/sh"
has 'sh: a .test.sh runs, a *Tests.cs without test-filter does not' 'tests: 1 run, 1 passed, 0 failed' "$out"
toolset dotnet 'test-filter <expr>' 'echo filter "<expr>" > filter.out'
verify "$tmp/sh"
has 'dotnet: *Tests.cs runs through test-filter <expr> by its base name' 'tests: 2 run, 2 passed, 0 failed' "$out"
check 'dotnet: the expr is the base name' 'filter XTests' "$(cat "$tmp/sh/filter.out" 2>/dev/null)"

exit "$fail"
