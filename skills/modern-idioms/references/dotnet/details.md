# Modern C# for .NET 8/9/10 — Agent Reference

Scope: C# 12 (.NET 8), C# 13 (.NET 9), C# 14 (.NET 10). Every item is sourced. Anything not
confirmed against a primary source is tagged `[unverified]`.

Version anchors (verified against the "What's new in C# N" pages):
- C# 12 → .NET 8 · C# 13 → .NET 9 · C# 14 → .NET 10.
- `field` keyword: **preview** in C# 13 (VS 17.12+, needs `<LangVersion>preview`), **GA** in C# 14.
- Extension members (`extension` blocks): **GA** in C# 14 / .NET 10. No preview gate.
- https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13
- https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14

Analyzer ID prefixes used below: `CA` = .NET code-quality, `IDE` = .NET style/refactor,
`S` = SonarAnalyzer.CSharp, `MA` = Meziantou.Analyzer, `SYSLIB` = .NET source-generator diagnostics.

---

# Part A — Old constructs and their modern replacements

## A1. Declarations and file layout

### A1.1 File-scoped namespaces — C# 10 / .NET 6
Block namespace wrapping the whole file → single `namespace X;` line, one less indent level.
```csharp
// old
namespace Sample { class C { } }
// new
namespace Sample;
class C { }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/namespace
Analyzer: `IDE0161` (Use file-scoped namespace) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0160-ide0161

### A1.2 Top-level statements — C# 9 / .NET 5 (default template since .NET 6 SDK)
`class Program { static void Main(string[]) }` boilerplate → statements directly in `Program.cs`.
```csharp
// old
class Program { static void Main(string[] args) => Console.WriteLine("hi"); }
// new
Console.WriteLine("hi");
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/program-structure/top-level-statements
Analyzer: `IDE0210` (Convert to top-level statements) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0210

### A1.3 Global usings + implicit usings — C# 10 / .NET 6 SDK
Repeating `using System;` etc. in every file → one `global using`, or SDK-generated implicit usings.
```csharp
// old: top of every file
using System; using System.Linq; using System.Collections.Generic;
// new: once, plus <ImplicitUsings>enable</ImplicitUsings> in the csproj
global using System.Text.Json;
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/using-directive
· https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview

### A1.4 `using` declaration without braces — C# 8 / .NET Core 3.0
`using (...) { ... }` block → `using var x = ...;`, disposed at end of enclosing scope.
```csharp
// old
using (var r = File.OpenText(path)) { return r.ReadToEnd(); }
// new
using var r = File.OpenText(path);
return r.ReadToEnd();
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/statements/using
Analyzer: `IDE0063` (Use simple `using` statement) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0063

### A1.5 `using` alias for any type — C# 12 / .NET 8
Aliases were limited to named types → any type, including tuples, arrays, pointers.
```csharp
// old: illegal before C# 12
// using Point = (int X, int Y);
// new
using Point = (int X, int Y);
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-12

### A1.6 File-local types — C# 11 / .NET 7
Uniquely-mangled `internal` helper names in generated code → `file` modifier scopes the type to its file.
```csharp
// old
internal class Gen_MyType_Helper_8f3a1 { }
// new
file class Helper { }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/file

## A2. Types and members

