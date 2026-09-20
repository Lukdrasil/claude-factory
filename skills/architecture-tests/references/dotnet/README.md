# Installing the architecture tests

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

Sources are `@references/dotnet/tests/`. This phase comes **after** `setup-guardrails`; enabling tests before the analyzer build is green means two red things at once and nobody knows what to fix first. **Invariant: every enabled test commits green.** A failing test gets fixed (few occurrences) or its namespaces grandfathered (many), never disabled.

## Steps

### 1. Preflight

- `dotnet build` is green and the guardrails baseline is installed; if not, run `setup-guardrails` first and stop here.
- Record the facts the conventions file needs: root namespace, whether assembly names follow `{Root}.{Module}.{Layer}` (auto-discovery needs at least three dot-separated segments), the host project's assembly name, and how modules communicate (synchronous Contracts vs integration events; events change the boundary rules, see @references/dotnet/integration-events.md). If `analyze-structure` already produced a proposal, read these from its report.

### 2. Create the test project

Copy `@references/dotnet/tests/*` into the repo's test folder as an `Architecture.Tests` project. Adjust `Architecture.Tests.csproj`:

- `TargetFramework` to match the repo.
- The `ProjectReference` glob `..\..\src\Modules\**\*.csproj` (plus the Host reference) to the repo's real layout; the test project must reference **every** module assembly, or `DiscoverModules()` silently misses it.
- The `PackageReference`s carry no versions. Under CPM, add `PackageVersion` entries for `NetArchTest.eNhancedEdition`, `xunit`, `xunit.runner.visualstudio`, `Microsoft.NET.Test.Sdk`, `JunitXml.TestLogger` to `Directory.Packages.props` (a human-approved edit where guardrails deny that file); without CPM, inline the versions.
- Test runner: when `global.json` pins the test runner to `Microsoft.Testing.Platform`, the kit's VSTest/xunit-v2 project is rejected by `dotnet test`; convert it to the repo's runner (xunit.v3 package, `<OutputType>Exe</OutputType>`, `<UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>`; the kit test sources compile under both).
- `dotnet sln add` the project.

### 3. Fill in the conventions

`ArchitectureConventions.cs` is the single place describing the architecture; adapting to the repo means editing this file, nothing else:

- `RootNamespace` → the repo's real prefix.
- `Modules`: keep `DiscoverModules()` when assembly names follow the convention; otherwise replace with the explicit list. For a flat monolith with no modules yet, set an explicit one-pseudo-module list: boundary tests stay off, `DomainPurityTests` works even flat, and each later module extraction adds its name here so the boundary tests start guarding it.
- Prefix-less naming (`{Module}.{Layer}` with no root, Contracts as sibling projects): the helper methods (`Ns`, `ContractsOf`, `AssembliesOf`, `LoadedAssemblies`) also need editing to the repo's shape; their header comment says so. The module-cycle test additionally needs a shared namespace prefix; without one, disable it with a `Skip` reason.
- Layer and folder names (`Domain`, `Contracts`, `Ports`, `Features`) if the repo differs.
- `IntegrationEventsFolder` when modules communicate via events.
- `HostAssemblyName` in `CompositionRootTests.cs` when the host is not named `{Root}.Host`; with a wrong name those tests silently pass.

### 4. Enable tests one at a time

Enable in this benefit/pain order:

| # | Test | Why here | Typical pain |
|---|------|----------|--------------|
| 1 | `No_dependency_cycles_between_modules` | most severe problem, usually few occurrences | low |
| 2 | `Domain_has_no_outward_dependencies` | defines what the domain actually is | medium |
| 3 | `Module_reaches_other_modules_only_through_their_public_surface` | the core of modularity | **high** |
| 4 | `Slices_do_not_depend_on_sibling_slices` | only once slices exist | medium |
| 5 | `Module_exposes_only_its_declared_surface` | most mechanical work | **high** |

For each test file: enable it, run `timeout 15m dotnet test`, and if it fails:

- **Fewer than ~10 occurrences** → fix the code and commit.
- **More** → add the affected namespaces to `GrandfatheredNamespaces`, set `MaxGrandfatheredTypes` in `DebtTrackingTests.cs` to the current measured count, commit green, and file an issue with a deadline for the cleanup; a baseline without a plan is just a slow way to disable the rule.

`GrandfatheredNamespaces` is the visible debt list; its value is that widening it shows up in code review.

### 5. Arm the debt ceilings

`DebtTrackingTests.cs`: `MaxGrandfatheredTypes` holds the measured count from step 4 (0 when nothing was grandfathered) and `MaxPublicSurfaceExceptions` stays at 2 unless the repo already needs more; each extra entry is a hole in the visibility model. From here the numbers only go down; raising one is a merge-request discussion.

### 6. Verify and gate

```bash
dotnet build && timeout 15m dotnet test
```

If CI is set up (guardrails step 7), confirm the architecture tests run in the pipeline; the CI config installed by `setup-guardrails` (its `gitlab-ci.yml`) has them as a separate job. Without CI, note in the report that they run locally only.

## Done when

All seven test files are in the repo, `ArchitectureConventions.cs` (and `HostAssemblyName`) describe the repo's reality, every enabled test is green, the ceilings hold the measured values, each grandfathered namespace has an issue with a deadline, and the report to the user lists: which tests are enabled, what was grandfathered and why, and which tests wait for a later phase (with the reason, e.g. "no slices yet").
