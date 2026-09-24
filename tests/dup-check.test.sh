#!/bin/sh
# dup-check.sh (T-228-04, F12): the repo files come from `git ls-files`, a name matches only within one language
# and never in markdown, an added name yields one line, and a 12,000-line diff against a 2,000-file repo
# finishes under 30 s. The CLI and the output line format stay as they were.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
check() { # <what> <0 = ok>
  if [ "$2" -eq 0 ]; then printf 'PASS %s\n' "$1"; else printf 'FAIL %s\n' "$1"; fail=1; fi
}

repo() { # <dir>
  git init -q "$1"
  git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}
put() { # <repo> <path>, the content on stdin
  mkdir -p "$(dirname "$1/$2")"
  cat > "$1/$2"
}
commit() { # <repo>
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@t commit -q -m step
}
run() { # <repo>: diff of the last commit, then dup-check over it; stdout in $out, exit code in $rc
  git -C "$1" diff HEAD~1 HEAD > "$1.diff"
  out=$(sh "$bin/dup-check.sh" "$1.diff" "$1")
  rc=$?
}
lines() { printf '%s' "$out" | grep -c . ; }

# ---- the CLI --------------------------------------------------------------------------------------------
sh "$bin/dup-check.sh" "$tmp/nothing" >/dev/null 2>&1
[ $? -eq 1 ]; check 'one argument is a usage error, exit 1' $?
sh "$bin/dup-check.sh" "$tmp/nothing.diff" "$tmp" >/dev/null 2>&1
[ $? -eq 1 ]; check 'a missing diff file is exit 1' $?
: > "$tmp/empty.diff"
sh "$bin/dup-check.sh" "$tmp/empty.diff" "$tmp/no-such-dir" >/dev/null 2>&1
[ $? -eq 1 ]; check 'a repo directory that is not one is exit 1' $?

# ---- a diff with no added line has no candidate ---------------------------------------------------------
r=$tmp/removed; repo "$r"
printf 'load_config() {\n  echo a\n}\n' | put "$r" lib/util.sh; commit "$r"
rm "$r/lib/util.sh"; commit "$r"
run "$r"
[ "$rc" -eq 0 ] && [ -z "$out" ]; check 'a removal-only diff prints nothing, exit 0' $?

# ---- a same-language name, in the unchanged line format ------------------------------------------------
r=$tmp/samelang; repo "$r"
printf '#!/bin/sh\n\nload_config() {\n  echo a\n}\n' | put "$r" lib/util.sh; commit "$r"
printf '#!/bin/sh\nloadConfig() {\n  echo b\n}\n' | put "$r" bin/new.sh; commit "$r"
run "$r"
[ "$out" = 'loadConfig lib/util.sh:3 same normalized name, added at bin/new.sh:2' ]
check 'a same-language normalized name is one line: <name> <path:line> same normalized name, added at <file:line>' $?
[ "$rc" -eq 0 ]; check 'a candidate is still exit 0' $?

# ---- a copied six-line block, in the unchanged line format ---------------------------------------------
r=$tmp/window; repo "$r"
printf '#!/bin/sh\necho one\necho two\necho three\necho four\necho five\necho six\n' | put "$r" lib/a.sh; commit "$r"
printf '#!/bin/sh\nset -eu\necho zero\n  echo one\n  echo  two\n\techo three\n  echo four\n  echo five\n  echo six\n' \
  | put "$r" bin/b.sh; commit "$r"
run "$r"
[ "$out" = 'bin/b.sh:4+6 lib/a.sh:2 same 6 trimmed lines' ]
check 'a copied block, reindented, is one line: <file:line+6> <path:line> same 6 trimmed lines' $?

# ---- the diff never matches its own files --------------------------------------------------------------
r=$tmp/self; repo "$r"
printf 'run_all() {\n  echo a\n}\n' | put "$r" lib/self.sh; commit "$r"
printf 'run_all() {\n  echo a\n}\nrun_all() {\n  echo b\n}\n' | put "$r" lib/self.sh; commit "$r"
run "$r"
[ -z "$out" ]; check 'a name the diff repeats inside its own file is no candidate' $?

