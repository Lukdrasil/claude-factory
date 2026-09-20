# PublicApiAnalyzers on Contracts

Deferred from the main kit because on an existing codebase it generates
one warning for every public member; so hundreds to thousands.

## What it does

Every change to a module's public API requires an explicit entry in
`PublicAPI.Shipped.txt`. This makes a contract change visible in the
MR diff instead of slipping through.

For a modular monolith, this is more valuable than for a library: a
module's contract is the boundary through which modules talk to each
other, and a silent change to that boundary is exactly what dissolves
modularity.

## Enabling it

```xml
<PackageVersion Include="Microsoft.CodeAnalysis.PublicApiAnalyzers" Version="5.6.0" />
```

```xml
<!-- only in projects with Contracts -->
<ItemGroup Condition="$(MSBuildProjectName.EndsWith('.Application'))">
  <PackageReference Include="Microsoft.CodeAnalysis.PublicApiAnalyzers" PrivateAssets="all" />
  <AdditionalFiles Include="PublicAPI.Shipped.txt" />
  <AdditionalFiles Include="PublicAPI.Unshipped.txt" />
</ItemGroup>
```

```ini
[**/Contracts/**/*.cs]
dotnet_diagnostic.RS0016.severity = error   # undocumented public API
dotnet_diagnostic.RS0017.severity = error   # API in the file that no longer exists
dotnet_diagnostic.RS0037.severity = warning # nullability in the API file
```

## Bootstrapping on existing code

Don't write the files by hand. Let them be generated:

```bash
# create empty files
find src -name "*.Application.csproj" -execdir touch PublicAPI.Shipped.txt PublicAPI.Unshipped.txt \;

# the build throws RS0016 for every member; use the output to populate the files
dotnet build -p:ErrorLog=api.sarif,version=2.1
jq -r '.runs[].results[] | select(.ruleId=="RS0016") | .message.text' api.sarif
```

In Visual Studio there's a code fix for this, "Add to public API",
with a "Fix all in solution" option, which is faster.

## When to enable it

Phase 4 or later, and only on `Contracts`; not the whole project.
Enabling it on `Ports` is debatable: ports change more often than
contracts and are an internal module boundary, not a public promise.
