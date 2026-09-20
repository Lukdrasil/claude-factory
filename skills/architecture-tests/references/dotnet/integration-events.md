# Integrační eventy místo synchronních volání

Kit ve výchozím stavu předpokládá, že moduly spolu mluví synchronně
přes `Contracts`. Pokud jdeš eventy, změní se dvě věci.

## 1. Konvence

```csharp
// ArchitectureConventions.cs
public const string? IntegrationEventsFolder = "IntegrationEvents";
```

Tím se `PublicSurfaceOf()` rozšíří o event namespace a testy začnou
brát eventy jako legitimní součást public surface.

## 2. Zpřísněné pravidlo hranic

Ve variantě s eventy nechceš, aby modul volal cizí `Contracts`;
jinak máš obojí a nikdo neví, co platí. Nahraď v `ModuleBoundaryTests`:

```csharp
[Theory, MemberData(nameof(Modules))]
public void Modules_communicate_only_through_integration_events(string module)
{
    var forbidden = Conventions.Modules
        .Where(m => m != module)
        .SelectMany(m => new[]
        {
            Ns(m, DomainLayer),
            Ns(m, InfrastructureLayer),
            FeaturesOf(m),
            ContractsOf(m),          // ← nově zakázáno i tohle
        })
        .ToArray();

    var result = Types.InAssemblies(AssembliesOf(module))
        .ShouldNot().HaveDependencyOnAny(forbidden)
        .GetResult();

    Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
        $"Module '{module}' calls another module directly",
        result.FailingTypeNames,
        "Modules communicate through integration events. Publish an event " +
        "from this module and subscribe to it in the other one. If you need " +
        "a synchronous answer, that is a sign the two modules are really one."));
}
```

## 3. Event projekt bez závislostí

```
Acme.<Modul>.IntegrationEvents/     ← samostatný projekt
    <Something>Happened.cs           public sealed record
```

Musí být samostatný projekt, ne složka v Application. Důvod: konzumenti
ho referencují, a kdyby byl v Application, dostali by s ním i porty
a contracts, které vidět nemají.

Test, který to hlídá:

```csharp
[Theory, MemberData(nameof(Modules))]
public void Integration_events_have_no_dependencies(string module)
{
    var result = Types.InAssemblies(AssembliesOf(module))
        .That().ResideInNamespace($"{RootNamespace}.{module}.IntegrationEvents")
        .ShouldNot().HaveDependencyOnAny(
            Ns(module, DomainLayer),
            Ns(module, ApplicationLayer),
            Ns(module, InfrastructureLayer))
        .GetResult();

    Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
        $"Integration events of '{module}' depend on module internals",
        result.FailingTypeNames,
        "An integration event is a serializable contract with no behaviour. " +
        "Use primitives and plain records; never a domain type."));
}
```

## Kdy zvolit kterou variantu

| | Synchronní Contracts | Integrační eventy |
|---|---|---|
| Konzistence | okamžitá | eventual |
| Ladění | snadné | těžší (async, korelace) |
| Rozpad na služby | vyžaduje přepis | připravené |
| Cyklické závislosti | musíš je hlídat | přirozeně se nedějí |

Doporučení: začni synchronně a přejdi na eventy až když víš, že
konkrétní modul chceš oddělit. Eventy zavedené dopředu "pro jistotu"
platíš složitostí každý den bez užitku.
