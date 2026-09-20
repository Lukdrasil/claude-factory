# Correct-fix example; C# / .NET rules

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

Covers CA*, S* (Sonar), VSTHRD*, MA* (Meziantou), IDE*, DDD*, RS0030.

## Steps

### 1. Check the example library first

Two places, in this order: the target repo's `docs/analyzer-examples/<CODE>.md` (examples this repo grew, step 6), then `@references/dotnet/rules/<CODE>.md`, the shipped library — one file per rule, already in the output format. When a file exists, serve it; adapt the wrong snippet to the user's real code when they gave a concrete file, otherwise return it as is. Steps 2–5 are for codes with no example in either place.

### 2. Establish the rule's intent

- Look the code up in the library indexes first, `@references/dotnet/rules/_index-sonar.md` (S*), `@references/dotnet/rules/_index-meziantou.md` (MA*), `@references/dotnet/rules/_index-ca.md` (CA*), `@references/dotnet/rules/_index-ide.md` (IDE*), `@references/dotnet/rules/_index-vsthrd.md` (VSTHRD*, RS*), each gives the title and the official doc URL pattern; then fetch the official doc (WebFetch/WebSearch) for the description and its noncompliant/compliant examples. A fix based on a misremembered intent is worse than none.
- Kit-specific rules are covered by their library files: `@references/dotnet/rules/DDD001.md`, `@references/dotnet/rules/DDD002.md`, `@references/dotnet/rules/RS0030.md`. For `RS0030` on a symbol the library example does not show, the message in the target repo's `build/BannedSymbols.Domain.txt` / `BannedSymbols.Global.txt` line **is** the fix instruction; the snippet illustrates it.

### 3. Establish the layer

The right fix differs per architectural layer. The source of truth is the **target repo's** `.editorconfig` (the merged, installed one); when the repo has none, fall back to the **Kit config** line each `@references/dotnet/rules/` file carries. Examples of the differences:

- primary constructors: preferred style in `Features` (`true:warning`); in the domain the preference is off and `IDE0290` is silenced; recommend a classic constructor there (captured parameters cannot be readonly), but present it as guidance, since no diagnostic fires either way
- coupling (CA1506, S1200): warning in the domain, off in Infrastructure; "split this class" is a domain fix; an adapter with higher coupling is fine

If the warning comes from a concrete file, derive the layer from its path and build the wrong snippet from the real code, minimized. Without a concrete file, write the canonical example and, for layer-sensitive rules, show the variant for the strictest layer.

### 4. Write the fix in .NET 10 + SOLID idioms

The right snippet uses current idioms:

- time: `TimeProvider` lives in the application layer or adapter; the domain method takes the timestamp as a parameter (per `BannedSymbols.Domain.txt`; never inject a clock into an aggregate)
- file-scoped namespaces, collection expressions (`[...]`), `internal sealed` as the default visibility for handlers and adapters
- domain: private setters plus behavior methods, identity arriving from outside (DIP)
- async: `CancellationToken` propagated all the way down, tasks awaited, `async void` only for event handlers
- contracts: `record` types, free of domain types
- phrase the principle sentence concretely: "7 injected dependencies → group the ones always used together into one collaborator (SRP)", not "violates SRP"

### 5. Verify proportionally

Compile any snippet that declares a type, uses generics, or touches an API you have not used in this session: scratch project in the scratchpad, paste, `dotnet build`. Endpoint-shaped snippets need `dotnet new web` (or `<FrameworkReference Include="Microsoft.AspNetCore.App" />`), and declare a stub for any base type the snippet inherits (e.g. `AggregateRoot`). A single-token change (`ToLower` → `ToLowerInvariant`) may skip compilation.

### 6. Grow the library

The skill folder ships inside the plugin and is read-only, so the newly written example goes into the **target repo** as `docs/analyzer-examples/<CODE>.md`, in the format the shipped library files under `@references/dotnet/rules/` use (open any one as the template), so the next request for this code is a lookup, not a rebuild.

## Language-specific Done-when additions

When the finding is legacy debt rather than new code, the freezing techniques to offer are: downgrade the rule's severity for the legacy folder in `.editorconfig`, or grandfather the namespace in the architecture tests' `GrandfatheredNamespaces` list.