# ---- the cap -------------------------------------------------------------------------------------------
r=$tmp/cap; repo "$r"
i=1; while [ $i -le 25 ]; do printf 'fn_%02d() {\n  echo r%d\n}\n' $i $i; i=$((i + 1)); done | put "$r" lib/many.sh
commit "$r"
i=1; while [ $i -le 25 ]; do printf 'fn_%02d() {\n  echo a%d\n}\n' $i $i; i=$((i + 1)); done | put "$r" bin/many.sh
commit "$r"
run "$r"
[ "$(lines)" -eq 20 ]; check '25 candidates are capped at 20 lines' $?

# ---- a name in another language is no candidate --------------------------------------------------------
r=$tmp/crosslang; repo "$r"
printf 'def parse_args(argv):\n    return argv\n' | put "$r" lib/parse.py
printf 'load_env() {\n  echo e\n}\n' | put "$r" lib/env.sh; commit "$r"
printf 'parse_args() {\n  echo p\n}\nload_env() {\n  echo l\n}\n' | put "$r" bin/cli.sh; commit "$r"
run "$r"
! printf '%s\n' "$out" | grep -q 'lib/parse.py'; check 'an added sh name never matches a python definition' $?
[ "$out" = 'load_env lib/env.sh:1 same normalized name, added at bin/cli.sh:4' ]
check 'the same diff still finds the sh definition (positive control)' $?

# ---- markdown is never matched, as the repo side ------------------------------------------------------
r=$tmp/md-repo; repo "$r"
put "$r" docs/guide.md <<'EOF'
# Guide

```sh
render_page() {
  echo alpha
  echo beta
  echo gamma
  echo delta
  echo epsilon
  echo zeta
}
```
EOF
printf 'page_title() {\n  echo t\n}\n' | put "$r" lib/page.sh; commit "$r"
put "$r" bin/render.sh <<'EOF'
#!/bin/sh
render_page() {
  echo alpha
  echo beta
  echo gamma
  echo delta
  echo epsilon
  echo zeta
}
page_title() {
  echo u
}
EOF
commit "$r"
run "$r"
! printf '%s\n' "$out" | grep -q 'docs/guide.md'; check 'neither a name nor a block matches a markdown sample in the repo' $?
[ "$out" = 'page_title lib/page.sh:1 same normalized name, added at bin/render.sh:10' ]
check 'the same diff still finds the sh definition (positive control)' $?

# ---- markdown is never matched, as the added side -----------------------------------------------------
r=$tmp/md-added; repo "$r"
printf 'load_config() {\n  echo a\n}\nother_fn() {\n  echo o\n}\n' | put "$r" lib/util.sh; commit "$r"
printf '# Notes\n\n```sh\nload_config() {\n  echo n\n}\n```\n' | put "$r" docs/notes.md
printf 'other_fn() {\n  echo x\n}\n' | put "$r" bin/x.sh; commit "$r"
run "$r"
! printf '%s\n' "$out" | grep -q 'docs/notes.md'; check 'a name added in a markdown sample is no candidate' $?
[ "$out" = 'other_fn lib/util.sh:4 same normalized name, added at bin/x.sh:1' ]
check 'the same diff still finds the sh definition (positive control)' $?

# ---- a name added twice is one line --------------------------------------------------------------------
r=$tmp/repeat; repo "$r"
printf 'public class Store\n{\n    public void Save(int id)\n    {\n    }\n}\n' | put "$r" src/Store.cs; commit "$r"
put "$r" src/Cache.cs <<'EOF'
public class Cache
{
    public void Save(int id)
    {
    }

    public void Save(string key)
    {
    }
}
EOF
commit "$r"
run "$r"
[ "$(lines)" -eq 1 ]; check 'an overload added twice is one line' $?
printf '%s\n' "$out" | grep -q '^Save src/Store.cs:3 '; check 'the one line names the existing definition' $?

# ---- an untracked file is never read -------------------------------------------------------------------
r=$tmp/untracked; repo "$r"
printf 'function loadArgs(argv) {\n  return argv;\n}\n' | put "$r" lib/args.js; commit "$r"
printf 'function parseArgs(argv) {\n  return argv;\n}\nfunction loadArgs(argv) {\n  return [];\n}\n' \
  | put "$r" src/cli.js; commit "$r"
