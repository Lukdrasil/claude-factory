# Structure analysis and restructuring proposal

The deliverable is a **proposal**, a markdown report. Restructuring itself happens only after a human approves the proposal.

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo. Shell commands are for the Bash tool (Git Bash), not PowerShell.

The target model and its rationale: @references/dotnet/MODEL.md.

## Steps

### 1. Project inventory

- Find the `.sln`/`.slnx` and list its projects (`dotnet sln <sln> list`). If the repo has no solution file, enumerate `**/*.csproj` and record that fact in the report.
- Classify each project by name AND content (names lie more often): Domain / Application / Infrastructure / Host / Tests / unclassifiable. An unclassifiable project is a finding for the report, not a blocker.
- Record the naming convention (`{Root}.{Module}.{Layer}`? flat?). This decides how `ArchitectureConventions.cs` gets filled in later: `RootNamespace`, whether `Modules` can stay on its default auto-discovery (`DiscoverModules()` requires assembly names of at least three dot-separated segments, `{Root}.{Module}.{Layer}`) or needs an explicit list, and whether the host matches the default `HostAssemblyName` of `{Root}.Host`.

Done when every project in the solution has a layer assigned or is named in the unclassified list.

### 2. Dependency map

- Build a directed graph from every `<ProjectReference>` in the `.csproj` files.
- Look for: **cycles between projects**, dependencies pointing outward from a domain (domain → EF/HTTP/logging), the host reaching past registration entry points, and `Shared`/`Common`/`Core` projects with high fan-in.

Done when the graph covers all projects and every finding cites a concrete edge (from → to).

### 3. Measure analyzer debt

Measure how many warnings each strictness would bring. `--no-incremental` is required (an incremental build re-emits nothing) and the counts are an upper bound (MSBuild repeats a warning per referencing project):

```bash
dotnet build --no-incremental -p:AnalysisMode=Minimum     -p:TreatWarningsAsErrors=false 2>&1 | grep -c "warning"
dotnet build --no-incremental -p:AnalysisMode=Recommended -p:TreatWarningsAsErrors=false 2>&1 | grep -c "warning"
dotnet build --no-incremental -p:AnalysisMode=Recommended -p:TreatWarningsAsErrors=false 2>&1 | grep -oE "warning [A-Z]+[0-9]+" | sort | uniq -c | sort -rn | head -30
```

**Decision rule**: under ~200 warnings on `Recommended` → start there; over ~1000 → start on `Minimum` and escalate per category; in between, use judgment and default to the slower path. The rule decides `AnalysisMode`; map it to the kit's `QualityLevel` as Minimum → `Baseline`, Recommended → `Standard`. Whatever it says, the **installed** start is always `Baseline`. `Standard` turns warnings into CI errors, so it is the escalation *goal*, and the measurement sets how fast to get there.

Done when three numbers are recorded: the Minimum count, the Recommended count, and the top-rules breakdown.

### 4. Confront the target model

Give each of the five model claims a verdict backed by a cited file, or an explicit "not applicable" reason:

1. Public surface = Contracts + Ports + registration extension only
2. Dependencies point inward; domain depends on nothing
3. Slices are isolated from sibling slices
4. Domain is pure (no time, identity, I/O, persistence, logging)
5. Host touches modules only through registration entry points

Also record:

- What the repo already has: `.editorconfig`, `Directory.Build.props`, architecture tests, with their current settings. The proposal builds on these instead of replacing them.
- How modules communicate (or should): synchronous Contracts vs integration events. Events change the boundary rules; record the style here. `architecture-tests` bundles the integration-events reference and applies it. If undecidable from the code, record it as an open question for the user.

Done when all five claims have verdicts, existing quality assets are listed, and the communication style is recorded or flagged as open.

### 5. The restructuring proposal

The report contains:

- **A disposition for every project**: keep / rename / split / merge / extract as module, each with its target place in the structure.
- The target module list and each module's public surface (Contracts, Ports).
- Extraction order: cycles and `Shared` projects first (they block everything else), then modules one at a time. On a flat monolith, do not rename assemblies up front. Extract one module, add its name to the architecture tests' `Modules` list, repeat; an extracted module is guarded by tests from that point on, so modularity only grows and never regresses.
- The measured numbers from step 3 and the recommended `QualityLevel` escalation.
- Phases where **each phase ends on a green build**; a phase that leaves the repo red does not belong in the proposal.

Save as `docs/restructuring-proposal.md` in the target repo (create `docs/` if missing) unless the user names another location, and summarize the main dispositions to the user.

Done when every project has a disposition, every finding from step 2 has a resolution in the proposal, and the phases can each be executed independently ending green.
