# .NET reference (C# 12–14, .NET 8–10)

The hot read for every code-writing step. One row per replacement; `details.md` in this directory carries the
before/after snippet, the analyzer rule and the sources for every row (same section codes), and
`inefficient.md` the idioms that count as defects. Only rows at or below the project's `LangVersion` /
`TargetFramework` apply — never raise either to use a row.

## Version anchors
- C# 12 → .NET 8 · C# 13 → .NET 9 · C# 14 → .NET 10.
- `field` keyword: **preview** in C# 13 (VS 17.12+, needs `<LangVersion>preview`), **GA** in C# 14.
- Extension members (`extension` blocks): **GA** in C# 14 / .NET 10. No preview gate.
- https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13
- https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14

## Replacements
| code | old construct | modern construct | since | rule |
|---|---|---|---|---|
| A1.1 | block `namespace X { }` | file-scoped namespace `X;` | C# 10 | IDE0161 |
| A1.2 | `Main(string[])` boilerplate class | top-level statements in `Program.cs` | C# 9 | IDE0210 |
| A1.3 | repeated `using` directives per file | `global using` / implicit usings | C# 10 | — |
| A1.4 | `using (...) { }` block | `using var x = ...;` declaration | C# 8 | IDE0063 |
| A1.5 | alias limited to named types | `using` alias for any type, incl. tuples | C# 12 | — |
| A1.6 | mangled `internal` helper type names | `file` modifier scopes type to file | C# 11 | — |
| A2.1 | hand-written ctor plus private fields | primary constructor parameters on the type | C# 12 | IDE0290 |
| A2.2 | hand-rolled value-semantics class | `record` / `record struct` with `with` | C# 9 / C# 10 | — |
| A2.3 | `private set` or ctor-only readonly property | `init` setter | C# 9 | — |
| A2.4 | ctor overloads to enforce a value is set | `required` member | C# 11 | — |
| A2.5 | explicit backing field, one custom accessor | `field` contextual keyword | C# 13 preview / C# 14 GA | — |
| A2.6 | `static` method with `this` first parameter | `extension` blocks (properties, indexers too) | C# 14 | — |
| A2.7 | `partial` methods only | partial properties, indexers, ctors, events | C# 13 / C# 14 | — |
| A2.8 | mutable struct, defensively copied | `readonly struct` / `readonly` members | C# 7.2 / C# 8 | IDE0250 |
| A2.9 | struct fields could not initialize inline | inline field initializer + explicit `public S()` | C# 10 | — |
| A2.10 | `[Attr(typeof(Foo))]` with a `Type` parameter | generic attribute class `Attr<T>` | C# 11 | — |
| A2.11 | one numeric algorithm duplicated per type | generic method constrained to `INumber<T>` | C# 11 | — |
| A2.12 | `x += y` always desugars to `x = x + y` | user-defined `operator +=` in place | C# 14 | — |
| A3.1 | type-specific initializers, `Concat().ToArray()` | collection expression `[...]` with spread `..` | C# 12 | IDE0300 |
| A3.2 | type repeated on both sides of `=` | target-typed `new()` | C# 9 | IDE0090 |
| A3.3 | `switch` statement assigning with `case`/`break` | switch expression | C# 8 | — |
| A3.4 | chained `&&` comparisons and `!= null` | property/relational patterns, `is not null` | C# 8 / C# 9 | IDE0150 |
| A3.5 | nested brace pattern per level | dotted-path property pattern `{ Start.Y: 0 }` | C# 10 | — |
| A3.6 | manual length/index guards | list pattern with `..` slices | C# 11 | — |
| A3.7 | `Length - 1` arithmetic, `Skip().Take()` | `^1` index and `a..b` range | C# 8 | IDE0057 |
| A3.8 | `^` disallowed inside an object initializer | `^` index inside an object initializer | C# 13 | — |
| A3.9 | escaped/verbatim strings for JSON, XML, regex | `"""` raw string literal | C# 11 | — |
| A3.10 | `Encoding.UTF8.GetBytes("...")` | `u8` string literal | C# 11 | — |
| A3.11 | `if (x == null) x = ...;` | `??=` null-coalescing assignment | C# 8 | IDE0074 |
| A3.12 | null guard before an assignment | `?.=` / `?[]=` conditional assignment | C# 14 | — |
| A3.13 | `nameof(List<int>)` needed a closed generic | `nameof(List<>)` unbound generic | C# 14 | IDE0340 |
| A3.14 | overload or local function for a lambda default | inline default lambda parameter | C# 12 | — |
| A3.15 | `ref`/`out` forced explicit types on all params | untyped lambda params with `ref`/`out` | C# 14 | IDE0350 |
| A3.16 | hard-coded parameter-name strings in guards | `[CallerArgumentExpression]` captures source text | C# 10 | — |
| A4.1 | nullable-oblivious references, runtime NREs | `<Nullable>enable</Nullable>` tracked null state | C# 8 | — |
| A4.2 | `ref` (writable) or `in` (accepts rvalues) | `ref readonly` parameter | C# 12 | — |
| A4.3 | no `scoped`, ref fields, ref struct interfaces | `scoped`, ref fields, `allows ref struct` | C# 11 / C# 13 | — |
| A4.4 | no `ref`/`ref struct` locals in async/iterators | allowed when not live across `await`/`yield` | C# 13 | — |
| A4.5 | a faster overload breaks callers with ambiguity | `[OverloadResolutionPriority(n)]` | C# 13 | — |
| A4.6 | ambiguity-prone `"\x1b"` escape | `"\e"` escape sequence | C# 13 | — |
| A5.1 | `lock(object)` via `Monitor.Enter`/`Exit` | `System.Threading.Lock` with `EnterScope()` | .NET 9 / C# 13 | IDE0330 |
| A5.2 | direct `DateTime.Now`/`Task.Delay` calls | inject `TimeProvider`, `FakeTimeProvider` in tests | .NET 8 | S6354 |
| A5.3 | `Task<List<T>>` buffering the whole result | `IAsyncEnumerable<T>` streaming with `yield return` | C# 8 | — |
| A5.4 | `Substring` and array-copy slicing | `ReadOnlySpan<T>` via `AsSpan()` slicing | .NET 9 (span `Split`) | CA1846 |
| A5.5 | hand-written `if (x is null) throw ...` | `ArgumentNullException.ThrowIfNull` and friends | .NET 6–8 | CA1510 |
| A5.6 | `StringBuilder`/`string.Format` in a hot path | `string.Create` writing into destination buffer | C# 10 | MA0111 |
| A5.7 | `Dictionary`/`HashSet` built once, never mutated | `FrozenDictionary`/`FrozenSet` for read-heavy tables | .NET 8 | — |
| A5.8 | `IndexOfAny(char[])` re-derived every call | precomputed `SearchValues<T>` field | .NET 8 / .NET 9 (string) | CA1870 |
| A5.9 | Newtonsoft.Json or reflection-based STJ | `System.Text.Json` with `JsonSerializerContext` | ongoing | CA1869 |
| A5.10 | `new HttpClient()` per request | `IHttpClientFactory` typed client via DI | .NET Core 2.1+ | — |
| A5.11 | `Task.WhenAny` drain loop | `Task.WhenEach` async-enumerable of completions | .NET 9 | — |
| A5.12 | `Parallel.ForEach` with an async body | `Parallel.ForEachAsync` with cancellation | .NET 6 | — |
| A5.13 | `new Random()` per call, manual locking | `Random.Shared` thread-safe singleton | .NET 6 | — |
| A5.14 | `params T[]` always allocates an array | `params ReadOnlySpan<T>` | C# 13 | — |
| A5.15 | hand-rolled loops, `OrderBy().First()`, `GroupBy()` | `MinBy`/`MaxBy`, `CountBy`, `Chunk` | .NET 6–10 | — |
| A5.16 | `new Regex(...)` parsed at runtime | `[GeneratedRegex]` compile-time source generator | .NET 7 | SYSLIB1045 |
| A5.17 | `logger.LogInformation($"...")` interpolated message | `[LoggerMessage]` source-generated delegate | .NET 6 | CA1848 |
| A5.18 | `Task<T>` allocates for an available result | `ValueTask<T>` only where profiling shows need | C# 7 / .NET Core 2.1 | CA2012 |
| A5.19 | `string.Format` re-parsing a non-literal format | `CompositeFormat.Parse` once | .NET 8 | CA1863 |
| A5.20 | `BitConverter.ToString(b).Replace("-","")` etc. | `Convert.ToHexString`, `Environment.ProcessId`, `SHA256.HashData` | .NET 5–9 | CA1872 |

## Enforcement
Many CA performance rules (`CA1851`, `CA1854`, `CA1860`, `CA1863`, `CA1870`, `CA2007`, `CA1849`) are off by
default: a green build proves nothing about them, the walk in SKILL.md step 4 does. `details.md` has the
analyzer setup.

Sources: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-12 ·
https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13 ·
https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14 ·
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/performance-warnings —
the full list is in `details.md`.
