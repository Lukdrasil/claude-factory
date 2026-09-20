# Installing agent guardrails; C# / .NET

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

Sources are `@references/dotnet/build/` and `@references/dotnet/agents/`. Installed files land in the **target repo root**; `Directory.Build.props` wires its `AdditionalFiles` via `$(MSBuildThisFileDirectory)`, so the BannedSymbols and CodeMetricsConfig files must sit next to it.

**Invariant for the whole procedure: every step ends on a green `dotnet build`.** The goal of installation is infrastructure in place, not clean code; existing debt gets frozen with the techniques in @references/dotnet/BASELINE.md, and a red step gets reduced until green (the ladder in step 3).

## Steps

### 1. Preflight

- Verify a green build BEFORE touching anything; report a red repo to the user first; guardrails on a red base produce unreadable feedback.
- Find existing `.editorconfig`, `Directory.Build.props`, `Directory.Packages.props`. Rule: **merge, not overwrite**; add the kit's sections to existing files and list every conflict (same key, different value) to the user for a decision.
- Scan for nested `.editorconfig` files (`**/.editorconfig`); a deeper file overrides the root one, so guardrails can be installed yet inert. Report any file that re-declares a severity the kit sets.
- Central Package Management: the kit's `Directory.Build.props` declares analyzer `PackageReference`s **without versions**; they need CPM. Decide now: if the repo has CPM (or you introduce it), you will merge `@references/dotnet/build/Directory.Packages.props` in step 3; if not, you will inline the versions from that file into the `PackageReference`s. Tell the user which path you chose.

### 2. Measure and pick the starting strictness

Take the three measured numbers and the strictness decision from the `analyze-structure` report. Without one, run its step 3 first. The installed start is always `QualityLevel=Baseline`.

### 3. Install the build layer

Copy/merge into the target repo root: `@references/dotnet/build/Directory.Build.props`, `@references/dotnet/build/.editorconfig`, `@references/dotnet/build/BannedSymbols.Global.txt`, `@references/dotnet/build/BannedSymbols.Domain.txt`, `@references/dotnet/build/CodeMetricsConfig.txt`; plus `@references/dotnet/build/Directory.Packages.props` (merging versions) if CPM was chosen in step 1, otherwise inline the analyzer versions from it. Set `QualityLevel=Baseline`.

Naming-convention adaptation checklist (these match silently; a mismatch means the rule stays mute, not that anything errors):

- `.editorconfig` section headers key on project-name suffixes `*.Domain` / `*.Infrastructure` and folder names `Contracts` / `Ports` / `Features`. If the repo uses different tokens (e.g. `*.Core`), change only those tokens; the `**/` prefixes already match at any depth.
- `Directory.Build.props` gates the domain banned list on `$(MSBuildProjectName.EndsWith('.Domain'))` and the relaxed test mode on `EndsWith('Tests')`/`EndsWith('.Test')`; adapt both conditions to the repo's naming.

Debt trimming for the first green build:

- `BannedSymbols.Global.txt`: keep only the sync-over-async lines active, comment out the rest.
- `BannedSymbols.Domain.txt`: check it against the actual domain code and comment out any line the legacy domain violates. This file is wired to every `*.Domain` project **regardless of `QualityLevel`**, and `RS0030` is error severity; a legacy `DateTime.UtcNow` turns the build red on day one.

Verify: `dotnet build` green. If red, note that the async-correctness rules (`VSTHRD002/100/103`, `CA2012`, `CA2016`) and `RS0030` are error severity independent of `QualityLevel`; they are the first suspects. Reduce in this order until green:

1. `.editorconfig` section for legacy paths (@references/dotnet/BASELINE.md, technique B)
2. comment out more `BannedSymbols` lines
3. `NoWarn` on written-off projects (technique A)
4. lower `QualityLevel`

### 4. AGENTS.md; the rules for agents

From `@references/dotnet/agents/AGENTS.md.template`, copy **only the fenced markdown block** into `AGENTS.md` at the target repo root, the surrounding prose is instructions to you. Rewrite the Architecture and Visibility sections to describe the repo's **actual** structure. Keep the FORBIDDEN CHANGES section's wording and list of prohibited actions intact; the one edit it needs is replacing the paths with the locations where step 3 actually put the files, the same paths step 5 will use. If the team uses Copilot, duplicate into `.github/copilot-instructions.md`.

### 5. Permission deny

Merge the `deny` and `allow` lists from `@references/dotnet/agents/claude-settings.json` into the target repo's `.claude/settings.json` (keep existing permissions, drop the `_comment` key). Rewrite the deny paths to where the files actually live after step 3: the `build/` prefix goes away for files now at the repo root, and the architecture-test path becomes the repo's real test-project path. Keep the `Edit`+`Write` pairs together. Known residual gap: Bash redirection can still overwrite these files; the AGENTS.md prohibition from step 4 covers that case.

### 6. SARIF feedback

Per `@references/dotnet/agents/SARIF-WORKFLOW.md`, add the `ErrorLog` property (CI-conditioned) and put the local command into AGENTS.md's Build section: `dotnet build -p:ErrorLog=analysis.sarif,version=2.1`. Two adjustments to the doc:

- `ErrorLog` writes one SARIF **per project**; the queries must glob `**/analysis.sarif` (or use `jq -s`).
- Check that `jq` is available (`jq --version`); Git for Windows does not bundle it. If absent, write a PowerShell `ConvertFrom-Json` equivalent into AGENTS.md instead of the jq queries.

This gives the agent a structured list of its own findings instead of log parsing.

### 7. CI gate

Warning-to-error escalation activates only when `ContinuousIntegrationBuild` is set, which CI supplies via the `CI` env var. Offer `@references/dotnet/gitlab-ci.yml` (or its equivalent for the repo's CI system). If the user declines, record in the report that enforcement stays advisory until CI sets `CI`.

### 8. Optional: the custom DDD analyzers

Wire DDD001/DDD002 only on request; the analyzer sources ship with the `write-analyzer` skill (its `references/dotnet/analyzers/` folder including `analyzers-wireup.props` and README); follow that skill's install step. They need a compiled analyzer project, so they stay out of the base install.

## Done when

`dotnet build` is green, the files from steps 3–6 are in place, `AGENTS.md` describes the repo's real structure, the deny-list paths match where the files actually are, and the report to the user contains: the measured numbers, the chosen `QualityLevel` and escalation goal, the merge conflicts and how they were resolved, which `BannedSymbols` lines were commented out (= debt to re-enable), and the CI enforcement status. The natural next phase is `architecture-tests`.
