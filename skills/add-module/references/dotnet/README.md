# Adding a module

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

Sources are `@references/dotnet/templates/`; the reference structure and visibility table are in `@references/dotnet/templates/README.md`. The result is three projects plus host registration, **ending on a green build**.

## Steps

### 1. Establish the target repo's conventions

- Root namespace (templates use `Acme`), module location (templates assume `src/Modules/<Module>/`), `TargetFramework`, and `LangVersion`. Read all four from existing sibling modules, not from the template. For the first module in a flat repo, ask the user for the root namespace and confirm the location.
- If `LangVersion` is below C# 14, plan to write the registration extensions in the classic `this`-parameter form; the template's comment confirms it is binary-equivalent.
- Module name: PascalCase, singular/plural matching sibling modules. Auto-discovery in the architecture tests keys off `{Root}.{Module}.{Layer}` assembly names, so this naming is load-bearing.

### 2. Create the projects from the templates

Copy `@references/dotnet/templates/Domain.csproj.template`, `@references/dotnet/templates/Application.csproj.template`, `@references/dotnet/templates/Infrastructure.csproj.template` to `src/Modules/<Module>/<Root>.<Module>.<Layer>/<Root>.<Module>.<Layer>.csproj` and adjust:

- Substitute `__MODULE__` → module name and `Acme` → real root namespace, including inside `InternalsVisibleTo`; those names must match the actual assembly names or internal visibility silently fails. The `<Root>.<Module>.Tests` entry backs an optional per-module test project; leave it in place.
- Add `<TargetFramework>` matching the siblings; the templates carry none.
- Delete the EF Core `PackageReference` from the Infrastructure project until the module actually has persistence; when persistence arrives, add the matching `PackageVersion` to `Directory.Packages.props` first.
- Create `Application/Contracts`, `Application/Ports`, `Application/Features` (with `.gitkeep`, or directly with the first contract if the user provided one).
- Reference direction: Domain → nothing, Application → Domain, Infrastructure → Application.

### 3. Registration entry point

`@references/dotnet/templates/ModuleExtensions.cs.template` → `<Root>.<Module>.Infrastructure/<Module>ModuleExtensions.cs`. Placeholders in the file and its commented lines: `__MODULE__`, `__module__` (lowercase, route path), `__ENTITY__`, `__USECASE__`. Uncomment registrations only for what the module really has. On a pre-C# 14 repo, write the classic extension-method form from step 1. `@references/dotnet/templates/DesignTimeDbContextFactory.cs.template` comes into play only when the module gains EF migrations; it is public by design and already whitelisted in `AllowedPublicTypeSuffixes`.

### 4. Wire into the solution and host

- `dotnet sln add` for all three projects.
- Host: `ProjectReference` to the module's Infrastructure project, plus calls to `Add<Module>Module(configuration)` and `Map<Module>Module()` next to the other modules' registrations.
- What the tests actually enforce here: `CompositionRootTests` fails when the host touches `Domain` or `Features` namespaces; the "every module registered" check is informational only, so verify the two calls yourself. And the composition-root tests key off `HostAssemblyName` (default `{Root}.Host`); if the host is named differently, update it in `ArchitectureConventions.cs`, otherwise those tests silently pass.

### 5. Wire into the architecture tests

If the repo has the kit's architecture tests (installed by `architecture-tests`), check which convention each file uses before editing:

- `ArchitectureConventions.cs`: `Modules` defaults to auto-discovery (`DiscoverModules()` from `{Root}.{Module}.{Layer}` assembly names), so there is nothing to add. Add the name only if the repo replaced it with an explicit list.
- `Architecture.Tests.csproj`: the kit default globs `src\Modules\**\*.csproj`, which picks up the new projects automatically. Add explicit `ProjectReference`s only if the repo lists projects explicitly. Either way, the test project must end up referencing the module; without a reference, discovery skips it silently.

These are the only legitimate test edits for a new module; `GrandfatheredNamespaces`, `MaxGrandfatheredTypes`, and `AllowedPublicTypeSuffixes` stay untouched.

### 6. Verify

```bash
dotnet build && timeout 15m dotnet test
```

## Done when

Build and tests are green, the host registers the module through both extension points, the module is visible to the architecture tests (via discovery or explicit references, confirmed, not assumed), and the module's only public types are its (possibly still empty) Contracts/Ports and `<Module>ModuleExtensions`.
