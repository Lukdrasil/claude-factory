using NetArchTest.Rules;
using Xunit;
using static Architecture.Tests.Conventions;

namespace Architecture.Tests;

/// <summary>
/// Hranice mezi moduly. Toto je nejdůležitější sada v celém kitu;
/// bez ní se modulární monolit během roku slepí zpátky do jedné koule.
/// </summary>
public class ModuleBoundaryTests
{
    public static TheoryData<string> Modules => ModuleNames();

    [Theory, MemberData(nameof(Modules))]
    public void Module_reaches_other_modules_only_through_their_public_surface(string module)
    {
        var forbidden = Conventions.Modules
            .Where(m => m != module)
            .SelectMany(InternalsOf)
            .ToArray();

        if (forbidden.Length == 0) return;

        var result = Types.InAssemblies(AssembliesOf(module))
            .That().DoNotResideInNamespaceMatching(GrandfatheredPattern)
            .ShouldNot().HaveDependencyOnAny(forbidden)
            .GetResult();

        Assert.True(result.IsSuccessful, Explain(
            $"Module '{module}' reaches into another module's internals",
            result.FailingTypes?.Select(t => t.FullName),
            $"Call the other module through its {ContractsFolder} namespace instead. " +
            $"If the API you need is missing there, add it to that module's {ContractsFolder}; " +
            $"do not widen the visibility of its internal types."));
    }

    [Theory, MemberData(nameof(Modules))]
    public void Contracts_do_not_leak_domain_types(string module)
    {
        var result = Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(ContractsOf(module))
            .ShouldNot().HaveDependencyOnAny(Ns(module, DomainLayer))
            .GetResult();

        Assert.True(result.IsSuccessful, Explain(
            $"Contracts of '{module}' expose domain types",
            result.FailingTypes?.Select(t => t.FullName),
            "Contracts must be plain DTOs. Add a mapping step inside the module " +
            "that converts the domain type into a contract type."));
    }

    [Theory, MemberData(nameof(Modules))]
    public void Application_does_not_depend_on_infrastructure(string module)
    {
        var result = Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(Ns(module, ApplicationLayer))
            .ShouldNot().HaveDependencyOnAny(Ns(module, InfrastructureLayer))
            .GetResult();

        Assert.True(result.IsSuccessful, Explain(
            $"Application layer of '{module}' depends on Infrastructure",
            result.FailingTypes?.Select(t => t.FullName),
            $"Dependencies point inward. Define what you need as an interface in " +
            $"{PortsOf(module)} and implement it in Infrastructure."));
    }

    [Fact]
    public void No_dependency_cycles_between_modules()
    {
        var result = Types.InAssemblies(AllModuleAssemblies())
            .Slice().ByNamespacePrefix($"{RootNamespace}.*")
            .Should().NotHaveDependenciesBetweenSlices()
            .GetResult();

        Assert.True(result.IsSuccessful, Explain(
            "Dependency cycle between modules",
            result.FailingTypes?.Select(t => t.FullName),
            "A cycle means these modules are one module. Either merge them, " +
            "or break the cycle by moving the shared concept into a third module " +
            "or by inverting one direction with an integration event."));
    }

    internal static string Explain(string what, IEnumerable<string?>? offenders, string howToFix)
    {
        var list = offenders?.Take(15).ToArray() ?? [];
        var more = (offenders?.Count() ?? 0) - list.Length;

        return $"""

            {what}.

            Offending types:
              {string.Join("\n  ", list)}{(more > 0 ? $"\n  ... and {more} more" : "")}

            How to fix:
              {howToFix}
            """;
    }
}