mkdir -p "$r/dist"
printf '\000\001\002ELF\000\nfunction parseArgs(a){return a}\n\000\377\376\n' > "$r/dist/bundle.js"
run "$r"
! printf '%s\n' "$out" | grep -q 'dist/bundle.js'; check 'an untracked binary build output is no candidate' $?
[ "$out" = 'loadArgs lib/args.js:1 same normalized name, added at src/cli.js:4' ]
check 'the same diff still finds the tracked definition (positive control)' $?

# ---- a C# keyword before `(` is never a definition name ------------------------------------------------
r=$tmp/cskeyword; repo "$r"
put "$r" src/Registry.cs <<'EOF'
public class Registry
{
    private static readonly List<int> Items = new(4);
    public string Label => nameof(Items);
    public Type Kind => typeof(int);
    public int Width => sizeof(int);
    public int Zero => default(int);
    public int Broken => throw new(nameof(Items));
    public void Load(int id)
    {
    }
}
EOF
commit "$r"
put "$r" src/Cache.cs <<'EOF'
public class Cache
{
    private readonly Dictionary<string, int> map = new();
    public string Label => nameof(map);
    public Type Kind => typeof(string);
    public int Width => sizeof(long);
    public int Zero => default(int);
    public int Broken => throw new(nameof(map));
    public void Load(string key)
    {
    }
}
EOF
commit "$r"
run "$r"
[ "$out" = 'Load src/Registry.cs:9 same normalized name, added at src/Cache.cs:9' ]
check 'new, nameof, typeof, sizeof, default and throw before ( are no candidate, the real method is' $?

# ---- QS-03: 12,000 added lines against a 2,000-file repo under 30 s -----------------------------------
r=$tmp/big; repo "$r"
mkdir -p "$r/lib" "$r/bin"
awk -v d="$r/lib" 'BEGIN {
  for (n = 1; n <= 2000; n++) {
    f = sprintf("%s/f%04d.sh", d, n)
    print "#!/bin/sh" > f
    for (k = 1; k <= 2; k++) {
      s = (k == 1) ? "a" : "b"
      printf "repo_fn_%d_%s() {\n", n, s > f
      for (j = 1; j <= 8; j++) printf "  echo \"repo %d %s %d\"\n", n, s, j > f
      print "}" > f
    }
    close(f)
  }
}'
commit "$r"
awk -v d="$r/bin" 'BEGIN {
  for (k = 1; k <= 40; k++) {
    f = sprintf("%s/added%02d.sh", d, k)
    for (g = 1; g <= 30; g++) {
      printf "added_fn_%d_%d() {\n", k, g > f
      for (j = 1; j <= 8; j++) printf "  echo \"added %d %d %d\"\n", k, g, j > f
      print "}" > f
    }
    close(f)
  }
}'
put "$r" bin/copied.sh <<'EOF'
repoFn77A() {
  echo "copied"
}
echo "repo 1999 b 1"
echo "repo 1999 b 2"
echo "repo 1999 b 3"
echo "repo 1999 b 4"
echo "repo 1999 b 5"
echo "repo 1999 b 6"
EOF
commit "$r"
git -C "$r" diff HEAD~1 HEAD > "$r.diff"
added=$(grep -c '^+[^+]' "$r.diff")
[ "$added" -ge 12000 ]; check "the synthetic diff adds at least 12,000 lines ($added)" $?
start=$(date +%s)
out=$(timeout 30 sh "$bin/dup-check.sh" "$r.diff" "$r")
rc=$?
secs=$(( $(date +%s) - start ))
[ "$rc" -eq 0 ]; check "12,000 added lines against 2,000 files finish under 30 s (exit $rc, ${secs} s)" $?
printf '%s\n' "$out" | grep -qx 'repoFn77A lib/f0077.sh:2 same normalized name, added at bin/copied.sh:1'
check 'the large run still finds the one renamed definition (positive control)' $?
printf '%s\n' "$out" | grep -qx 'bin/copied.sh:4+6 lib/f1999.sh:13 same 6 trimmed lines'
check 'the large run still finds the one copied block (positive control)' $?
[ "$(lines)" -eq 2 ]; check 'the large run prints exactly those two candidates' $?

exit $fail
