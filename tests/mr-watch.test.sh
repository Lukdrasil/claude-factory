#!/bin/sh
# mr-watch.sh over a glab stub: F31, the parent's own task MR is watched beside its block MRs, so the lead learns
# the human merged it without being told; a merged parent prints `<T-id> merged` and is not set done here
# (task-done.sh does that behind the done gate).
set -u
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
check() { # <label> <0 want match | 1 want none> <pattern> <text>
  if printf '%s\n' "$4" | grep -qE "$3"; then got=0; else got=1; fi
  if [ "$got" -eq "$2" ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

state="$tmp/factory/state"
mkdir -p "$state/repos/demo/tasks" "$tmp/bin" "$tmp/mrs"
printf 'demo: {url: "https://forge.test/g/demo.git", default_branch: main, path: "%s"}\n' "$tmp/clone" > "$state/repos.yml"
printf -- '---\nid: T-501\nrepo: demo\nstatus: review\nbranch: feat/T-501-x\nmr_url: https://forge.test/g/demo/-/merge_requests/9\n---\n\n# Goal\nfeat(demo): x\n' \
  > "$state/repos/demo/tasks/T-501.md"
printf -- '---\nid: T-501-01\nrepo: demo\nstatus: done\nbranch: block/T-501-01\nmr_url: https://forge.test/g/demo/-/merge_requests/8\n---\n\n# Goal\nfeat(demo): y\n' \
  > "$state/repos/demo/tasks/T-501-01.md"
cat > "$tmp/bin/glab" <<STUB
#!/bin/sh
[ "\$1 \$2" = "mr view" ] || exit 1
cat "$tmp/mrs/\${3##*/}.json"
STUB
chmod +x "$tmp/bin/glab"
mr() { printf '{"iid":%s,"state":"%s","user_notes_count":0}\n' "$1" "$2" > "$tmp/mrs/$1.json"; }
watch() { PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-501 --once --state "$state" 2>&1; }
seen="$tmp/factory/demo/.harness/T-501/mr-watch.state"

mr 8 merged
mr 9 opened
printf 'T-501-01 merged 0\n' > "$tmp/seen0" && mkdir -p "${seen%/*}" && cp "$tmp/seen0" "$seen"
out=$(watch)
check 'an open task MR prints nothing'            1 'T-501 ' "$out"
check 'the task MR is in the state file'          0 '^T-501 open 0$' "$(cat "$seen")"
mr 9 merged
out=$(watch)
check 'a merged task MR prints <T-id> merged'     0 '^T-501 merged$' "$out"
check 'the state file keeps it merged'            0 '^T-501 merged 0$' "$(cat "$seen")"
check 'the parent is not set done by the watcher' 0 '^status: review$' "$(cat "$state/repos/demo/tasks/T-501.md")"
out=$(watch)
check 'the merge is reported once'                1 'T-501 merged' "$out"

# GitHub: a review with inline threads leaves the PR open; the reviews and the inline comments are counted
mkdir -p "$state/repos/gh/tasks"
printf 'gh: {url: "https://github.com/o/gh.git", default_branch: main, path: "%s"}\n' "$tmp/clone" >> "$state/repos.yml"
printf -- '---\nid: T-502\nrepo: gh\nstatus: review\nbranch: feat/T-502-x\nmr_url: https://github.com/o/gh/pull/7\n---\n\n# Goal\nfeat(gh): x\n' \
  > "$state/repos/gh/tasks/T-502.md"
cat > "$tmp/bin/gh" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "pr view") cat "$tmp/mrs/pr7.json" ;;
  api*) cat "$tmp/mrs/inline7.txt" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
printf '{"state":"OPEN","reviewDecision":"","comments":[],"reviews":[],"statusCheckRollup":[]}\n' > "$tmp/mrs/pr7.json"
printf '0\n' > "$tmp/mrs/inline7.txt"
watch2() { PATH="$tmp/bin:$PATH" sh "$root/bin/mr-watch.sh" T-502 --once --state "$state" 2>&1; }
out=$(watch2)
check 'a GitHub PR with no review prints nothing'   1 'T-502 ' "$out"
printf '{"state":"OPEN","reviewDecision":"","comments":[],"reviews":[{"body":"looks off, see threads","state":"COMMENTED"}],"statusCheckRollup":[]}\n' > "$tmp/mrs/pr7.json"
printf '2\n' > "$tmp/mrs/inline7.txt"
out=$(watch2)
check 'a review as Comment with inline threads is counted' 0 '^T-502 new-comments 3$' "$out"
log=$(PATH="$tmp/bin:$PATH" sh -c 'gh api repos/o/gh/pulls/7/comments --jq length')
check 'the inline count comes from the pulls comments endpoint' 0 '^2$' "$log"

exit $fail
