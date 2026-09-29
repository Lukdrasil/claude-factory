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

exit $fail
