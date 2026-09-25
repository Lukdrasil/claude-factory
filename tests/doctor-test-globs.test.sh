#!/bin/sh
# factory-doctor.sh's coverage collector check run from inside the clone, the way onboarding runs it: the test-globs
# `test/**` and `**/*Tests.cs` are matched as patterns against each *.csproj, never expanded by the shell against the
# clone's files, so a test project the globs alone name is found and its Directory.Build.props collector counts.
set -u
bin=$(CDPATH= cd -- "$(dirname -- "$0")/../bin" && pwd)
tmp=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
unset WORK_DIR

fail=0
check() { # <what> <expected> <actual>
  if [ "$2" = "$3" ]; then printf 'PASS %s\n' "$1"
  else printf 'FAIL %s:\n  expected [%s]\n  got      [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

clone="$tmp/demo"
mkdir -p "$clone/test/Demo.Tests" "$tmp/state/repos/demo"
git init -q "$clone"
git -C "$clone" remote add origin https://example.invalid/demo.git
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' > "$clone/test/Demo.Tests/Demo.Tests.csproj"
printf '<Project>\n  <PackageReference Include="Microsoft.Testing.Extensions.CodeCoverage" />\n</Project>\n' \
  > "$clone/test/Directory.Build.props"
printf 'class DemoTests {}\n' > "$clone/test/Demo.Tests/DemoTests.cs"
printf 'demo: { path: %s }\n' "$clone" > "$tmp/state/repos.yml"
cat > "$tmp/state/repos/demo/toolset.md" <<'EOF'
---
stack: dotnet
test-globs:
  - "test/**"
  - "**/*Tests.cs"
---

| command | binding |
|---|---|
| `coverage` | dotnet test |
EOF

out=$(cd "$clone" && sh "$bin/factory-doctor.sh" --root "$tmp" --repo "$clone" 2>&1 | grep 'coverage collector')
check "run from the clone, the globs find the test project and its collector" \
  "ok: a coverage collector in a test project (test/Directory.Build.props)" "$out"

exit "$fail"
