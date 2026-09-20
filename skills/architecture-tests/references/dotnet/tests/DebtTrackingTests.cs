using NetArchTest.Rules;
using Xunit;
using static Architecture.Tests.Conventions;

namespace Architecture.Tests;

/// <summary>
/// Hlídá, že technický dluh může jen klesat.
///
/// Nejcennější test v celém kitu při zavádění na existující codebase.
/// Bez něj se z baseline stane trvalý stav; někdo přidá kód do legacy
/// namespace, nikdo si nevšimne, a za rok je legacy větší než nový kód.
///
/// Postup: sniž číslo při každém úklidu. Nikdy nezvyšuj bez diskuze v MR.
/// </summary>
public class DebtTrackingTests
{
    /// <summary>
    /// Kolik typů smí zůstat v grandfathered namespace.
    /// Nastav při zavedení na aktuální počet, pak jen snižuj.
    /// </summary>
    private const int MaxGrandfatheredTypes = 0;

    /// <summary>
    /// Kolik výjimek smí být v AllowedPublicTypeSuffixes.
    /// Každá je díra v modelu viditelnosti.
    /// </summary>
    private const int MaxPublicSurfaceExceptions = 2;

    [Fact]
    public void Grandfathered_namespaces_are_not_growing()
    {
        if (GrandfatheredNamespaces.Length == 0)
        {
            Assert.Equal(0, MaxGrandfatheredTypes);
            return;
        }

        var types = Types.InAssemblies(AllModuleAssemblies())
            .That().ResideInNamespaceMatching(GrandfatheredPattern)
            .GetTypes()
            .ToArray();

        Assert.True(types.Length <= MaxGrandfatheredTypes, $"""

            Grandfathered namespaces now hold {types.Length} types,
            over the ceiling of {MaxGrandfatheredTypes}.

            New code must not be added to namespaces that are exempt from
            architecture rules. Either:
              1. Put the new code in a properly structured module, or
              2. If you cleaned up and the count legitimately changed,
                 lower MaxGrandfatheredTypes in this file.

            Raising the ceiling is a deliberate decision that belongs in
            a merge request discussion, not a quiet edit.
            """);
    }

    [Fact]
    public void Public_surface_exceptions_are_bounded()
    {
        Assert.True(AllowedPublicTypeSuffixes.Length <= MaxPublicSurfaceExceptions, $"""

            AllowedPublicTypeSuffixes has grown to {AllowedPublicTypeSuffixes.Length} entries:
              {string.Join("\n  ", AllowedPublicTypeSuffixes)}

            Each entry is a hole in the module visibility model. Legitimate
            reasons are narrow: a framework requires the type to be public
            (EF design-time factory), or it is the module registration
            extension.

            If you are adding one because a type "needs" to be public,
            the type most likely belongs in Contracts instead.
            """);
    }

    /// <summary>
    /// Informativní; nikdy nepadá, jen vypíše rozložení do test outputu.
    /// Užitečné pro sledování trendu bez blokování pipeline.
    /// </summary>
    [Fact]
    public void Report_module_sizes()
    {
        foreach (var module in Conventions.Modules)
        {
            var domain = CountIn(module, DomainLayer);
            var app = CountIn(module, ApplicationLayer);
            var infra = CountIn(module, InfrastructureLayer);

            Console.WriteLine(
                $"{module,-20} domain:{domain,4}  app:{app,4}  infra:{infra,4}");
        }

        Assert.True(true);
    }

    private static int CountIn(string module, string layer) =>
        Types.InAssemblies(AssembliesOf(module))
            .That().ResideInNamespace(Ns(module, layer))
            .GetTypes().Count();
}
