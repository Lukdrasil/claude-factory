using NetArchTest.Rules;
using Xunit;
using static Architecture.Tests.Conventions;

namespace Architecture.Tests;

/// <summary>
/// Čistota domény.
///
/// Většinu z toho už chytí BannedSymbols.Domain.txt při buildu; ten je
/// rychlejší a hlásí přesný řádek. Tyto testy pokrývají to, co BannedApi
/// neumí: tranzitivní závislosti a strukturální pravidla.
/// </summary>
public class DomainPurityTests
{
    public static TheoryData<string> Modules => ModuleNames();

    private static readonly string[] ForbiddenInDomain =
    [
        "Microsoft.EntityFrameworkCore",
        "Microsoft.AspNetCore",
        "Microsoft.Extensions.Logging",
        "Microsoft.Extensions.DependencyInjection",
        "Microsoft.Extensions.Configuration",
        "System.Net.Http",
        "System.Data",
        "Dapper",
        "Newtonsoft.Json",
    ];

    [Theory, MemberData(nameof(Modules))]
    public void Domain_has_no_outward_dependencies(string module)
    {
        var forbidden = ForbiddenInDomain
            .Concat([Ns(module, InfrastructureLayer), Ns(module, ApplicationLayer)])
            .ToArray();

        var result = Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(Ns(module, DomainLayer))
            .ShouldNot().HaveDependencyOnAny(forbidden)
            .GetResult();

        Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
            $"Domain of '{module}' depends on the outside world",
            result.FailingTypes?.Select(t => t.FullName),
            "The domain sits at the centre; everything points at it, it points at nothing. " +
            "Move the concern to the application layer, or express it as a port interface " +
            "that the domain receives as a parameter."));
    }

    [Theory, MemberData(nameof(Modules))]
    public void Domain_does_not_reference_other_modules(string module)
    {
        var others = Conventions.Modules
            .Where(m => m != module)
            .Select(m => $"{RootNamespace}.{m}")
            .ToArray();

        if (others.Length == 0) return;

        var result = Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(Ns(module, DomainLayer))
            .ShouldNot().HaveDependencyOnAny(others)
            .GetResult();

        Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
            $"Domain of '{module}' references another module",
            result.FailingTypes?.Select(t => t.FullName),
            "A domain model belongs to exactly one bounded context. If two modules " +
            "need the same concept, give each its own type and map between them at " +
            "the boundary. Sharing the type re-couples the modules."));
    }

    [Theory, MemberData(nameof(Modules))]
    public void Ports_are_interfaces(string module)
    {
        var result = Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(PortsOf(module))
            .Should().BeInterfaces()
            .GetResult();

        Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
            $"Non-interface types found in {PortsOf(module)}",
            result.FailingTypes?.Select(t => t.FullName),
            "A port is a contract, not an implementation. Move concrete types " +
            "to Infrastructure, and DTOs used by the port next to the interface " +
            "only if they carry no behaviour."));
    }
}
