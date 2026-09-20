using System.Runtime.CompilerServices;
using NetArchTest.Rules;
using Xunit;
using static Architecture.Tests.Conventions;

namespace Architecture.Tests;

/// <summary>
/// Public surface modulu = Contracts + Ports + registrační extension.
/// Nic jiného. Tenhle jediný test drží celý model viditelnosti.
/// </summary>
public class PublicSurfaceTests
{
    public static TheoryData<string> Modules => ModuleNames();

    [Theory, MemberData(nameof(Modules))]
    public void Module_exposes_only_its_declared_surface(string module)
    {
        var surface = PublicSurfaceOf(module);

        var leaks = Types.InAssemblies(AssembliesOf(module))
            .That().ArePublic()
            .GetTypes()
            .Select(t => t.ReflectionType)
            .Where(t => !IsCompilerGenerated(t))
            .Where(t => !IsNested(t))
            .Where(t => !IsExplicitlyAllowed(t))
            .Where(t => !InAnyNamespace(t, surface))
            .Where(t => !InAnyNamespace(t, GrandfatheredNamespaces))
            .Select(t => t.FullName!)
            .Order(StringComparer.Ordinal)
            .ToArray();

        Assert.True(leaks.Length == 0, $"""

            Module '{module}' exposes types outside its public surface.

            Leaking types:
              {string.Join("\n  ", leaks.Take(20))}
              {(leaks.Length > 20 ? $"... and {leaks.Length - 20} more" : "")}

            The public surface of a module is:
              - {string.Join("\n              - ", surface)}
              - one registration extension ({string.Join(", ", AllowedPublicTypeSuffixes)})

            How to fix, pick one:
              1. Mark the type internal. This is correct for handlers, entities,
                 adapters and anything else that is an implementation detail.
              2. If it genuinely is part of what this module offers to others,
                 move it into the {ContractsFolder} namespace.

            Do not add it to AllowedPublicTypeSuffixes unless it is infrastructure
            plumbing that a framework requires to be public.
            """);
    }

    // Pozn.: Ports záměrně nekontrolujeme na public. Port, jehož signatura
    // používá interní doménový typ (typicky repository), public být NEMŮŽE
    // (CS0050); implementuje ho Infrastructure přes InternalsVisibleTo.
    // Public port je povolený (viz PublicSurfaceOf), ne povinný.
    [Theory, MemberData(nameof(Modules))]
    public void Contracts_are_public(string module)
    {
        var result = Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(ContractsOf(module))
            .Should().BePublic()
            .GetResult();

        Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
            $"Internal types found in the Contracts of '{module}'",
            result.FailingTypes?.Select(t => t.FullName),
            $"Either make them public, or move them out of {ContractsFolder}; " +
            $"an internal type in the contract namespace is confusing to readers."));
    }

    [Theory, MemberData(nameof(Modules))]
    public void Implementation_classes_are_sealed(string module)
    {
        // AreNotStatic: static třídy (endpointy) nejsou v C# pohledu sealed
        var result = Types.InAssemblies(AssembliesOf(module))
            .That().AreClasses()
            .And().AreNotAbstract()
            .And().AreNotStatic()
            .And().ResideInNamespace(FeaturesOf(module))
            .Should().BeSealed()
            .GetResult();

        Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
            $"Unsealed handler classes in '{module}'",
            result.FailingTypes?.Select(t => t.FullName),
            "Seal them. Handlers are not extension points; if you need variation, " +
            "add another slice. Sealing also lets the JIT devirtualise calls."));
    }

    [Theory, MemberData(nameof(Modules))]
    public void Module_has_exactly_one_registration_entry_point(string module)
    {
        var entryPoints = Types.InAssemblies(AssembliesOf(module))
            .That().ArePublic()
            .And().AreStatic()
            .GetTypes()
            .Select(t => t.ReflectionType)
            .Where(t => t.Name.EndsWith("ModuleExtensions", StringComparison.Ordinal))
            .Select(t => t.FullName!)
            .ToArray();

        Assert.True(entryPoints.Length <= 1, $"""

            Module '{module}' has more than one registration entry point:
              {string.Join("\n  ", entryPoints)}

            How to fix:
              Consolidate them into a single static class. One module, one
              Add{module}Module call, one place where the host wires it up.
              Splitting registration makes it impossible to tell what the
              module actually needs.
            """);
    }

    // -----------------------------------------------------------------------

    private static bool IsCompilerGenerated(Type t) =>
        t.IsDefined(typeof(CompilerGeneratedAttribute), inherit: false)
        || t.Name.Contains('<', StringComparison.Ordinal)      // <>c, lambdas, iterators
        || t.Name.StartsWith("<", StringComparison.Ordinal)
        || t.Namespace is null;                                 // C# 14 extension plumbing

    private static bool IsNested(Type t) => t.IsNested;

    private static bool IsExplicitlyAllowed(Type t) =>
        AllowedPublicTypeSuffixes.Any(s => t.Name.EndsWith(s, StringComparison.Ordinal));

    private static bool InAnyNamespace(Type t, string[] namespaces) =>
        t.Namespace is { } ns
        && namespaces.Any(n => ns.Equals(n, StringComparison.Ordinal)
                            || ns.StartsWith(n + ".", StringComparison.Ordinal));
}
