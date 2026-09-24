---
stack: dotnet
crap-threshold: 8
db-schema:
  - "**/Migrations/**"
  - "**/*.sql"
api-contracts:
  - "**/openapi*.json"
  - "**/openapi*.yaml"
  - "**/openapi*.yml"
  - "**/swagger*.json"
  - "**/*.proto"
test-globs:
  - "**/tests/**"
  - "**/*Tests.cs"
---

# Toolset — C# / .NET

Command names are the contract (ADR-0039); the right-hand side is what this repo runs. A command that is
not listed here does not exist for this repo — note it and move on.

| command | binding |
|---|---|
| `build` | `dotnet build {{solution}} -warnaserror -v q --nologo` |
| `test` | `timeout 15m dotnet test {{solution}}` |
| `test-filter <expr>` | `timeout 15m dotnet test {{solution}} --filter "<expr>"` |
| `coverage` | `timeout 15m dotnet test {{solution}} --collect:"XPlat Code Coverage" && reportgenerator -reports:"**/coverage.cobertura.xml" -targetdir:.coverage -reporttypes:TextSummary` |
| `mutation <scope>` | `dotnet stryker --mutate "<scope>" --break-at <n>` |
| `crap <scope>` | `DOTNET_ROLL_FORWARD=Major dotnet-crap analyze "<scope>" --coverage .coverage/Cobertura.xml --threshold 8` |
| `format` | `dotnet format whitespace {{solution}} --include <the changed files>` |
| `format-verify` | `dotnet format whitespace {{solution}} --verify-no-changes --include <the changed files>` |
| `find-refs <symbol>` | `grep -rn "<symbol>" --include=*.cs .` |
| `hotspots` | `reportgenerator -reports:"**/coverage.cobertura.xml" -targetdir:.coverage -reporttypes:HtmlInline` |
| `arch-build` | `likec4 build --no-use-dot docs/architecture` |

`build` is quiet and bannerless so a failure prints diagnostics, not a 19k-char log. A binding cell is a
shell command and holds nothing else: `block-verify.sh` and `block-merge.sh` split the row on `|`, strip the
backquotes and run the rest, so a note beside the command runs as shell. The notes live here.

`test-filter` takes VSTest's `--filter "<expr>"`. A repo on xunit.v3 under Microsoft.Testing.Platform takes
`--filter-query "<expr>"` instead; change the binding when the repo is seeded.

`coverage` writes `.coverage/`, which `crap` reads, so run `coverage` first. `crap` runs on the newest
runtime; the tool's default threshold is 30, changed code is held to the `crap-threshold:` above, which
`block-verify.sh` reddens a block over.

`mutation`'s `<n>` is the score the task's `## Acceptance` demands; the run exits non-zero below it.

`find-refs` is a grep over the C# sources. With an LSP session, the C# language server's find-references
over the solution (Roslyn `FindReferencesAsync`) is more precise; read the grep hits either way.

`hotspots` writes the Risk Hotspots page, the CRAP ranking for the whole repo.

`arch-build` exists once the repo has a model. `--no-use-dot` uses likec4's bundled WASM Graphviz, so no
native `dot` is needed on PATH.

`dotnet format` without a subcommand also runs analyzers and exits 2 on an IDE* diagnostic — that is a style
finding, not a formatting failure; scope the run to the block's files so a block never reformats unrelated ones.

`crap` binds to Crap4DotNet (the binary `dotnet-crap`; the `analyze` subcommand is required), `hotspots` to
ReportGenerator Risk Hotspots. Install: `dotnet tool install -g dotnet-reportgenerator-globaltool`,
`dotnet tool install -g Crap4DotNet`, `dotnet tool install -g dotnet-stryker`, `npm i -g likec4` — `factory doctor`
reports which are missing.