### A2.1 Primary constructors for classes/structs — C# 12 / .NET 8
Hand-written ctor + private fields → parameters on the type, in scope for the whole body.
(Records have had primary constructors since C# 9 / record structs C# 10.)
```csharp
// old
class Point { readonly double _x, _y; public Point(double x, double y) { _x = x; _y = y; } }
// new
class Point(double x, double y) { public double Dist => Math.Sqrt(x * x + y * y); }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/instance-constructors
Analyzer: `IDE0290` (Use primary constructor) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0290
Caveat: primary-constructor parameters are mutable captured fields; `MA0143` asks that they be
treated as readonly — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0143.md

### A2.2 Records and record structs, `with` expressions — C# 9 / C# 10
Hand-rolled value-semantics class (manual `Equals`/`GetHashCode`/`ToString`/copy ctor) → `record`.
```csharp
// old
class Person { public string First; public override bool Equals(object o) => /* manual */ false; }
// new
public record Person(string First, string Last);
var p2 = p1 with { First = "Jo" };     // nondestructive mutation
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/record
Rule of thumb: `record` for immutable data carriers; `record struct` for small value-like data;
plain `class` when identity, not value, is the semantics.

### A2.3 `init` setters — C# 9 / .NET 5
`private set` (silently mutable) or ctor-only readonly property → `init`, settable only during construction.
```csharp
// old
public string First { get; private set; }
// new
public string First { get; init; }   // usable from an object initializer, immutable after
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/init

### A2.4 `required` members — C# 11 / .NET 7
Constructor overloads or documentation to enforce "must be set" → compiler-enforced `required`.
```csharp
// old
public Person(string first) => First = first;   // only way to force a value
// new
public required string First { get; init; }     // CS9035 if the initializer omits it
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/required
Pair with `[SetsRequiredMembers]` on a constructor that sets them all.

### A2.5 `field` keyword — preview C# 13, **GA C# 14 / .NET 10**
Explicit backing field for a property with one custom accessor → `field` contextual keyword.
```csharp
// old
private string _msg;
public string Msg { get => _msg; set => _msg = value ?? throw new ArgumentNullException(nameof(value)); }
// new (C# 14)
public string Msg { get; set => field = value ?? throw new ArgumentNullException(nameof(value)); }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/field
· https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14
Status: do **not** emit `field` when targeting C# 13 without `<LangVersion>preview</LangVersion>`.
Beware types that already have a member literally named `field`; disambiguate with `@field`/`this.field`.

### A2.6 Extension members (`extension` blocks) — **GA C# 14 / .NET 10**
`static` method with a `this` first parameter, methods only → `extension(T receiver) { ... }` blocks
that also declare extension *properties*, *indexers*, *operators*, and *static* extension members.
```csharp
// old
public static bool IsEmpty<T>(this IEnumerable<T> s) => !s.Any();
// new (C# 14)
public static class Seq { extension<T>(IEnumerable<T> source) { public bool IsEmpty => !source.Any(); } }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/extension
· https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14
Classic `this`-parameter extension methods remain valid and are still the right choice on C# ≤ 13.

### A2.7 Partial members, widened — C# 13 and C# 14
C# 9 allowed `partial` methods only. C# 13 added **partial properties and indexers**; C# 14 added
**partial instance constructors and events**. This is what lets source generators contribute members.
```csharp
// C# 13
public partial class C { public partial string Name { get; set; } }            // declaring
public partial class C { public partial string Name { get => _n; set => _n = value; } } // implementing
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/partial-member

### A2.8 `readonly struct` / `readonly` members — C# 7.2 / C# 8
Mutable struct the compiler defensively copies → `readonly struct`, or `readonly` on individual members.
```csharp
// old
public struct Coords { public double X { get; set; } public double Mag() => X; }
// new
public readonly struct Coords { public double X { get; init; } public readonly double Mag() => X; }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/struct
Analyzer: `IDE0250` (Struct can be made 'readonly') — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0250

### A2.9 Struct field initializers and parameterless struct ctors — C# 10 / .NET 6
Struct fields could not be initialized inline → they can, together with an explicit `public Struct()`.
```csharp
// old: illegal before C# 10
// public struct M { public double V = double.NaN; }
// new
public struct M { public double V = double.NaN; public M() { } }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/struct

### A2.10 Generic attributes — C# 11 / .NET 7
`[Attr(typeof(Foo))]` with a `Type` parameter → a generic attribute class.
```csharp
// old
[TypeConverter(typeof(FooConverter))]
// new
public class ValidatorAttribute<T> : Attribute { }
[Validator<Foo>] class Bar { }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/advanced-topics/reflection-and-attributes/creating-custom-attributes

### A2.11 Static abstract interface members + generic math — C# 11 / .NET 7
One numeric algorithm duplicated per type → one generic method constrained to `INumber<T>`.
```csharp
// old
static int Sum(int[] xs) { int s = 0; foreach (var x in xs) s += x; return s; }   // and a double copy, decimal copy...
// new
static T Sum<T>(ReadOnlySpan<T> xs) where T : INumber<T>
{ T s = T.Zero; foreach (var x in xs) s += x; return s; }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/interface
· https://learn.microsoft.com/en-us/dotnet/standard/generics/math

### A2.12 User-defined compound assignment operators — C# 14 / .NET 10
`x += y` always desugared to `x = x + y` (a new instance) → a type can define `operator +=` for in-place mutation.
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14

## A3. Expressions and syntax

### A3.1 Collection expressions `[...]` and the spread `..` — C# 12 / .NET 8
Type-specific initializers and `Concat(...).ToArray()` → one `[...]` form for arrays, spans, `List<T>`, etc.
```csharp
// old
int[] a = new int[] { 1, 2, 3 };
int[] b = a.Concat(new[] { 4, 5 }).ToArray();
// new
int[] a = [1, 2, 3];
int[] b = [.. a, 4, 5];
ReadOnlySpan<int> s = [1, 2, 3];      // no heap allocation for the span case
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/collection-expressions
Analyzers: `IDE0300`–`IDE0306` (use collection expression for array / empty / `Create()` / fluent / `new`)
— https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0300

### A3.2 Target-typed `new()` — C# 9 / .NET 5
Type repeated on both sides → `new()` when the target type is already known.
```csharp
// old
private readonly Dictionary<string, List<int>> _m = new Dictionary<string, List<int>>();
// new
private readonly Dictionary<string, List<int>> _m = new();
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/new-operator
Analyzer: `IDE0090` (Simplify `new` expression) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0090

### A3.3 Switch expressions — C# 8 / .NET Core 3.0
`switch` statement with `case`/`break` assigning a variable, or a long if/else chain → switch expression.
```csharp
// old
string s; switch (n) { case 1: s = "one"; break; default: s = "many"; break; }
// new
string s = n switch { 1 => "one", 2 => "two", _ => "many" };
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/switch-expression
The compiler reports non-exhaustive arms (CS8509), which an if/else chain cannot give you.

### A3.4 Property, relational and logical patterns; `is not null` — C# 8 / C# 9
Chained `&&` comparisons and `!= null` → patterns that express shape and range inline.
```csharp
// old
if (o != null && o.Items > 10 && o.Cost > 1000) { }
if (x != null) { }
// new
if (o is { Items: > 10, Cost: > 1000 }) { }
if (x is not null) { }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/patterns
Analyzers: `IDE0150` (prefer null check over type check), `IDE0260`/`IDE0078` (use pattern matching)
— https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0150
Prefer `is not null` over `!= null`: `!=` can dispatch to a user-defined operator, `is` cannot.

### A3.5 Extended property patterns — C# 10 / .NET 6
Nested braces per level → a dotted path inside one pattern.
```csharp
// old
if (seg is { Start: { Y: 0 } }) { }
// new
if (seg is { Start.Y: 0 }) { }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/patterns

### A3.6 List patterns — C# 11 / .NET 7
Manual length/index guards → a sequence pattern with `..` slices.
```csharp
// old
if (a.Length >= 2 && a[0] == 1 && a[1] == 2) { }
// new
if (a is [1, 2, ..]) { }
if (a is [var first, .., var last]) { }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/patterns

### A3.7 Indices and ranges — C# 8 / .NET Core 3.0
`Length - 1` arithmetic and `Skip().Take()` → `^1` and `a..b`.
```csharp
// old
var last = xs[xs.Length - 1];
var mid = xs.Skip(1).Take(3).ToArray();
// new
var last = xs[^1];
var mid = xs[1..4];
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/member-access-operators
Analyzer: `IDE0057` (Use range operator) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0057
On `string`/arrays prefer `AsSpan()[1..4]`: the range indexer on a string calls `Substring` and copies (`CA1831`).

### A3.8 Implicit index access in object initializers — C# 13 / .NET 9
`^` was not allowed inside an object initializer → it is now, for single-dimension collections.
```csharp
// new
var t = new TimerRemaining { buffer = { [^1] = 0, [^2] = 1 } };
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13

### A3.9 Raw string literals — C# 11 / .NET 7
Escaped or verbatim strings for JSON/XML/regex → `"""` blocks, no escaping, indentation stripped.
```csharp
// old
var json = "{\n  \"prop\": 0\n}";
// new
var json = """
    { "prop": 0 }
    """;
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/raw-string
Interpolation in a raw string uses extra `$`: `$$"""{{value}}"""` when the content contains braces.

### A3.10 UTF-8 string literals `u8` — C# 11 / .NET 7
`Encoding.UTF8.GetBytes("...")` or a hand-written `byte[]` → a compile-time `ReadOnlySpan<byte>`.
```csharp
// old
static readonly byte[] Auth = Encoding.UTF8.GetBytes("AUTH ");
// new
ReadOnlySpan<byte> auth = "AUTH "u8;
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/reference-types

### A3.11 Null-coalescing assignment `??=` — C# 8 / .NET Core 3.0
```csharp
// old
if (names == null) names = new List<string>();
// new
names ??= [];
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/assignment-operator
Analyzer: `IDE0074` (Use coalesce compound assignment) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0054-ide0074

### A3.12 Null-conditional assignment `?.=` — C# 14 / .NET 10
Null guard before an assignment → `?.` / `?[]` on the left of `=` and compound assignments.
```csharp
// old
if (customer is not null) customer.Order = GetCurrentOrder();
// new
customer?.Order = GetCurrentOrder();   // RHS evaluated only when customer is non-null
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14
`++`/`--` are **not** allowed in this position.

### A3.13 `nameof` with unbound generics — C# 14 / .NET 10
```csharp
// old
string n = nameof(List<int>);   // had to close the generic
// new
string n = nameof(List<>);      // "List"
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14
Analyzer: `IDE0340` (Use unbound generic type) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0340

### A3.14 Default lambda parameters and `params` in lambdas — C# 12 / .NET 8
Overloads or a local function to give a lambda parameter a default → declare the default inline.
```csharp
// old
var inc = (int x, int step) => x + step;
// new
var inc = (int x, int step = 1) => x + step;
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-12

### A3.15 Modifiers on untyped lambda parameters — C# 14 / .NET 10
`ref`/`out`/`in`/`scoped` on a lambda parameter forced explicit types on *all* parameters → no longer.
```csharp
// old
TryParse<int> p = (string text, out int result) => int.TryParse(text, out result);
// new
TryParse<int> p = (text, out result) => int.TryParse(text, out result);
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14
Analyzer: `IDE0350` (Use implicitly typed lambda) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0350

### A3.16 `CallerArgumentExpression` — C# 10 / .NET 6
Hard-coded parameter-name strings in guard helpers → the compiler captures the argument's source text.
```csharp
// old
static void Check(bool c, string expr) { if (!c) throw new ArgumentException(expr); }
// new
static void Check(bool c, [CallerArgumentExpression(nameof(c))] string? expr = null)
{ if (!c) throw new ArgumentException(expr); }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/attributes/caller-information

## A4. Nullability and correctness

### A4.1 Nullable reference types — C# 8, on by default in new .NET 6+ templates
Every reference implicitly nullable, NREs only at run time → compiler-tracked null state.
```csharp
// old (nullable-oblivious)
string name = GetName();          // may silently be null
// new: <Nullable>enable</Nullable>
string? name = GetName();
if (name is not null) Use(name);  // CS8602 without the guard
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/nullable-reference-types
Always set `<Nullable>enable</Nullable>` in the csproj. Use `[NotNullWhen(true)]`, `[MemberNotNull]`
and friends instead of `!` (null-forgiving); `!` suppresses the diagnostic without proving anything.

### A4.2 `ref readonly` parameters — C# 12 / .NET 8
`ref` (accidentally writable) or `in` (accepts rvalues) for a large read-only struct → `ref readonly`.
```csharp
// old
static void Read(in Matrix4x4 m) { }
// new
static void Read(ref readonly Matrix4x4 m) { }   // by ref, provably not modified, requires a variable
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-12

### A4.3 `scoped`, `ref` fields, `allows ref struct`, `ref struct` interfaces — C# 11 and C# 13
C# 11 added `scoped` and `ref` fields in `ref struct`. C# 13 added `where T : allows ref struct`
(so `Span<T>` can be a generic argument) and let `ref struct` types implement interfaces.
```csharp
// C# 13
public class C<T> where T : allows ref struct { public void M(scoped T p) { } }
ref struct Buf : IDisposable { public void Dispose() { } }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13
· https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/ref-struct

### A4.4 `ref`/`unsafe` in iterators and async methods — C# 13 / .NET 9
`async` and `yield return` methods could not declare `ref` locals or `ref struct` locals at all → they can,
as long as the local is not live across an `await` or `yield return`.
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13

### A4.5 Overload resolution priority — C# 13 / .NET 9
Adding a faster overload broke callers with ambiguity → `[OverloadResolutionPriority(n)]` picks a winner.
```csharp
[OverloadResolutionPriority(1)] public void Write(ReadOnlySpan<char> s) { }
public void Write(string s) { }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13
Library authors only; it changes which overload existing source binds to on recompile.

### A4.6 `\e` escape sequence — C# 13 / .NET 9
`""` or the ambiguity-prone `"\x1b"` → `"\e"`.
```csharp
// old
const string Reset = "\x1b[0m";   // breaks if the next char is a hex digit
// new
const string Reset = "\e[0m";
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13

## A5. BCL replacements

### A5.1 `System.Threading.Lock` instead of `lock(object)` — .NET 9 + C# 13
`lock` on a plain `object` emits `Monitor.Enter/Exit` → locking a `Lock` emits `Lock.EnterScope()`, faster.
```csharp
// old
private readonly object _gate = new();
// new
private readonly Lock _gate = new();      // the lock statement recognizes the type; no other change
void M() { lock (_gate) { /* ... */ } }
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.threading.lock
· https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/statements/lock
Analyzers: `IDE0330` (Prefer `System.Threading.Lock`) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0330
· `MA0158` (Use System.Threading.Lock) — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0158.md
Trap: converting the `Lock` to `object` before locking silently falls back to `Monitor`.

### A5.2 `TimeProvider` instead of `DateTime.Now` — .NET 8
Direct `DateTime.UtcNow`/`Task.Delay` calls, untestable → inject `TimeProvider`; use `FakeTimeProvider` in tests.
```csharp
// old
class Reminder { public bool IsDue(DateTimeOffset d) => DateTime.UtcNow >= d; }
// new
class Reminder(TimeProvider clock) { public bool IsDue(DateTimeOffset d) => clock.GetUtcNow() >= d; }
```
Docs: https://learn.microsoft.com/en-us/dotnet/standard/datetime/timeprovider-overview
· https://learn.microsoft.com/en-us/dotnet/core/extensions/timeprovider-testing
Analyzer: `S6354` (Use a testable date/time provider) — https://rules.sonarsource.com/csharp/RSPEC-6354
Also gives `clock.CreateTimer(...)` and `TimeProvider.GetElapsedTime(...)`; back-ported via `Microsoft.Bcl.TimeProvider`.

### A5.3 `IAsyncEnumerable<T>` instead of `Task<List<T>>` — C# 8 / .NET Core 3.0
Buffering the whole result set before returning → streaming with `yield return` + `await foreach`.
```csharp
// old
async Task<List<Row>> GetAsync() { var l = new List<Row>(); /* fill all */ return l; }
// new
async IAsyncEnumerable<Row> GetAsync([EnumeratorCancellation] CancellationToken ct = default)
{ await foreach (var r in Source(ct)) yield return r; }
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.collections.generic.iasyncenumerable-1
· https://learn.microsoft.com/en-us/dotnet/api/system.runtime.compilerservices.enumeratorcancellationattribute
Callers pass cancellation with `.WithCancellation(ct)`. Always mark the token parameter
`[EnumeratorCancellation]`, otherwise `WithCancellation` is silently ignored.

### A5.4 `Span<T>` / `ReadOnlySpan<T>` instead of `Substring` and array copies
`Substring` is an O(n) copy + allocation → `AsSpan()` slicing is allocation-free and O(1).
```csharp
// old
if (line.Substring(0, 5) == "HTTP/") { }
var parts = line.Split(',');                    // allocates string[] plus every element
// new
if (line.AsSpan(0, 5).SequenceEqual("HTTP/")) { }
foreach (Range r in line.AsSpan().Split(','))   // .NET 9 span Split, zero allocation
    Handle(line.AsSpan()[r]);
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.memoryextensions.split
· https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-9/libraries
Analyzers: `CA1846` (prefer `AsSpan` over `Substring`), `CA1831`/`CA1832`/`CA1833` (use `AsSpan` instead of
range-based indexers), `CA1845` (span-based `string.Concat`)
— https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1846
Span-returning APIs cannot cross an `await`; use `Memory<T>` there. C# 14 adds implicit span conversions.

### A5.5 Throw helpers instead of hand-written guard clauses — .NET 6/7/8
`if (x is null) throw new ArgumentNullException(nameof(x));` → one-line static helpers that also inline better.
```csharp
// old
if (name is null) throw new ArgumentNullException(nameof(name));
if (count < 0) throw new ArgumentOutOfRangeException(nameof(count));
// new
ArgumentException.ThrowIfNullOrWhiteSpace(name);
ArgumentOutOfRangeException.ThrowIfNegative(count);
```
Available: `ArgumentNullException.ThrowIfNull` (.NET 6); `ArgumentException.ThrowIfNullOrEmpty` (.NET 7);
`ArgumentException.ThrowIfNullOrWhiteSpace`, `ArgumentOutOfRangeException.ThrowIfNegative/ThrowIfZero/
ThrowIfGreaterThan/ThrowIfLessThan/ThrowIfEqual/ThrowIfNegativeOrZero` (.NET 8);
`ObjectDisposedException.ThrowIf` (.NET 7).
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.argumentnullexception.throwifnull
· https://learn.microsoft.com/en-us/dotnet/api/system.argumentoutofrangeexception.throwifnegative
Analyzers: `CA1510`/`CA1511`/`CA1512`/`CA1513` (use the corresponding throw helper)
— https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1510
Traps: `CA1871` — don't pass a nullable struct to `ThrowIfNull` (it boxes); `CA2264` — don't pass a
non-nullable value to it at all.

### A5.6 `string.Create` and interpolated string handlers — C# 10 / .NET 6
`StringBuilder` or `string.Format` in a hot path → write straight into the destination buffer.
```csharp
// old
string s = new StringBuilder().Append(a).Append('-').Append(b).ToString();
// new
string s = string.Create(len, (a, b), static (span, st) => { /* write into span */ });
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.string.create
Analyzers: `MA0111` (Use string.Create instead of FormattableString) and `S6618` (same)
— https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0111.md · https://rules.sonarsource.com/csharp/RSPEC-6618
Custom `[InterpolatedStringHandler]` types let an API skip formatting entirely when the result is unused
(this is exactly how `Debug.Assert` and the logging handlers avoid work at disabled levels).

### A5.7 Frozen collections for build-once lookup tables — .NET 8
`Dictionary`/`HashSet` populated at startup and never mutated → `FrozenDictionary`/`FrozenSet`, faster reads.
```csharp
// old
private static readonly Dictionary<string, bool> Config = LoadConfig();
// new
private static readonly FrozenDictionary<string, bool> Config = LoadConfig().ToFrozenDictionary();
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.collections.frozen.frozendictionary-2
Trade-off: construction is *more* expensive. Only worth it for long-lived, read-dominated tables.

### A5.8 `SearchValues<T>` instead of `IndexOfAny(char[])` — .NET 8 (char/byte), .NET 9 (string)
Re-deriving the search structure on every call → precompute it once into a static field.
```csharp
// old
int i = text.IndexOfAny(new[] { 'a', 'e', 'i', 'o', 'u' });
// new
private static readonly SearchValues<char> Vowels = SearchValues.Create("aeiou");
int i = text.AsSpan().IndexOfAny(Vowels);
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.buffers.searchvalues-1
Analyzer: `CA1870` (Use a cached `SearchValues` instance) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1870

### A5.9 `System.Text.Json` instead of Newtonsoft.Json; source generation over reflection
Newtonsoft, or reflection-based STJ (slow startup, breaks under trimming/Native AOT) → STJ with a
`JsonSerializerContext`.
```csharp
// old
var s = JsonConvert.SerializeObject(todo);
// new
[JsonSerializable(typeof(Todo))] partial class AppJson : JsonSerializerContext { }
var s = JsonSerializer.Serialize(todo, AppJson.Default.Todo);
```
Docs: https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation-modes
· https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/reflection-vs-source-generation
Analyzer: `CA1869` (Cache and reuse `JsonSerializerOptions` instances) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1869
.NET 9 adds the `JsonSerializerOptions.Web` singleton; .NET 10 adds `JsonSerializerOptions.Strict`
and `AllowDuplicateProperties` — https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/libraries

### A5.10 `IHttpClientFactory` instead of `new HttpClient()` — .NET Core 2.1+
A new `HttpClient` per request exhausts sockets (each owns a handler and connection pool).
```csharp
// old
using var client = new HttpClient();
// new
builder.Services.AddHttpClient<WeatherClient>();     // typed client, pooled handlers
```
Docs: https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory
· https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/http/httpclient-guidelines
If DI is unavailable, use one long-lived static `HttpClient` with
`SocketsHttpHandler.PooledConnectionLifetime` set, so DNS changes are still picked up.

### A5.11 `Task.WhenEach` instead of a `Task.WhenAny` drain loop — .NET 9
The `WhenAny`-in-a-loop pattern is O(n²) in continuations → an `IAsyncEnumerable` of completing tasks.
```csharp
// old
while (tasks.Count > 0) { var t = await Task.WhenAny(tasks); tasks.Remove(t); Use(await t); }
// new
await foreach (var t in Task.WhenEach(tasks)) Use(await t);
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.task.wheneach

### A5.12 `Parallel.ForEachAsync` instead of `Parallel.ForEach` with an async body — .NET 6
`Parallel.ForEach(items, async x => ...)` creates `async void`-shaped delegates; the loop returns before the
work finishes and exceptions are lost.
```csharp
// old
Parallel.ForEach(urls, async u => await Fetch(u));
// new
await Parallel.ForEachAsync(urls, opts, async (u, ct) => await Fetch(u, ct));
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.parallel.foreachasync
· https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/async-lambda-pitfalls
`ParallelOptions.MaxDegreeOfParallelism` bounds concurrency (default `Environment.ProcessorCount`).

### A5.13 `Random.Shared` instead of `new Random()` — .NET 6
A fresh `Random` per call (correlated seeds in tight loops) or manual locking → a thread-safe shared instance.
```csharp
// old
var r = new Random(); int n = r.Next(100);
// new
int n = Random.Shared.Next(100);
int secure = RandomNumberGenerator.GetInt32(0, 100);      // for anything security-relevant
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.random.shared
.NET 8 adds `Random.Shared.GetItems(...)` and `Random.Shared.Shuffle(span)`
— https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-8/runtime

### A5.14 `params` collections — C# 13 / .NET 9
`params T[]` always allocated an array → `params ReadOnlySpan<T>` lets the compiler use stack memory.
```csharp
// old
public void Log(params object[] args) { }        // allocates an array (and boxes value types)
// new
public void Concat<T>(params ReadOnlySpan<T> items) { }
```
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13
Also accepted: `Span<T>`, `IEnumerable<T>`, `IReadOnlyList<T>`, `ICollection<T>`, `IList<T>`, and any
collection type with an accessible `Add`. Adding a span overload beside an existing array one is a
non-breaking, allocation-removing change (pair it with `[OverloadResolutionPriority]`).

### A5.15 New `Enumerable` members instead of hand-rolled loops and `GroupBy`
```csharp
// old
var top = items.OrderByDescending(x => x.Score).First();
var counts = words.GroupBy(w => w).ToDictionary(g => g.Key, g => g.Count());
// new
var top = items.MaxBy(x => x.Score);          // .NET 6
var counts = words.CountBy(w => w);           // .NET 9, no intermediate groupings
```
Additions by version: `Chunk`, `MaxBy`/`MinBy`, `DistinctBy`/`ExceptBy`/`IntersectBy`/`UnionBy`,
`TryGetNonEnumeratedCount` (.NET 6); `Order`/`OrderDescending` (.NET 7); `CountBy`, `AggregateBy`,
`Index` (.NET 9); `LeftJoin`/`RightJoin` (.NET 10).
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.countby
· https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.maxby
· https://learn.microsoft.com/en-us/dotnet/csharp/linq/standard-query-operators/join-operations

### A5.16 `[GeneratedRegex]` instead of `new Regex(...)` — .NET 7 (properties: .NET 9)
Runtime pattern parsing (and JIT cost from `RegexOptions.Compiled`) → a compile-time source generator.
```csharp
// old
private static readonly Regex R = new(@"\b\w{5}\b", RegexOptions.Compiled);
// new
[GeneratedRegex(@"\b\w{5}\b", RegexOptions.IgnoreCase)]
private static partial Regex FiveCharWord();
```
Docs: https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expression-source-generators
Analyzer: `SYSLIB1045` (convert to `GeneratedRegexAttribute`) — https://learn.microsoft.com/en-us/dotnet/fundamentals/syslib-diagnostics/syslib1045
`RegexOptions.Compiled` is unnecessary with the generator. .NET 9 allows the attribute on a
`static partial` get-only property (uses C# 13 partial properties).

### A5.17 `[LoggerMessage]` instead of `logger.LogInformation($"...")` — .NET 6
Interpolated log messages box arguments, re-parse the template per call, and build the string even when
the level is disabled.
```csharp
// old
_logger.LogInformation($"Processing {id}");
// new
[LoggerMessage(Level = LogLevel.Information, Message = "Processing {Id}")]
static partial void LogProcessing(ILogger logger, int id);
```
Docs: https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/high-performance-logging
Analyzers: `CA1848` (Use the LoggerMessage delegates) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1848
· `CA1873` (Avoid potentially expensive logging) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1873
· `CA2254` (Template should be a static expression) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2254

### A5.18 `ValueTask` / `ValueTask<T>` — C# 7 / .NET Core 2.1
`Task<T>` allocates even when the result is already available. `ValueTask<T>` avoids that — but Microsoft's
own guidance is to **default to `Task`/`Task<T>`** and adopt `ValueTask` only where profiling shows the
allocation matters, because of the strict consume-exactly-once rules.
```csharp
public ValueTask<int> GetAsync(int key) =>
    _cache.TryGetValue(key, out int v) ? new ValueTask<int>(v) : new(ComputeAsync(key));
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.valuetask-1
Analyzer: `CA2012` (Use ValueTasks correctly) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2012

### A5.19 `CompositeFormat` for non-literal format strings — .NET 8
A resource-loaded format string re-parsed on every `string.Format` call → parse it once.
```csharp
// old
string s = string.Format(CultureInfo.InvariantCulture, LoadResource(), min, max);
// new
private static readonly CompositeFormat Msg = CompositeFormat.Parse(LoadResource());
string s = string.Format(CultureInfo.InvariantCulture, Msg, min, max);
```
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.text.compositeformat
Analyzer: `CA1863` (Use 'CompositeFormat') — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1863

### A5.20 Misc BCL one-liners that replace older idioms
```csharp
// old                                            // new
BitConverter.ToString(b).Replace("-", "")      => Convert.ToHexString(b)              // CA1872, .NET 5
Process.GetCurrentProcess().Id                 => Environment.ProcessId               // CA1837, .NET 5
Thread.CurrentThread.ManagedThreadId           => Environment.CurrentManagedThreadId  // CA1840
new HashAlgorithm().ComputeHash(b)             => SHA256.HashData(b)                  // CA1850
Regex.Match(s, p).Success                      => Regex.IsMatch(s, p)                 // CA1874
Regex.Matches(s, p).Count                      => Regex.Count(s, p)                   // CA1875
new T[0] / Enumerable.Empty<T>()               => Array.Empty<T>() or []              // CA1825
Guid.NewGuid() as a clustered DB key           => Guid.CreateVersion7()               // .NET 9, sortable
Encoding.UTF8.GetBytes($"{a}-{b}")             => Utf8.TryWrite(dest, $"{a}-{b}", ..) // .NET 8
```
Docs: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/performance-warnings
· https://learn.microsoft.com/en-us/dotnet/api/system.guid.createversion7
· https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-8/runtime

---

# Part B — Inefficient idioms and their replacements

Rule IDs below were checked against the authoritative lists: the `dotnet/docs` rule index pages,
the `SonarSource/sonar-dotnet` RSPEC metadata, and the `Meziantou.Analyzer` README table.
`rules.sonarsource.com` was not reachable from the research environment, so Sonar titles were
confirmed from the `sonar-dotnet` repo instead; both URLs are given.

## B1. Strings

### B1.1 `+` concatenation in a loop
```csharp
// bad
string s = ""; foreach (var x in items) s += x + ", ";
// good
var sb = new StringBuilder(); foreach (var x in items) sb.Append(x).Append(", ");
// better, when the shape allows it
string s = string.Join(", ", items);
```
Why: strings are immutable, so every `+=` allocates a new string and copies both operands — O(n²)
bytes copied and n intermediate garbage strings.
Rules: `S1643` "Strings should not be concatenated using '+' in a loop" —
https://rules.sonarsource.com/csharp/RSPEC-1643/ ·
https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/rspec/cs/S1643.json
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.text.stringbuilder
Pick `string.Concat`/`string.Join` over `StringBuilder` when the element count is known and small —
they size the result exactly and allocate once.

### B1.2 `string.Format` with a non-literal format string
```csharp
// bad
for (...) s = string.Format(CultureInfo.InvariantCulture, LoadTemplate(), a, b);
// good
private static readonly CompositeFormat Fmt = CompositeFormat.Parse(LoadTemplate());
s = string.Format(CultureInfo.InvariantCulture, Fmt, a, b);
```
Why: `string.Format`/`AppendFormat` re-parse the composite format string on every call.
`CompositeFormat` (.NET 8) parses once. For compile-time literals, plain interpolation is already
lowered to `DefaultInterpolatedStringHandler` and needs no change.
Rules: `CA1863` "Use 'CompositeFormat'" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1863
· `CA1305` "Specify IFormatProvider" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1305
Docs: https://learn.microsoft.com/en-us/dotnet/standard/base-types/composite-formatting

### B1.3 `StringBuilder.Append` with a one-character string
```csharp
// bad
sb.Append("-").Append(name).Append(",");
// good
sb.Append('-').Append(name).Append(',');
```
Why: the `string` overload goes through a length check and a bulk copy; the `char` overload writes
one character directly.
Rules: `CA1834` "Use StringBuilder.Append(char) for single character strings" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1834
· `CA1830` "Prefer strongly-typed Append and Insert overloads" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1830
· `MA0028` "Optimize StringBuilder usage" — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0028.md

### B1.4 `ToLower()`/`ToUpper()` to compare strings
```csharp
// bad
if (a.ToLower() == b.ToLower()) { }
// good
if (string.Equals(a, b, StringComparison.OrdinalIgnoreCase)) { }
```
Why: two throwaway string allocations per comparison, plus culture-sensitive casing gives wrong
answers in some locales (the Turkish dotless-i problem). `Ordinal`/`OrdinalIgnoreCase` is also the
fastest comparison path.
Rules: `CA1862` "Use the 'StringComparison' method overloads" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1862
· `CA1304`/`CA1305`/`CA1311` (culture) · `MA0001` "StringComparison is missing" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0001.md
· `MA0006` "Use String.Equals instead of equality operator" · `MA0074` "Avoid implicit culture-sensitive methods"
Docs: https://learn.microsoft.com/en-us/dotnet/standard/base-types/best-practices-strings
Default to `StringComparison.Ordinal` for identifiers, keys, paths and protocol tokens; use
culture-aware comparison only for text shown to a human.

### B1.5 `Substring` where a view would do
```csharp
// bad
if (line.Substring(0, 4) == "GET ") { }
// good
if (line.AsSpan(0, 4).SequenceEqual("GET ")) { }
```
Why: `Substring` is an O(n) copy plus a heap allocation; `AsSpan`/`Slice` is O(1) and allocates nothing.
Rules: `CA1846` "Prefer AsSpan over Substring" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1846
· `CA1845` "Use span-based 'string.Concat'" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1845
· `CA1831`/`CA1832`/`CA1833` (use `AsSpan` instead of range-based indexers) ·
`IDE0057` "Use range operator" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0057

### B1.6 `IndexOf`/`Contains`/`StartsWith` with a one-character string
```csharp
// bad
if (s.IndexOf("/") == 0) { }
if (s.Contains("x")) { }
// good
if (s.StartsWith('/')) { }
if (s.Contains('x')) { }
```
Why: `IndexOf(string) == 0` scans for the substring anywhere before the caller discards the result;
the `char` overloads skip the string-comparison machinery entirely.
Rules: `CA1858` "Use StartsWith instead of IndexOf" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1858
· `CA1865`–`CA1867` "Use char overload" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1865-ca1867
· `CA1847` "Use char literal for a single character lookup" · `CA2249` "Consider using String.Contains instead of String.IndexOf"
· `S6610` "StartsWith/EndsWith overloads that take a char should be used" —
https://rules.sonarsource.com/csharp/RSPEC-6610/ · https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/rspec/cs/S6610.json

### B1.7 Testing for an empty string with `== ""`
```csharp
// bad
if (s == "" || s == null) { }
// good
if (string.IsNullOrEmpty(s)) { }
```
Why: `==` on strings runs a full comparison; a length check is a single field read. `IsNullOrEmpty`
also folds the null case in.
Rules: `CA1820` "Test for empty strings using string length" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1820

### B1.8 `Encoding.GetBytes` allocating on every call
```csharp
// bad
byte[] b = Encoding.UTF8.GetBytes(s);
// good
Span<byte> dest = stackalloc byte[256];
Encoding.UTF8.GetBytes(s.AsSpan(), dest);        // or: ReadOnlySpan<byte> lit = "literal"u8;
```
Why: the array-returning overload allocates a fresh `byte[]` per call; the span overload writes into
caller-owned memory, and a `u8` literal needs no runtime encoding at all.
Rules: `IDE0230` "Use UTF-8 string literal" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0230
· otherwise no analyzer rule.
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.text.encoding.getbytes
Above a few hundred bytes, rent from `ArrayPool<byte>.Shared` rather than `stackalloc`.

### B1.9 `Guid.ToString()` as a dictionary key
```csharp
// bad
var map = new Dictionary<string, T>(); map[id.ToString()] = v;
// good
var map = new Dictionary<Guid, T>(); map[id] = v;
```
Why: `Guid` already hashes well as a 16-byte value; `ToString()` allocates a 36-character string per
lookup *and* makes hashing scan 36 chars instead of 16 bytes. When text is genuinely required, use
`Guid.TryFormat` into a span.
Rules: no analyzer rule. `MA0176` "Optimize guid creation" covers a related case —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0176.md
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.guid.tryformat

### B1.10 `Enum.ToString()` / `Enum.Parse` / `Enum.IsDefined` in hot paths
```csharp
// bad
string name = color.ToString();
// good
string name = color switch { Color.Red => "Red", Color.Blue => "Blue", _ => color.ToString() };
```
Why: these go through reflection-backed metadata lookups and box the enum value. A `switch` (or a
`FrozenDictionary` lookup table) is a jump table. Use `Enum.TryParse` rather than `Enum.Parse` in
a `try`/`catch`.
Rules: `MA0052` "Replace constant Enum.ToString with nameof" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0052.md
· `CA2248` "Provide correct 'enum' argument to 'Enum.HasFlag'" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2248
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.enum.tostring

### B1.11 `new Regex(...)` in a hot path
```csharp
// bad
if (new Regex(@"\d+").IsMatch(s)) { }
// good
[GeneratedRegex(@"\d+", RegexOptions.None, matchTimeoutMilliseconds: 1000)]
private static partial Regex Digits();
```
Why: constructing a `Regex` parses and builds the pattern's node tree on every call. The source
generator does it at build time; a missing timeout is a ReDoS hazard on untrusted input.
Rules: `SYSLIB1045` (convert to `GeneratedRegexAttribute`) —
https://learn.microsoft.com/en-us/dotnet/fundamentals/syslib-diagnostics/syslib1045
· `MA0110` "Use the Regex source generator" — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0110.md
· `MA0009` "Add regex evaluation timeout" — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0009.md
· `S6444` "Regular expressions should be executed with a timeout" — https://rules.sonarsource.com/csharp/RSPEC-6444/
· `CA1874` "Use 'Regex.IsMatch'" and `CA1875` "Use 'Regex.Count'" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1874
If the generator is unavailable, fall back to a `static readonly Regex` field, not a per-call `new`.

## B2. LINQ and enumeration

### B2.1 `ToList()`/`ToArray()` before a single enumeration
```csharp
// bad
foreach (var x in query.Where(p).ToList()) Use(x);
// good
foreach (var x in query.Where(p)) Use(x);
```
Why: materializing allocates a backing array (often grown and copied several times) for no benefit
when the sequence is walked exactly once.
Materialize when it *is* right: the sequence is enumerated more than once, the query hits a
database/file, or you need a snapshot because the source may mutate during iteration.
Rules: no rule for the premature case; `CA1851` covers the opposite mistake (below).
Docs: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1851

### B2.2 Repeated enumeration of an `IEnumerable<T>` parameter
```csharp
// bad
void Save(IEnumerable<Row> rows) { if (rows.Any()) Log(rows.Count()); foreach (var r in rows) ... }
// good
void Save(IEnumerable<Row> rows) { var list = rows as IReadOnlyList<Row> ?? rows.ToList(); ... }
```
Why: an `IEnumerable<T>` may be a lazy query; each pass re-runs the whole pipeline, which for a LINQ
provider means another database round-trip and for an iterator means recomputing every element.
Rules: `CA1851` "Possible multiple enumerations of IEnumerable collection" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1851

### B2.3 `Count() > 0` / `Any()` / `.Count`
```csharp
// bad
if (list.Count() > 0) { }          // LINQ Count() on a List<T>
if (array.Any()) { }               // the type has .Length
// good
if (list.Count > 0) { }
if (array.Length > 0) { }
// unknown concrete type:
if (src.TryGetNonEnumeratedCount(out var c) ? c > 0 : src.Any()) { }
```
Why: `Enumerable.Count()` on a non-`ICollection` source enumerates everything just to learn the size;
`Any()` short-circuits but still allocates an enumerator where a `Count`/`Length` property is a field read.
Rules: `CA1827` "Do not use Count/LongCount when Any can be used" ·
`CA1828` (the async EF Core counterpart) · `CA1829` "Use Length/Count property instead of Enumerable.Count" ·
`CA1836` "Prefer IsEmpty over Count" · `CA1860` "Avoid using 'Enumerable.Any()' extension method" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1860
· `S1155` "Any() should be used to test for emptiness" — https://rules.sonarsource.com/csharp/RSPEC-1155/
· `MA0031` "Optimize Enumerable.Count() usage" · `MA0112` "Use 'Count > 0' instead of 'Any()'" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0112.md
Note `S1155` and `CA1860` point in opposite directions: `Any()` is right for a bare `IEnumerable<T>`,
`.Count`/`.Length` is right when the concrete type exposes one. Follow `CA1860` when the type is known.
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.trygetnonenumeratedcount

### B2.4 `.Where(p).First()` and friends
```csharp
// bad
var item = list.Where(x => x.Id == id).FirstOrDefault();
// good
var item = list.FirstOrDefault(x => x.Id == id);
```
Why: the chained form allocates a second iterator for the `Where` stage; the predicate overload does
one pass with one iterator.
Rules: `MA0029` "Combine LINQ methods" — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0029.md
· `MA0020` "Use direct methods instead of LINQ methods" · `S2971` "LINQ expressions should be simplified" —
https://rules.sonarsource.com/csharp/RSPEC-2971/
· `S6602` "Find method should be used instead of the FirstOrDefault extension" (List<T>) —
https://rules.sonarsource.com/csharp/RSPEC-6602/ — note SonarSource's own tracking found
`FirstOrDefault` overtook `List<T>.Find` from .NET 9, so treat `S6602` as runtime-dependent:
https://github.com/SonarSource/sonar-dotnet/issues/9664

### B2.5 LINQ where the collection has a purpose-built member
```csharp
// bad
if (list.Any(x => x.Ok)) { }      list.All(p);      set.Min();      list.First();
// good
if (list.Exists(x => x.Ok)) { }   list.TrueForAll(p);  sortedSet.Min;  list[0];
```
Why: the collection-specific members avoid allocating a LINQ enumerator and, for `SortedSet.Min`, are
O(log n) instead of O(n).
Rules: `CA1826` "Use property instead of Linq Enumerable method" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1826
· `S6605` (Exists vs Any) · `S6603` (TrueForAll vs All) · `S6608` (indexing vs Enumerable on IList)
· `S6609` (Set Min/Max properties) · `S6617` (Contains vs Any for equality checks) —
https://rules.sonarsource.com/csharp/RSPEC-6605/ · https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/rspec/cs/S6605.json
· `MA0098` "Use indexer instead of LINQ methods" — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0098.md

### B2.6 `OrderBy(k).First()` instead of `MinBy`
```csharp
// bad
var cheapest = items.OrderBy(i => i.Price).First();
// good
var cheapest = items.MinBy(i => i.Price);
```
Why: `OrderBy` sorts the whole sequence — O(n log n) plus a buffer for every element — to read one
item. `MinBy`/`MaxBy` (.NET 6) are a single O(n) pass with no buffer.
Rules: no analyzer rule confirmed for this pattern `[unverified]`.
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.minby

### B2.7 Projecting before filtering
```csharp
// bad
items.Select(x => Expensive(x)).Where(r => r.IsValid)
// good
items.Where(x => x.IsValid).Select(x => Expensive(x))
```
Why: projection-first runs `Expensive` on every element including the ones about to be discarded.
Filter first so the costly stage sees the smallest set. Same argument for `Where` before `OrderBy`.
Rules: `S6607` "The collection should be filtered before sorting by using 'Where' before 'OrderBy'" —
https://rules.sonarsource.com/csharp/RSPEC-6607/ · https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/rspec/cs/S6607.json

### B2.8 `List<T>.Contains` inside a loop
```csharp
// bad
foreach (var id in incoming) if (known.Contains(id)) Hit(id);     // known is a List<T>
// good
var knownSet = known.ToHashSet();
foreach (var id in incoming) if (knownSet.Contains(id)) Hit(id);
```
Why: `List<T>.Contains` is a linear scan, so the nested loop is O(n·m). A `HashSet<T>` makes each
lookup O(1) average. For a build-once set, `ToFrozenSet()` is faster still.
Rules: no analyzer rule for this direction `[unverified]`. `MA0227` "Avoid using 'Enumerable.Contains'
on a set" covers the inverse mistake — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0227.md
Docs: https://learn.microsoft.com/en-us/dotnet/standard/collections/

### B2.9 LINQ in per-frame / per-request hot loops
```csharp
// bad
foreach (var id in entities.Where(e => e.Active).Select(e => e.Id)) Use(id);
// good
foreach (ref readonly var e in CollectionsMarshal.AsSpan(entities))
    if (e.Active) Use(e.Id);
```
Why: each LINQ stage allocates an iterator object and a closure, and every element crosses a virtual
`MoveNext` call. A `for`/`foreach` over a `Span<T>` allocates nothing and the JIT can elide bounds checks.
Rules: no analyzer rule.
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.collectionsmarshal.asspan
This is a hot-path-only trade. LINQ is the right default everywhere else — measure before rewriting.

### B2.10 Allocating an empty collection
```csharp
// bad
return new int[0];              return new List<T>();           return Enumerable.Empty<T>().ToList();
// good
return [];                      return Array.Empty<T>();
```
Why: a fresh zero-length array is a real allocation; `Array.Empty<T>()` returns one cached instance
per type. `[]` (C# 12) lowers to the same thing for array and span targets.
Rules: `CA1825` "Avoid zero-length array allocations" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1825
· `IDE0301` "Use collection expression for empty" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0301

## B3. Async

### B3.1 `async void`
```csharp
// bad
async void Save() { await _repo.SaveAsync(); }
// good
async Task SaveAsync() { await _repo.SaveAsync(); }
```
Why: an exception from an `async void` method is rethrown on the captured `SynchronizationContext` (or
a thread-pool thread) and usually crashes the process; callers also cannot await or observe completion.
The only legitimate use is a real event handler.
Rules: `S3168` "'async' methods should not return 'void'" — https://rules.sonarsource.com/csharp/RSPEC-3168/
· `MA0155` "Do not use async void methods" — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0155.md
· `MA0147` "Avoid async void method for delegate" · `VSTHRD100` —
https://github.com/microsoft/vs-threading/blob/main/doc/analyzers/VSTHRD100.md
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/async-return-types

### B3.2 Blocking on a task (`.Result`, `.Wait()`, `GetAwaiter().GetResult()`)
```csharp
// bad
var data = GetDataAsync().Result;
// good
var data = await GetDataAsync();
```
Why: the thread is parked while the task runs; under a captured context the continuation needs that
same thread, so it deadlocks. Even without a context, each blocked request burns a pool thread —
this is the classic route to thread-pool starvation.
Rules: `S4462` "Calls to 'async' methods should not be blocking" — https://rules.sonarsource.com/csharp/RSPEC-4462/
· `MA0042` "Do not use blocking calls when the calling method is async" ·
`MA0045` "Do not use blocking calls, even when the calling method must become async" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0042.md
· `VSTHRD002` — https://github.com/microsoft/vs-threading/blob/main/doc/analyzers/VSTHRD002.md
Docs: https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/common-async-bugs
· https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices

### B3.3 Missing `ConfigureAwait(false)` in a library
```csharp
// bad (library code)
await SomeIoAsync();
// good (library code)
await SomeIoAsync().ConfigureAwait(false);
```
Why: without it the continuation is posted back to the caller's captured context — an extra hop, and a
deadlock if any caller blocks. **Not needed in ASP.NET Core**: there is no `SynchronizationContext`,
so continuations already resume on a pool thread. Apply it in reusable libraries, not app code.
Rules: `CA2007` "Do not directly await a Task" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2007
· `MA0004` "Use Task.ConfigureAwait" — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0004.md
· `S3216` "'ConfigureAwait(false)' should be used" — https://rules.sonarsource.com/csharp/RSPEC-3216/
Docs: https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/executioncontext-synchronizationcontext

### B3.4 `Task.Run` on an already-async call
```csharp
// bad
var r = await Task.Run(() => _svc.GetAsync());
// good
var r = await _svc.GetAsync();
```
Why: ASP.NET Core already dispatches request handling onto pool threads. Wrapping an I/O-bound
call adds a scheduling hop and one more queued work item without adding any parallelism. `Task.Run`
is for offloading genuinely CPU-bound work off a UI thread.
Rules: no analyzer rule.
Docs: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices

### B3.5 `Thread.Sleep` in async code
```csharp
// bad
async Task PollAsync() { while (true) { Thread.Sleep(1000); await CheckAsync(); } }
// good
async Task PollAsync(CancellationToken ct) { while (true) { await Task.Delay(1000, ct); await CheckAsync(ct); } }
```
Why: `Thread.Sleep` holds the pool thread for the whole interval; `Task.Delay` releases it and is
cancellable. Under `TimeProvider`, use `timeProvider.Delay(...)` so tests need not wait in real time.
Rules: `MA0045` (flags `Thread.Sleep` as a blocking call) —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0045.md
· `S2925` "'Thread.Sleep' should not be used in tests" (test scope only) — https://rules.sonarsource.com/csharp/RSPEC-2925/
Docs: https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-threadpool-starvation

### B3.6 `async` method with no `await`
```csharp
// bad
async Task<int> GetAsync() { return _cached; }
// good
Task<int> GetAsync() => Task.FromResult(_cached);
```
Why: the compiler still builds a state machine and allocates a `Task` for a method that runs entirely
synchronously. `CS1998` names it at compile time.
Rules: `CS1998` (compiler warning) · `S3168` — https://rules.sonarsource.com/csharp/RSPEC-3168/
Docs: https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/common-async-bugs

### B3.7 Not forwarding the `CancellationToken`
```csharp
// bad
async Task RunAsync(CancellationToken ct) { await Step1Async(); await Step2Async(); }
// good
async Task RunAsync(CancellationToken ct) { await Step1Async(ct); await Step2Async(ct); }
```
Why: cancellation never reaches the inner call, so the work keeps burning CPU, connections and time
after the caller has given up — the request times out but the server keeps working.
Rules: `CA2016` "Forward the CancellationToken parameter to methods that take one" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2016
· `MA0032` "Use an overload with a CancellationToken argument" · `MA0040` "Forward the CancellationToken"
· `MA0080` "Use a cancellation token using .WithCancellation()" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0040.md
· `CA1068` "CancellationToken parameters must come last" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1068

### B3.8 Fire-and-forget: discarding a returned `Task`
```csharp
// bad
SendEmailAsync(user);                              // Task dropped; failures vanish
// good
await SendEmailAsync(user);
// deliberate background work: hand it to a hosted service / Channel, and always observe the fault
```
Why: an unobserved faulted task swallows the exception, and nothing orders the work against the rest
of the request. `_ = Foo()` is not a fix; it only silences the warning.
Rules: `MA0134` "Observe result of async calls" — https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0134.md
· `CA2012` (for `ValueTask`) · `CA2025` "Do not pass `IDisposable` instances into unawaited tasks" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2025

### B3.9 `ValueTask` consumed more than once
```csharp
// bad
ValueTask<int> vt = GetAsync(); var a = await vt; var b = await vt;
// good
var a = await GetAsync();
```
Why: a `ValueTask` may wrap a pooled `IValueTaskSource` that is recycled the moment it is awaited.
Awaiting twice, reading `.Result` before completion, or storing it is undefined behaviour by contract.
Rules: `CA2012` "Use ValueTasks correctly" — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2012
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.valuetask

### B3.10 Sync-over-async in EF Core
```csharp
// bad
var rows = ctx.Blogs.Where(b => b.Rating > 3).ToList();
ctx.SaveChanges();
// good
var rows = await ctx.Blogs.Where(b => b.Rating > 3).ToListAsync(ct);
await ctx.SaveChangesAsync(ct);
```
Why: the synchronous path holds the request thread for the entire database round-trip instead of
releasing it, which caps throughput at the pool size under load.
Rules: `CA1849` "Call async methods when in an async method" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1849
· `CA1828` (CountAsync/AnyAsync) — https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1828
Docs: https://learn.microsoft.com/en-us/ef/core/miscellaneous/async
· https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying
A single `DbContext` is not thread-safe: never fire concurrent async queries on one instance.

### B3.11 Holding a lock across `await`
```csharp
// bad
lock (_gate) { await DoWorkAsync(); }              // CS1996 — will not compile
// good
await _semaphore.WaitAsync(ct);
try { await DoWorkAsync(ct); } finally { _semaphore.Release(); }
```
Why: `Monitor` (and `System.Threading.Lock`) are thread-affine — the thread that exits must be the one
that entered, which an `await` cannot guarantee. `SemaphoreSlim` is the async-compatible mutex.
Rules: `CS1996` (compiler error)
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.threading.semaphoreslim.waitasync

### B3.12 `Parallel.ForEach` with an async body
```csharp
// bad
Parallel.ForEach(items, async item => await ProcessAsync(item));   // returns immediately
// good
await Parallel.ForEachAsync(items, ct, async (item, t) => await ProcessAsync(item, t));
```
Why: the body parameter is `Action<T>`, so the async lambda becomes `async void`. The loop reports
completion as soon as each iteration reaches its first `await`, and every exception is lost.
Rules: inherits the `async void` rules (`S3168`, `MA0155`, `VSTHRD100`); no rule specific to this call.
Docs: https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/async-lambda-pitfalls
· https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.parallel.foreachasync

## B4. Dictionaries and collections

### B4.1 `ContainsKey` + indexer (double lookup)
```csharp
// bad
if (d.ContainsKey(k)) return d[k];
// good
if (d.TryGetValue(k, out var v)) return v;
```
Why: two independent hash computations and bucket walks where one suffices.
Rules: `CA1854` "Prefer the 'IDictionary.TryGetValue(TKey, out TValue)' method" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1854

### B4.2 `ContainsKey` + `Add`, and the read-modify-write counter
```csharp
// bad
if (!d.ContainsKey(k)) d.Add(k, 0);
d[k] = d[k] + 1;                                     // three lookups
// good
ref int slot = ref CollectionsMarshal.GetValueRefOrAddDefault(d, k, out _);
slot++;                                              // one lookup
```
Why: each `ContainsKey`/`Add`/indexer-get/indexer-set is a separate lookup.
`GetValueRefOrAddDefault` returns a mutable reference into the bucket after a single probe.
Rules: `CA1864` "Prefer the 'IDictionary.TryAdd(TKey, TValue)' method" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1864
· `CA1853` "Unnecessary call to 'Dictionary.ContainsKey(key)'" (guarding `Remove`) —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1853
· `CA1868` "Unnecessary call to 'Contains' for sets" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1868
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.collectionsmarshal.getvaluereforadddefault
The ref returned is invalidated by any insert or resize — do not hold it across a mutation.

### B4.3 `foreach` over `Keys` then indexing
```csharp
// bad
foreach (var k in d.Keys) Use(k, d[k]);
// good
foreach (var (k, v) in d) Use(k, v);
```
Why: one hash lookup per iteration on top of the enumeration that already had the value in hand.
Rules: no rule for this exact shape `[unverified]`. `CA1841` "Prefer Dictionary Contains methods"
is the nearest confirmed rule (it targets `Keys.Contains`) —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1841

### B4.4 Growing a collection without capacity
```csharp
// bad
var list = new List<T>(); foreach (var x in src) list.Add(x);
// good
var list = new List<T>(src.Count);                   // or list.EnsureCapacity(n)
var sb = new StringBuilder(expectedLength);
var d = new Dictionary<K,V>(expectedCount);
```
Why: the backing array doubles on overflow, so building n items allocates ~log₂(n) arrays and copies
roughly 2n elements. Pre-sizing makes it one allocation and zero copies.
Rules: no analyzer rule.
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.collections.generic.list-1.ensurecapacity

### B4.5 Non-generic collections
```csharp
// bad
var list = new ArrayList(); list.Add(42);            // boxes
// good
var list = new List<int>(); list.Add(42);
```
Why: every value type stored in `ArrayList`/`Hashtable` is boxed on insert and unboxed on read — an
allocation and an indirection per element.
Rules: `CA1010` "Collections should implement generic interface" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1010
Docs: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/guidelines-for-collections

### B4.6 Exposing a mutable `List<T>` on a public API
```csharp
// bad
public List<Item> Items { get; set; }
// good
public IReadOnlyList<Item> Items => _items;
```
Why: callers can replace or mutate the backing store with no validation or change notification, and
`List<T>` pins you to a concrete type at the boundary.
Rules: `CA1002` "Do not expose generic lists" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1002
· `CA2227` "Collection properties should be read only" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2227
· `CA1819` "Properties should not return arrays" ·
`MA0016` "Prefer using collection abstraction instead of implementation" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0016.md

### B4.7 `static readonly` constant arrays and constant array arguments
```csharp
// bad
void M() => Parse(new[] { 'a', 'b', 'c' });          // fresh array per call
private static readonly byte[] Magic = { 1, 2, 3 };
// good
void M() => Parse(Magic);
private static ReadOnlySpan<byte> Magic => [1, 2, 3];   // no managed allocation at all
```
Why: a constant array literal passed as an argument is allocated on every call; a `ReadOnlySpan<T>`
property over a constant blob is emitted into the assembly's data section and never allocates.
Rules: `CA1861` "Avoid constant arrays as arguments" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1861
· `CA1878` "Prefer ReadOnlySpan properties over readonly array fields" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1878

## B5. Boxing and structs

### B5.1 Boxing through `object` / `params object[]`
```csharp
// bad
void Log(string fmt, params object[] args);          // every value-type arg is boxed
Log("{0}:{1}", id, size);
// good
void Log(ref DefaultInterpolatedStringHandler h);    // or: params ReadOnlySpan<T> (C# 13)
Log($"{id}:{size}");
```
Why: each value type passed as `object` becomes a heap allocation, plus the `object[]` itself.
Generic overloads, interpolated string handlers and `params ReadOnlySpan<T>` all avoid it.
Rules: no general boxing rule. `CA2263` "Prefer generic overload when type is known" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2263
· `CA1871` "Do not pass a nullable struct to 'ArgumentNullException.ThrowIfNull'" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1871
Docs: https://learn.microsoft.com/en-us/dotnet/framework/performance/writing-large-responsive-apps

### B5.2 Struct copies in `foreach` and on call boundaries
```csharp
// bad
foreach (var s in bigStructs) Use(s);                // copies each struct
void Process(BigStruct s) { }                        // copies on every call
// good
foreach (ref readonly var s in bigStructs.AsSpan()) Use(in s);
void Process(ref readonly BigStruct s) { }
```
Why: a non-`readonly` struct is defensively copied by the compiler on every member access through a
readonly location; large structs passed by value copy every field per call.
Rules: `IDE0250` "Struct can be made 'readonly'" · `IDE0251` "Member can be made 'readonly'" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0250
· `MA0168` "Use readonly struct for in or ref readonly parameter" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0168.md
Docs: https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/struct

### B5.3 A struct key without `IEquatable<T>`
```csharp
// bad
struct Point { public int X, Y; }                                  // uses ValueType.Equals
// good
readonly struct Point : IEquatable<Point>
{ public readonly int X, Y;
  public bool Equals(Point o) => X == o.X && Y == o.Y;
  public override int GetHashCode() => HashCode.Combine(X, Y); }
```
Why: without `IEquatable<T>`, `EqualityComparer<T>.Default` falls back to `ValueType.Equals`, which
boxes both operands and compares fields reflectively — a catastrophic cost for a dictionary key.
Rules: `CA1815` "Override equals and operator equals on value types" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1815
· `CA2231` "Overload operator equals on overriding ValueType.Equals" ·
`S3898` "Value types should implement IEquatable<T>" — https://rules.sonarsource.com/csharp/RSPEC-3898/
· `MA0065` "Default ValueType.Equals or HashCode is used for struct equality" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0065.md

### B5.4 `Enum.HasFlag`
```csharp
// bad
if (flags.HasFlag(Perm.Write)) { }
// good
if ((flags & Perm.Write) != 0) { }
```
Why: the parameter is typed `Enum`, so the argument is boxed. The JIT has recognized and devirtualized
this pattern since .NET Core 2.1, so on modern .NET the difference is usually negligible — treat the
bitwise form as a hot-path-only optimization, not a blanket rule.
Rules: `CA2248` "Provide correct 'enum' argument to 'Enum.HasFlag'" (correctness, not cost) —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2248
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.enum.hasflag

### B5.5 Closures allocated per loop iteration
```csharp
// bad
for (int i = 0; i < n; i++) handlers.Add(() => Use(i));       // one display class per iteration
// good
for (int i = 0; i < n; i++) handlers.Add(Bind(i));            // hoist, or pass state explicitly
list.Sort(static (a, b) => a.Id.CompareTo(b.Id));             // static lambda: cached, captures nothing
```
Why: a lambda that captures a local allocates a display-class instance every time it is created, and
a lambda capturing nothing is cached by the compiler only if it truly captures nothing. Mark lambdas
`static` (C# 9) to have the compiler prove that.
Rules: `IDE0320` "Make anonymous function `static`" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0320
· `S6612` "The lambda parameter should be used instead of capturing arguments in 'ConcurrentDictionary' methods" —
https://rules.sonarsource.com/csharp/RSPEC-6612/

## B6. Exceptions

### B6.1 `Parse` in a `try`/`catch` instead of `TryParse`
```csharp
// bad
try { n = int.Parse(s); } catch (FormatException) { n = 0; }
// good
if (!int.TryParse(s, out n)) n = 0;
```
Why: throwing costs on the order of microseconds (exception construction, stack capture, two-pass
unwind) versus nanoseconds for a bool return. On an expected-invalid input path this dominates.
Rules: no rule for this exact idiom `[unverified]`. `S2221` "'Exception' should not be caught" is
adjacent — https://rules.sonarsource.com/csharp/RSPEC-2221/
Docs: https://learn.microsoft.com/en-us/dotnet/standard/exceptions/best-practices-for-exceptions

### B6.2 Swallowing with `catch (Exception)`
```csharp
// bad
try { DoWork(); } catch (Exception) { }
// good
try { DoWork(); } catch (IOException ex) { _logger.LogWarning(ex, "write failed for {Path}", path); }
```
Why: a blanket empty catch hides real defects, including ones the process cannot recover from
(`OutOfMemoryException`, `StackOverflowException`), and destroys the diagnostic trail.
Rules: `CA1031` "Do not catch general exception types" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1031
· `S2221` "'Exception' should not be caught" · `S2486` "Generic exceptions should not be ignored" —
https://rules.sonarsource.com/csharp/RSPEC-2486/
· `S108` "Nested blocks of code should not be left empty" — https://rules.sonarsource.com/csharp/RSPEC-108/
· `S6667` "Logging in a catch clause should pass the caught exception as a parameter" —
https://rules.sonarsource.com/csharp/RSPEC-6667/

### B6.3 `throw ex;` losing the stack trace
```csharp
// bad
catch (Exception ex) { Log(ex); throw ex; }
// good
catch (Exception ex) { Log(ex); throw; }
```
Why: `throw ex;` resets the stack trace to the rethrow site, discarding everything below it. Use
bare `throw;`, or wrap in a new exception with `innerException` set.
Rules: `CA2200` "Rethrow to preserve stack details" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2200
· `S3445` "Exceptions should not be explicitly rethrown" — https://rules.sonarsource.com/csharp/RSPEC-3445/

### B6.4 Exceptions on an expected path
```csharp
// bad
try { return dict[key]; } catch (KeyNotFoundException) { return default; }
// good
return dict.TryGetValue(key, out var v) ? v : default;
```
Why: same cost argument as B6.1. Exceptions are for the exceptional; every `Try*` API in the BCL
exists precisely so the expected-miss case does not throw.
Rules: no general rule; the dictionary case is `CA1854`.
Docs: https://learn.microsoft.com/en-us/dotnet/standard/exceptions/best-practices-for-exceptions

### B6.5 Hand-rolled guard clauses
See A5.5. Rules: `CA1510`–`CA1513`. Traps: `CA1871` (nullable struct to `ThrowIfNull` boxes),
`CA2264` (non-nullable value to `ThrowIfNull` is dead code) —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2264
Also `CA2208` "Instantiate argument exceptions correctly" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2208

## B7. Concurrency and resources

### B7.1 `lock(this)` / `lock(typeof(X))` / `lock("literal")`
```csharp
// bad
lock (this) { ... }        lock (typeof(Cache)) { ... }
// good
private readonly Lock _gate = new();     // .NET 9; use `new object()` on .NET 8
lock (_gate) { ... }
```
Why: `this`, `Type` objects and interned string literals have *weak identity* — unrelated code in
another assembly can lock the same instance, producing deadlocks you cannot see locally.
Rules: `CA2002` "Do not lock on objects with weak identity" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2002
· `S2551` "Shared resources should not be used for locking" — https://rules.sonarsource.com/csharp/RSPEC-2551/
· `MA0064` "Avoid locking on publicly accessible instance" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0064.md
· `IDE0330` / `MA0158` (prefer `System.Threading.Lock`) —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0330

### B7.2 `new HttpClient()` per request
```csharp
// bad
using var client = new HttpClient(); return await client.GetStringAsync(url);
// good
public MyService(HttpClient client) => _client = client;   // typed client from AddHttpClient
```
Why: each `HttpClient` owns a handler and its own connection pool. Disposing one leaves sockets in
`TIME_WAIT`, so a per-request client exhausts ephemeral ports under load. Conversely, a static
`HttpClient` with a default handler never notices DNS changes — set `PooledConnectionLifetime`.
Rules: no general CA rule. Azure Functions has `AZF0002` —
https://learn.microsoft.com/en-us/azure/azure-functions/errors-diagnostics/sdk-rules/azf0002
Docs: https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/http/httpclient-guidelines
· https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory

### B7.3 Not disposing `IDisposable`
```csharp
// bad
var conn = new SqlConnection(cs); conn.Open(); Query(conn);
// good
await using var conn = new SqlConnection(cs);   // IAsyncDisposable where available
```
Why: handles, sockets and pooled connections stay held until a finalizer runs — nondeterministically,
and only if the type has one. Under exceptions the resource leaks outright.
Rules: `CA2000` "Dispose objects before losing scope" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2000
· `CA1001` "Types that own disposable fields should be disposable" ·
`CA2213` "Disposable fields should be disposed" ·
`CA1063` "Implement IDisposable correctly" · `CA1816` "Call GC.SuppressFinalize correctly" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1063
· `S2930` "'IDisposables' should be disposed" — https://rules.sonarsource.com/csharp/RSPEC-2930/
· `MA0100` "Await task before disposing of resources" · `MA0129` "Await task in using statement" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0100.md

### B7.4 Un-cached `JsonSerializerOptions`
```csharp
// bad
JsonSerializer.Serialize(o, new JsonSerializerOptions { WriteIndented = true });
// good
private static readonly JsonSerializerOptions Opts = new() { WriteIndented = true };
JsonSerializer.Serialize(o, Opts);
```
Why: `System.Text.Json` caches all reflection-derived type metadata *inside the options instance*. A
fresh instance per call rebuilds the entire metadata graph every time — often a 100× regression.
Rules: `CA1869` "Cache and reuse 'JsonSerializerOptions' instances" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1869

### B7.5 Un-guarded expensive logging
```csharp
// bad
_logger.LogDebug("state: {State}", ExpensiveDump());   // ExpensiveDump runs even at Info level
// good
if (_logger.IsEnabled(LogLevel.Debug)) _logger.LogDebug("state: {State}", ExpensiveDump());
```
Why: arguments are evaluated before the call regardless of whether the level is enabled.
Rules: `CA1873` "Avoid potentially expensive logging" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1873
· `CA1848` "Use the LoggerMessage delegates" · `CA2254` "Template should be a static expression" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2254
· `S6667` (pass the exception to the logger) — https://rules.sonarsource.com/csharp/RSPEC-6667/

## B8. I/O

### B8.1 `File.ReadAllText` on a large file
```csharp
// bad
foreach (var line in File.ReadAllText(path).Split('\n')) Process(line);
// good
await foreach (var line in File.ReadLinesAsync(path, ct)) Process(line);
```
Why: the whole file lands in one string — over ~42 500 characters that string goes on the Large Object
Heap, which is only collected on a gen-2 collection and is not compacted by default. `Split` then
doubles it. Streaming keeps the working set flat.
Rules: no analyzer rule.
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.io.file.readlinesasync
· https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/large-object-heap

### B8.2 Synchronous file APIs inside an async method
```csharp
// bad
async Task<string> LoadAsync() => File.ReadAllText(path);
// good
async Task<string> LoadAsync(CancellationToken ct) => await File.ReadAllTextAsync(path, ct);
```
Why: the sync call blocks the pool thread for the full I/O duration. Also pass
`FileOptions.Asynchronous` when constructing a `FileStream` you intend to use asynchronously,
otherwise the "async" methods run on a blocking thread anyway.
Rules: `CA1849` "Call async methods when in an async method" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1849
· `CA2024` "Do not use StreamReader.EndOfStream in async methods" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2024
· `CA1835` "Prefer the 'Memory'-based overloads for 'ReadAsync' and 'WriteAsync'" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca1835

### B8.3 Allocating I/O buffers instead of renting
```csharp
// bad
var buffer = new byte[81920];
// good
var buffer = ArrayPool<byte>.Shared.Rent(81920);
try { /* use buffer.AsSpan(0, n) */ } finally { ArrayPool<byte>.Shared.Return(buffer); }
```
Why: an 80 KB array is close to the LOH threshold and churns gen-0 when allocated per operation.
`Rent` reuses arrays and skips zero-filling. The returned array may be *larger* than requested — always
slice to the length you asked for.
Rules: no analyzer rule. `CA2014` "Do not use stackalloc in loops" guards the related mistake —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/ca2014
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.buffers.arraypool-1

### B8.4 `File.Exists` then open
```csharp
// bad
if (File.Exists(path)) { using var s = File.OpenRead(path); }
// good
try { using var s = File.OpenRead(path); } catch (FileNotFoundException) { /* handle */ }
```
Why: a time-of-check/time-of-use race — another process can delete or replace the file between the two
calls — plus a wasted syscall. The `File.Exists` docs call this out explicitly.
Rules: no analyzer rule.
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.io.file.exists

## B9. Time, randomness and formatting

### B9.1 `DateTime.Now` instead of UTC
```csharp
// bad
var stamp = DateTime.Now;
// good
var stamp = DateTimeOffset.UtcNow;        // or clock.GetUtcNow() with TimeProvider
```
Why: `DateTime.Now` reads the time zone database and applies a DST offset on every call (measurably
slower than `UtcNow`), returns an ambiguous value during a DST fall-back hour, and is untestable.
Persist UTC; convert to local only at the presentation edge.
Rules: `S6563` "Use UTC when recording DateTime instants" — https://rules.sonarsource.com/csharp/RSPEC-6563/
· `S6562` "Always set the 'DateTimeKind' when creating new 'DateTime' instances" —
https://rules.sonarsource.com/csharp/RSPEC-6562/
· `S6566` "Use 'DateTimeOffset' instead of 'DateTime'" · `S6354` "Use a testable date/time provider" —
https://rules.sonarsource.com/csharp/RSPEC-6354/
Docs: https://learn.microsoft.com/en-us/dotnet/standard/datetime/timeprovider-overview

### B9.2 `DateTime` subtraction to measure elapsed time
```csharp
// bad
var t0 = DateTime.UtcNow; Work(); var elapsed = DateTime.UtcNow - t0;
// good
var t0 = Stopwatch.GetTimestamp(); Work(); var elapsed = Stopwatch.GetElapsedTime(t0);
```
Why: the wall clock is not monotonic — NTP corrections and manual changes make it jump, so an interval
can come out negative. `Stopwatch` uses the high-resolution monotonic counter.
Rules: `S6561` "Avoid using 'DateTime.Now' for benchmarking or timing operations" —
https://rules.sonarsource.com/csharp/RSPEC-6561/ · https://github.com/SonarSource/sonar-dotnet/blob/master/analyzers/rspec/cs/S6561.json
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.stopwatch.getelapsedtime
Under `TimeProvider`, use `timeProvider.GetTimestamp()` + `GetElapsedTime(...)` so tests stay deterministic.

### B9.3 `new Random()` per call or in a loop
```csharp
// bad
for (int i = 0; i < n; i++) { var r = new Random(); a[i] = r.Next(); }
// good
for (int i = 0; i < n; i++) a[i] = Random.Shared.Next();
```
Why: an allocation per iteration, and historically a time-seeded constructor meant instances created in
the same tick produced identical sequences. `Random.Shared` is a thread-safe singleton.
For anything security-relevant use `RandomNumberGenerator`, not `Random`.
Rules: `S2245` "Pseudorandom number generators (PRNGs) should not be used in security contexts"
(security only, not this perf case) — https://rules.sonarsource.com/csharp/RSPEC-2245/
· `CA5394` "Do not use insecure randomness" (security only)
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.random.shared

### B9.4 Random GUIDs as clustered database keys
```csharp
// bad
var id = Guid.NewGuid();          // v4, fully random
// good
var id = Guid.CreateVersion7();   // v7, time-ordered (.NET 9)
```
Why: v4 GUIDs scatter inserts uniformly across a clustered index, causing page splits and
fragmentation. v7 embeds a Unix-epoch timestamp in the high bits so inserts append.
Rules: `S4581` "'new Guid()' should not be used" (a different bug — the empty GUID) —
https://rules.sonarsource.com/csharp/RSPEC-4581/
Docs: https://learn.microsoft.com/en-us/dotnet/api/system.guid.createversion7

### B9.5 Redundant `.ToString()` in interpolation
```csharp
// bad
var s = $"{count.ToString()} items";
// good
var s = $"{count} items";
// culture-sensitive contexts
var s = string.Create(CultureInfo.InvariantCulture, $"{count} items");
```
Why: the interpolation handler already calls `ToString`; the explicit call adds a redundant string
allocation that the handler then copies. It also hides the culture question.
Rules: `IDE0071` "Simplify interpolation" —
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/ide0071
· `CA1305` "Specify IFormatProvider" · `MA0044` "Remove useless ToString call" —
https://github.com/meziantou/Meziantou.Analyzer/blob/main/docs/Rules/MA0044.md
· `MA0076` "Do not use implicit culture-sensitive ToString in interpolated strings" ·
`MA0185` "Simplify string.Create when all parameters are culture invariant"

---

## Quick enforcement setup

Put this in `Directory.Build.props` so the rules above actually run:
```xml
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <Nullable>enable</Nullable>
  <ImplicitUsings>enable</ImplicitUsings>
  <AnalysisLevel>latest-recommended</AnalysisLevel>
  <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
  <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
</PropertyGroup>
```
Docs: https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview
· https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-options
Many CA performance rules (`CA1851`, `CA1854`, `CA1860`, `CA1863`, `CA1870`, `CA2007`, `CA1849`) are
**not** enabled by default — raise `AnalysisMode` or enable them per-rule in `.editorconfig`.
`Meziantou.Analyzer` and `SonarAnalyzer.CSharp` are separate NuGet packages.

---

## Sources

### Microsoft Learn — C# language
https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-12
https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-13
https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14
https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-version-history
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/configure-language-version
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/namespace
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/using-directive
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/init
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/required
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/field
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/extension
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/file
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/interface
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/partial-member
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/keywords/method-parameters
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/record
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/struct
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/ref-struct
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/nullable-reference-types
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/reference-types
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/raw-string
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/patterns
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/switch-expression
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/collection-expressions
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/new-operator
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/member-access-operators
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/operators/assignment-operator
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/statements/using
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/statements/lock
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/statements/exception-handling-statements
https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/attributes/caller-information
https://learn.microsoft.com/en-us/dotnet/csharp/programming-guide/classes-and-structs/instance-constructors
https://learn.microsoft.com/en-us/dotnet/csharp/fundamentals/program-structure/top-level-statements
https://learn.microsoft.com/en-us/dotnet/csharp/asynchronous-programming/async-return-types
https://learn.microsoft.com/en-us/dotnet/csharp/linq/standard-query-operators/join-operations
https://learn.microsoft.com/en-us/dotnet/csharp/advanced-topics/reflection-and-attributes/creating-custom-attributes

### Microsoft Learn — .NET platform and libraries
https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-6
https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-8/runtime
https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-9/libraries
https://learn.microsoft.com/en-us/dotnet/core/whats-new/dotnet-10/libraries
https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview
https://learn.microsoft.com/en-us/dotnet/core/extensions/httpclient-factory
https://learn.microsoft.com/en-us/dotnet/core/extensions/timeprovider-testing
https://learn.microsoft.com/en-us/dotnet/core/extensions/logging/high-performance-logging
https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-threadpool-starvation
https://learn.microsoft.com/en-us/dotnet/standard/datetime/timeprovider-overview
https://learn.microsoft.com/en-us/dotnet/standard/base-types/best-practices-strings
https://learn.microsoft.com/en-us/dotnet/standard/base-types/composite-formatting
https://learn.microsoft.com/en-us/dotnet/standard/base-types/regular-expression-source-generators
https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/source-generation-modes
https://learn.microsoft.com/en-us/dotnet/standard/serialization/system-text-json/reflection-vs-source-generation
https://learn.microsoft.com/en-us/dotnet/standard/exceptions/best-practices-for-exceptions
https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/common-async-bugs
https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/async-lambda-pitfalls
https://learn.microsoft.com/en-us/dotnet/standard/asynchronous-programming-patterns/executioncontext-synchronizationcontext
https://learn.microsoft.com/en-us/dotnet/standard/collections/
https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/guidelines-for-collections
https://learn.microsoft.com/en-us/dotnet/standard/garbage-collection/large-object-heap
https://learn.microsoft.com/en-us/dotnet/standard/generics/math
https://learn.microsoft.com/en-us/dotnet/framework/performance/writing-large-responsive-apps
https://learn.microsoft.com/en-us/dotnet/fundamentals/networking/http/httpclient-guidelines
https://learn.microsoft.com/en-us/dotnet/fundamentals/syslib-diagnostics/syslib1045
https://learn.microsoft.com/en-us/aspnet/core/fundamentals/best-practices
https://learn.microsoft.com/en-us/ef/core/miscellaneous/async
https://learn.microsoft.com/en-us/ef/core/performance/efficient-querying
https://learn.microsoft.com/en-us/ef/core/what-is-new/ef-core-10.0/whatsnew

### Microsoft Learn — API reference
https://learn.microsoft.com/en-us/dotnet/api/system.threading.lock
https://learn.microsoft.com/en-us/dotnet/api/system.timeprovider
https://learn.microsoft.com/en-us/dotnet/api/system.collections.generic.iasyncenumerable-1
https://learn.microsoft.com/en-us/dotnet/api/system.runtime.compilerservices.enumeratorcancellationattribute
https://learn.microsoft.com/en-us/dotnet/api/system.memoryextensions.split
https://learn.microsoft.com/en-us/dotnet/api/system.argumentnullexception.throwifnull
https://learn.microsoft.com/en-us/dotnet/api/system.argumentexception.throwifnullorwhitespace
https://learn.microsoft.com/en-us/dotnet/api/system.argumentoutofrangeexception.throwifnegative
https://learn.microsoft.com/en-us/dotnet/api/system.objectdisposedexception.throwif
https://learn.microsoft.com/en-us/dotnet/api/system.string.create
https://learn.microsoft.com/en-us/dotnet/api/system.collections.frozen.frozendictionary-2
https://learn.microsoft.com/en-us/dotnet/api/system.buffers.searchvalues-1
https://learn.microsoft.com/en-us/dotnet/api/system.buffers.arraypool-1
https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.task.wheneach
https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.parallel.foreachasync
https://learn.microsoft.com/en-us/dotnet/api/system.threading.tasks.valuetask-1
https://learn.microsoft.com/en-us/dotnet/api/system.threading.semaphoreslim.waitasync
https://learn.microsoft.com/en-us/dotnet/api/system.random.shared
https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.randomnumbergenerator.getint32
https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.countby
https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.aggregateby
https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.maxby
https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.minby
https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.order
https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.trygetnonenumeratedcount
https://learn.microsoft.com/en-us/dotnet/api/system.linq.enumerable.leftjoin
https://learn.microsoft.com/en-us/dotnet/api/system.text.regularexpressions.generatedregexattribute
https://learn.microsoft.com/en-us/dotnet/api/microsoft.extensions.logging.loggermessageattribute
https://learn.microsoft.com/en-us/dotnet/api/system.text.compositeformat
https://learn.microsoft.com/en-us/dotnet/api/system.text.stringbuilder
https://learn.microsoft.com/en-us/dotnet/api/system.text.encoding.getbytes
https://learn.microsoft.com/en-us/dotnet/api/system.text.ascii
https://learn.microsoft.com/en-us/dotnet/api/system.convert.tohexstring
https://learn.microsoft.com/en-us/dotnet/api/system.guid.createversion7
https://learn.microsoft.com/en-us/dotnet/api/system.guid.tryformat
https://learn.microsoft.com/en-us/dotnet/api/system.enum.hasflag
https://learn.microsoft.com/en-us/dotnet/api/system.enum.tostring
https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.stopwatch.getelapsedtime
https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.collectionsmarshal.asspan
https://learn.microsoft.com/en-us/dotnet/api/system.runtime.interopservices.collectionsmarshal.getvaluereforadddefault
https://learn.microsoft.com/en-us/dotnet/api/system.collections.generic.list-1.ensurecapacity
https://learn.microsoft.com/en-us/dotnet/api/system.io.file.exists
https://learn.microsoft.com/en-us/dotnet/api/system.io.file.readlinesasync
https://learn.microsoft.com/en-us/dotnet/api/system.text.json.jsonserializeroptions.web

### Microsoft Learn — analyzer rules
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/overview
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-options
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/performance-warnings
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/reliability-warnings
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/usage-warnings
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/maintainability-warnings
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/quality-rules/design-warnings
https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/style-rules/index
(individual rule pages follow the pattern `.../quality-rules/caNNNN` and `.../style-rules/ideNNNN`;
every rule cited above resolves at that path — CA1002, CA1010, CA1031, CA1068, CA1305, CA1510–CA1513,
CA1815, CA1819, CA1820, CA1825, CA1826, CA1827–CA1830, CA1831–CA1836, CA1841, CA1845–CA1849,
CA1851–CA1854, CA1858–CA1864, CA1865–CA1875, CA1878, CA2000, CA2002, CA2007, CA2012, CA2014, CA2016,
CA2024, CA2025, CA2200, CA2208, CA2227, CA2231, CA2248, CA2254, CA2263, CA2264;
IDE0057, IDE0063, IDE0071, IDE0074, IDE0090, IDE0161, IDE0210, IDE0230, IDE0250, IDE0251, IDE0290,
IDE0300–IDE0306, IDE0320, IDE0330, IDE0340, IDE0350)

### SonarSource (titles verified from the sonar-dotnet RSPEC metadata)
https://rules.sonarsource.com/csharp/RSPEC-108/
https://rules.sonarsource.com/csharp/RSPEC-1155/
https://rules.sonarsource.com/csharp/RSPEC-1643/
https://rules.sonarsource.com/csharp/RSPEC-2221/
https://rules.sonarsource.com/csharp/RSPEC-2245/
https://rules.sonarsource.com/csharp/RSPEC-2486/
https://rules.sonarsource.com/csharp/RSPEC-2551/
https://rules.sonarsource.com/csharp/RSPEC-2925/
https://rules.sonarsource.com/csharp/RSPEC-2930/
https://rules.sonarsource.com/csharp/RSPEC-2971/
https://rules.sonarsource.com/csharp/RSPEC-3168/
https://rules.sonarsource.com/csharp/RSPEC-3216/
https://rules.sonarsource.com/csharp/RSPEC-3445/
https://rules.sonarsource.com/csharp/RSPEC-3898/
https://rules.sonarsource.com/csharp/RSPEC-4462/
https://rules.sonarsource.com/csharp/RSPEC-4581/
https://rules.sonarsource.com/csharp/RSPEC-6354/
https://rules.sonarsource.com/csharp/RSPEC-6444/
https://rules.sonarsource.com/csharp/RSPEC-6561/
https://rules.sonarsource.com/csharp/RSPEC-6562/
https://rules.sonarsource.com/csharp/RSPEC-6563/
https://rules.sonarsource.com/csharp/RSPEC-6602/
https://rules.sonarsource.com/csharp/RSPEC-6605/
https://rules.sonarsource.com/csharp/RSPEC-6607/
https://rules.sonarsource.com/csharp/RSPEC-6608/
https://rules.sonarsource.com/csharp/RSPEC-6609/
https://rules.sonarsource.com/csharp/RSPEC-6610/
https://rules.sonarsource.com/csharp/RSPEC-6612/
https://rules.sonarsource.com/csharp/RSPEC-6617/
https://rules.sonarsource.com/csharp/RSPEC-6667/
https://github.com/SonarSource/sonar-dotnet/tree/master/analyzers/rspec/cs
https://github.com/SonarSource/sonar-dotnet/issues/9664

### Meziantou.Analyzer
https://github.com/meziantou/Meziantou.Analyzer/blob/main/README.md
https://github.com/meziantou/Meziantou.Analyzer/tree/main/docs/Rules
(rule pages follow `docs/Rules/MANNNN.md`; cited: MA0001, MA0004, MA0006, MA0009, MA0016, MA0020,
MA0028, MA0029, MA0031, MA0032, MA0040, MA0042, MA0044, MA0045, MA0052, MA0064, MA0065, MA0074,
MA0076, MA0080, MA0098, MA0100, MA0110, MA0111, MA0112, MA0129, MA0134, MA0143, MA0147, MA0155,
MA0158, MA0168, MA0176, MA0185, MA0227)

### Other
https://github.com/microsoft/vs-threading/blob/main/doc/analyzers/VSTHRD002.md
https://github.com/microsoft/vs-threading/blob/main/doc/analyzers/VSTHRD100.md
https://learn.microsoft.com/en-us/azure/azure-functions/errors-diagnostics/sdk-rules/azf0002
https://learn.microsoft.com/en-us/visualstudio/profiling/performance-insights-enum-hasflag
https://learn.microsoft.com/en-us/visualstudio/profiling/performance-insights-zero-length-array-allocations
