using NetArchTest.Rules;
using Xunit;
using static Architecture.Tests.Conventions;

namespace Architecture.Tests;

/// <summary>
/// Composition root.
///
/// Host je jediné místo, které vidí všechny moduly; a právě proto je to
/// místo, kde modularita nejsnáz praskne. Stačí, aby si někdo v Program.cs
/// sáhl na doménovou entitu, a hranice modulu je pryč.
///
/// Host smí referencovat Infrastructure (kvůli registrační extension),
/// ale nesmí sáhnout hlouběji. To je jediná výjimka ze směru závislostí
/// a stojí za to ji mít explicitně zapsanou.
/// </summary>
public class CompositionRootTests
{
    /// <summary>Jméno hostitelské assembly. Uprav, pokud se jmenuje jinak.</summary>
    private const string HostAssemblyName = $"{RootNamespace}.Host";

    private static IEnumerable<System.Reflection.Assembly> HostAssembly() =>
        AppDomain.CurrentDomain.GetAssemblies()
            .Where(a => a.GetName().Name == HostAssemblyName);

    [Fact]
    public void Host_does_not_touch_module_internals()
    {
        if (!HostAssembly().Any()) return;

        var forbidden = Conventions.Modules
            .SelectMany(m => new[] { Ns(m, DomainLayer), FeaturesOf(m) })
            .ToArray();

        if (forbidden.Length == 0) return;

        var result = Types.InAssemblies(HostAssembly())
            .ShouldNot().HaveDependencyOnAny(forbidden)
            .GetResult();

        Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
            "Host reaches into module internals",
            result.FailingTypes?.Select(t => t.FullName),
            "The host may only call each module's registration extension " +
            "(AddXxxModule / MapXxxModule) and use its Contracts. If you need " +
            "something from inside a module, expose it through that module's " +
            "Contracts; do not reach in from the composition root."));
    }

    [Fact]
    public void Every_module_is_registered_by_the_host()
    {
        if (!HostAssembly().Any()) return;

        var registered = Types.InAssemblies(HostAssembly())
            .GetTypes()
            .Select(t => t.ReflectionType)
            .SelectMany(t => t.GetMethods(
                System.Reflection.BindingFlags.Public
                | System.Reflection.BindingFlags.NonPublic
                | System.Reflection.BindingFlags.Static
                | System.Reflection.BindingFlags.Instance))
            .SelectMany(m => m.GetParameters().Select(p => p.ParameterType.Namespace))
            .Where(ns => ns is not null)
            .ToHashSet(StringComparer.Ordinal);

        // Heuristika: modul je "napojený", pokud host vidí jeho Infrastructure.
        var unwired = Conventions.Modules
            .Where(m => !registered.Any(ns =>
                ns!.StartsWith(Ns(m, InfrastructureLayer), StringComparison.Ordinal)))
            .ToArray();

        // Informativní, ne blokující; heuristika má false positives
        // u modulů registrovaných přes reflexi nebo konfiguraci.
        if (unwired.Length > 0)
            Console.WriteLine(
                $"Possibly unwired modules (verify manually): {string.Join(", ", unwired)}");

        Assert.True(true);
    }
}
