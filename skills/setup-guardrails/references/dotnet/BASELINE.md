# Baseline: how to freeze existing debt

Goal: **new code under full rules, old code doesn't block the build, and debt is visible.**

Three techniques, from coarsest to most precise. Most projects use a mix.

---

## A) Excluding the whole project (coarsest)

For legacy projects that are going to be rewritten anyway:

```xml
<!-- Legacy.OldModule.csproj -->
<PropertyGroup>
  <QualityLevel>Baseline</QualityLevel>
  <NoWarn>$(NoWarn);CA1062;CA1031;S1200</NoWarn>
</PropertyGroup>
```

**When to use:** the project is written off, migration is planned.
**When not to use:** the project is actively developed; new code would escape the rules.

---

## B) `.editorconfig` section for legacy paths (medium)

```ini
# Everything new is under full rules...
[src/Modules/**/*.cs]
dotnet_diagnostic.CA1506.severity = warning
dotnet_diagnostic.S1200.severity = warning

# ...except these, until we clean them up.
# Issue: #142, deadline Q3
[src/Modules/Orders/Legacy/**/*.cs]
dotnet_diagnostic.CA1506.severity = none
dotnet_diagnostic.S1200.severity = none
```

**Advantage:** visible in one place, the comment carries context.
**Disadvantage:** new code in that folder also escapes. That's why it's
important for legacy folders to be *closed*; nothing new gets added to them.

A test that watches this is worth writing:

```csharp
[Fact]
public void Legacy_namespaces_are_not_growing()
{
    var count = Types.InAssemblies(AllModuleAssemblies())
        .That().ResideInNamespaceMatching(GrandfatheredPattern)
        .GetTypes().Count();

    // Lower this number with every cleanup. Never raise it.
    Assert.True(count <= 47,
        $"Legacy namespaces grew to {count} types. " +
        $"New code must not be added to grandfathered namespaces.");
}
```

That test is quietly the most useful thing in the whole kit: **debt can
only decrease.** If someone increases it, it must be a conscious act,
and it shows up in the diff.

---

## C) `#pragma` with a reference (most precise)

```csharp
#pragma warning disable CA1506 // Legacy God object, see #142
internal sealed class OrderProcessor
#pragma warning restore CA1506
```

**Advantage:** precise, doesn't touch surrounding code, the reason sits next to the code.
**Disadvantage:** a lot of diff noise when there are hundreds of occurrences.

This can be automated via `dotnet format analyzers --severity warn`, but
for architectural rules it won't produce a meaningful fix; it just
formats. For bulk suppression, option B is better.

---

## Suppression file for CA rules

For CA*, there's `GlobalSuppressions.cs`, which Visual Studio generates
via "Suppress → In Suppression File":

```csharp
[assembly: SuppressMessage("Design", "CA1506:Avoid excessive class coupling",
    Justification = "Legacy, tracked in #142",
    Scope = "type", Target = "~T:Acme.Orders.Legacy.OrderProcessor")]
```

Advantage over `#pragma`: it's all in one place and `Justification` is
mandatory. Disadvantage: doesn't work for Sonar (S*) rules, only for CA*.

---

## Recommended combination

| Situation | Technique |
|---|---|
| Written-off project | A; `NoWarn` on the project |
| Legacy folder in a live project | B; `.editorconfig` + growth test |
| Individual justified exception | C; `#pragma` with an issue reference |
| Architectural violation | `GrandfatheredNamespaces` + growth test |

---

## Metric to track

Not "how many warnings do we have", but **"is it going down?"**. Add a
CI job that prints the count (non-blocking):

```yaml
debt-report:
  stage: report
  script:
    - dotnet build -warnaserror- 2>&1 | grep -c "warning" | tee debt.txt
  artifacts:
    paths: [debt.txt]
  allow_failure: true
```

A three-month trend tells you more than the absolute number.
