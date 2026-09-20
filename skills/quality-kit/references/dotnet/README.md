# Quality kit: the C# / .NET phase map

The phases of `SKILL.md` on a .NET solution. Every phase ends on a green `dotnet build`; strictness only
ever rises on green.

| Phase | Skill | .NET specifics |
|---|---|---|
| 0 | `analyze-structure` | project inventory, `<ProjectReference>` graph, `AnalysisMode` debt measurement |
| 1-2 | `setup-guardrails` | analyzers through `Directory.Build.props`, `.editorconfig` severities, `BannedSymbols.*.txt`, `QualityLevel=Baseline` |
| 3 | `architecture-tests` | NetArchTest project, tests enabled one at a time, `GrandfatheredNamespaces` ceilings |
| 4 | manual, below | `QualityLevel=Standard` |
| 5 | manual, below | `QualityLevel=Strict` |

## Phase 4: escalate to error (when phases 0-3 are green and stable)

```xml
<QualityLevel>Standard</QualityLevel>
```

This turns on `TreatWarningsAsErrors` **in CI only**. Local builds keep
warnings, so iteration doesn't hurt, but nothing red reaches main. Pin
`AnalysisLevel` to a concrete version (e.g. `<AnalysisLevel>10.0</AnalysisLevel>`)
so an SDK upgrade can't surprise the build with new rules.

## Phase 5: metrics (optional)

`QualityLevel=Strict` enables `CodeMetricsConfig.txt` and code style in
build. Tuning, not rescue; do it only once the earlier phases hold.

## Anti-patterns

- **Disabling a rule instead of fixing.** If a rule blocks a legitimate change, adjust the rule in the kit with a comment why. No `#pragma` without justification.
- **Growing `AllowedPublicTypeSuffixes`.** Each added suffix is a hole in the visibility model. Only two legitimate reasons: a framework demands a public type, or it's a registration extension.
- **A baseline that never shrinks.** File an issue with a deadline for every freeze.
- **`AnalysisMode=All`.** Adds rules like CA1303 that are pure noise in a business app. `Recommended` plus targeted category tightening wins.
