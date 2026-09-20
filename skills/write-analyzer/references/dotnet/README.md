# Writing a custom DDD analyzer

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

The rule set lives in the **target repo's** `analyzers/` directory. If the repo does not have one yet, install it first: copy this skill's `@references/dotnet/analyzers/` folder into the repo and wire it per `@references/dotnet/analyzers/README.md` (per-project references, or globally via `analyzers-wireup.props` after fixing its relative path). Start from whichever exemplar matches the new rule: `@references/dotnet/analyzers/AggregateRootSetterAnalyzer.cs` (DDD001, syntax-only) or `@references/dotnet/analyzers/ConstructorDependencyCountAnalyzer.cs` (DDD002, configurable threshold). Deeper reference: `@references/dotnet/analyzers/README.md` and the RoslynAnalyzerCookbook linked there.

## Steps

### 1. Confirm an analyzer is the right tool

A custom analyzer is written only when nothing existing covers the rule:

- module boundaries, references, visibility → the repo's architecture-test project (installed by `architecture-tests`)
- banning a specific API → one line in `BannedSymbols.*.txt` (cheapest, consider first)
- complexity, coupling, style → an existing CA/S/MA rule in `.editorconfig`

A rule needing syntax or semantic context (what is an aggregate, what is injected) → custom analyzer. Tell the user which option you chose and why.

### 2. Create the diagnostic

- ID: next free `DDDnnn` (check the existing ones). File `<Rule>Analyzer.cs` in the repo's `analyzers/`, `[DiagnosticAnalyzer(LanguageNames.CSharp)]`, category `DDD`, `defaultSeverity: Warning`.
- **MessageFormat is the interface for the agent and the junior alike**: what is wrong AND the specific change that fixes it. DDD001 is the model ("Change it to 'private set' … and add a domain method…"). A message without the second half steers the reader toward a pragma instead of the fix.
- The project pins `netstandard2.0` (a Roslyn requirement) and `EnforceExtendedAnalyzerRules=true`; workspace-layer APIs will fail the build, so stay on the syntax/semantic layer.
- `ConfigureGeneratedCodeAnalysis(None)` + `EnableConcurrentExecution()` in `Initialize` (see the exemplars).
- Write the descriptor and an empty `Initialize` first; the `Analyze` body comes after the tests exist (step 4).

### 3. Thresholds from .editorconfig

Values that differ per layer (limits, base-type lists) are read from `AnalyzerConfigOptions` with the `ddd_` prefix; the pattern is in DDD002 (`ddd_max_constructor_dependencies`). A different strictness in a different layer then needs no recompilation.

### 4. Tests: red before green

Use `Microsoft.CodeAnalysis.Testing`; the `[|...|]` markup for expected diagnostics is shown in `@references/dotnet/analyzers/README.md`. If the repo's `analyzers/` has no test project yet, create `Acme.Analyzers.Tests/` inside it (xunit + `Microsoft.CodeAnalysis.CSharp.Analyzer.Testing`, using `CSharpAnalyzerTest<TAnalyzer, DefaultVerifier>`); the analyzer csproj already excludes that folder from its own compile glob. The `PackageVersion` entries the analyzer and its tests need are listed in `@references/dotnet/analyzers/README.md`; add them only if the consuming repo's CPM file lacks them, and where guardrails deny that file, this is a human-approved edit: ask.

`TestCode` must declare every base type the analyzer keys off (stub `AggregateRoot` etc. inside the test string; the test compilation sees nothing else). Three cases minimum:

1. a violation is reported; this test runs red before the `Analyze` body exists, which proves the test tests
2. correct code stays silent
3. the rule's boundary case (e.g. a private setter stays silent for DDD001; a non-injected framework parameter for DDD002)

### 5. Wire up and set severity

- Wiring into consuming projects: `ProjectReference` with `OutputItemType="Analyzer"`; procedure and the global variant are in `@references/dotnet/analyzers/README.md` and `@references/dotnet/analyzers/analyzers-wireup.props`.
- Severity and thresholds go into the **consuming repo's** `.editorconfig`, in the section of the layer where the rule applies (`dotnet_diagnostic.DDDnnn.severity = warning`). When working inside the kit itself, also mirror the default into the `setup-guardrails` skill's `references/dotnet/build/.editorconfig` so newly guarded repos ship with it. Where guardrails deny `.editorconfig` edits, this is a human-approved change: ask.
- Add the rule's row to the table in the repo's `analyzers/README.md`: ID, rule, why a custom analyzer (in the kit itself, that file is `@references/dotnet/analyzers/README.md`).

### 6. Verify on real code

`dotnet build` of the target solution: the analyzer reports where it should and nowhere else. If it fires many times on existing code, treat the rollout as debt (downgrade the severity for legacy folders in `.editorconfig`, or grandfather the namespaces in the architecture tests); the severity default stays.

## Done when

The step-4 tests are green having been red first, the analyzer is wired, severity and thresholds are in `.editorconfig`, the row is in the `analyzers/README.md` table, and the target solution's build is green or its findings are frozen with a baseline technique.
