# solution-map — .NET

Paths written `@...` are relative to the skill folder; bare paths live in the target repo.

## Extractor

```sh
timeout 5m dotnet run @references/dotnet/extract.cs -- <path to .sln or .slnx> --out docs/architecture/map/map.json
```

A file-based C# app: the first run restores its Roslyn package, later runs are seconds. It parses syntax only
(no build, no MSBuild workspace), so it works on a clone that does not compile. Its caller resolution is an
identifier match: a method's callers are the types in another component that invoke a member of that name and
mention the declaring type or one of its interfaces. That is a known ceiling; a false edge reported by a reader
is the trigger to move the extractor onto a semantic model.

## What the JSON means here

- **component**: the first namespace segment after the project's `RootNamespace` (the project name when
  unset). Types directly in the root namespace form the component `""`.
- **service** (`isService`): a type registered through `Add{Singleton|Scoped|Transient|HostedService}`, a
  `BackgroundService`/`IHostedService`, an interface with more than one implementation, or a static class named
  `*Endpoints`.
- **surface**: a service's public or internal methods with at least one caller outside its component.
- Skipped on purpose: nested types, `*.g.cs` and `*.Designer.cs`, `obj/` and `bin/`.

## What the explorer should read

Blazor components (`.razor`) are UI, not services; a component made only of them gets a one-line section.
Registrations live in `Program.cs` or `*Extensions.cs`; the flows through a component usually start at a hosted
service, an endpoint group, or a Blazor page's injected service.
