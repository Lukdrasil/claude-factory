#!/bin/sh
# review-sweep.sh over a glab stub: every live parent in review with an mr_url gets one mr-watch.sh --once
# --finish pass, so a task MR merged while no session watched ends its task; an open MR, a parent in another
# status, a parent with no mr_url and a block are left alone, and only the finish lines are printed.
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
mkdir -p "$state/repos/demo/tasks" "$state/repos/other/tasks" "$tmp/bin" "$tmp/mrs"
printf 'demo: {url: "https://forge.test/g/demo.git", default_branch: main, path: "%s/demo"}\nother: {url: "https://forge.test/g/other.git", path: "%s/other"}\n' \
  "$tmp" "$tmp" > "$state/repos.yml"
task() { # <key> <id> <status> <mr iid or null>
  url=null
  [ "$4" = null ] || url="https://forge.test/g/$1/-/merge_requests/$4"
  printf -- '---\nid: %s\nrepo: %s\narchetype: feature\nstatus: %s\nowner: factory@h:s1\nbranch: feat/%s\nmr_url: %s\n---\n\n# Goal\nfeat(%s): %s\n' \
    "$2" "$1" "$3" "$2" "$url" "$1" "$2" > "$state/repos/$1/tasks/$2.md"
}
mr() { printf '{"iid":%s,"state":"%s","user_notes_count":0}\n' "$1" "$2" > "$tmp/mrs/$1.json"; }
cat > "$tmp/bin/glab" <<STUB
#!/bin/sh
[ "\$1 \$2" = "mr view" ] || exit 1
cat "$tmp/mrs/\${3##*/}.json" 2>/dev/null || exit 1
STUB
chmod +x "$tmp/bin/glab"

task demo T-601 review 1;      mr 1 merged
task demo T-602 review 2;      mr 2 opened
task demo T-603 in_progress 3; mr 3 merged
task demo T-604 review null
task demo T-601-01 review 5;   mr 5 merged
task other T-701 review 7;     mr 7 merged
git init -q "$state"
git -C "$state" config user.email harness@localhost
git -C "$state" config user.name harness
git -C "$state" add -A
git -C "$state" commit -q -m init

st() { sed -n 's/^status:[[:space:]]*//p' "$(ls "$state"/repos/*/tasks/"$1".md "$state"/repos/*/archive/*/tasks/"$1".md 2>/dev/null | head -n1)"; }
sweep() { PATH="$tmp/bin:$PATH" sh "$root/bin/review-sweep.sh" "$@" --state "$state" 2>&1; }

out=$(sweep --repo demo)
check 'a merged task MR in review is finished'     0 '^T-601 done$' "$out"
check 'its parent is done'                         0 '^done$' "$(st T-601)"
check 'its block is done with it'                  0 '^done$' "$(st T-601-01)"
check 'an open task MR prints nothing'             1 'T-602' "$out"
check 'and stays in review'                        0 '^review$' "$(st T-602)"
check 'a parent not in review is left alone'       0 '^in_progress$' "$(st T-603)"
check 'a parent with no mr_url is left alone'      0 '^review$' "$(st T-604)"
check 'mr-watch event lines are not printed'       1 'merged|retargeted' "$out"
check '--repo leaves another repo alone'           0 '^review$' "$(st T-701)"

out=$(sweep)
check 'without --repo every repo is swept'         0 '^T-701 done$' "$out"
check 'a finished task is not finished again'      1 'T-601' "$out"

out=$(sweep --bogus); rc=$?
check 'an unknown argument is refused'             0 "unknown argument" "$out"
[ "$rc" = 1 ] && printf 'PASS and exits 1\n' || { printf 'FAIL and exits 1\n'; fail=1; }

exit $fail
