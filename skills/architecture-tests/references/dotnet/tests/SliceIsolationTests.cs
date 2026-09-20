using NetArchTest.Rules;
using Xunit;
using static Architecture.Tests.Conventions;

namespace Architecture.Tests;

/// <summary>
/// Izolace vertical slices uvnitř modulu.
///
/// Slice smí sáhnout na doménu modulu a na porty. Nesmí sáhnout na
/// sousední slice; jinak vzniká skrytý coupling, který nikdo neuvidí,
/// dokud nezkusí jednu slice smazat.
/// </summary>
public class SliceIsolationTests
{
    public static TheoryData<string> Modules => ModuleNames();

    [Theory, MemberData(nameof(Modules))]
    public void Slices_do_not_depend_on_sibling_slices(string module)
    {
        var slices = SlicesOf(module);
        if (slices.Length < 2) return;

        var failures = new List<string>();

        foreach (var slice in slices)
        {
            var siblings = slices.Where(s => s != slice).ToArray();

            var result = Types.InAssemblies(AssembliesOf(module))
                .That().ResideInNamespace(slice)
                .ShouldNot().HaveDependencyOnAny(siblings)
                .GetResult();

            if (!result.IsSuccessful)
                failures.Add($"{slice}: {string.Join(", ", result.FailingTypes?.Select(t => t.FullName) ?? [])}");
        }

        Assert.True(failures.Count == 0, $"""

            Slices in module '{module}' depend on each other.

            {string.Join("\n            ", failures)}

            How to fix, in order of preference:
              1. Duplicate the small piece of logic inside each slice.
                 Slices are allowed to duplicate; that is the point.
              2. If it is a genuine domain concept, move it to {Ns(module, DomainLayer)}.
              3. If one slice needs to trigger another use case, do it through
                 the module's own {ContractsFolder}, not by calling the handler directly.
            """);
    }

    [Theory, MemberData(nameof(Modules))]
    public void Slices_are_not_public(string module)
    {
        var result = Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(FeaturesOf(module))
            .And().AreClasses()
            .Should().NotBePublic()
            .GetResult();

        Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
            $"Slice types in '{module}' are public",
            result.FailingTypes?.Select(t => t.FullName),
            $"Handlers, commands and validators are implementation details. " +
            $"Mark them internal. What the outside world may call belongs in {ContractsOf(module)}."));
    }

    [Theory, MemberData(nameof(Modules))]
    public void Slices_do_not_depend_on_infrastructure(string module)
    {
        var result = Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(FeaturesOf(module))
            .ShouldNot().HaveDependencyOnAny(Ns(module, InfrastructureLayer))
            .GetResult();

        Assert.True(result.IsSuccessful, ModuleBoundaryTests.Explain(
            $"Slices in '{module}' reach into Infrastructure",
            result.FailingTypes?.Select(t => t.FullName),
            $"Depend on an interface from {PortsOf(module)} instead. " +
            $"The concrete adapter is wired up at composition time."));
    }

    /// <summary>
    /// Namespace jednotlivých slices; {Root}.{Modul}.Application.Features.{Slice}
    /// </summary>
    private static string[] SlicesOf(string module)
    {
        var prefix = FeaturesOf(module) + ".";

        return [.. Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(FeaturesOf(module))
            .GetTypes()
            .Select(t => t.ReflectionType.Namespace)
            .Where(ns => ns is not null && ns.Length > prefix.Length)
            .Select(ns =>
            {
                var rest = ns![prefix.Length..];
                var dot = rest.IndexOf('.');
                return prefix + (dot < 0 ? rest : rest[..dot]);
            })
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)];
    }
}
