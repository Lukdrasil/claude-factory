using System.Collections.Immutable;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace Acme.Analyzers;

/// <summary>
/// Aggregate root nesmí mít public setter.
///
/// Tohle NetArchTest neuhlídá; pracuje nad IL, kde je setter jen metoda
/// a chybí kontext, že jde o vlastnost agregátu. Potřebuješ syntax tree.
///
/// Konfigurace v .editorconfig:
///   ddd_aggregate_base_types = AggregateRoot,Entity
/// </summary>
[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class AggregateRootSetterAnalyzer : DiagnosticAnalyzer
{
    public const string DiagnosticId = "DDD001";

    // ZPRÁVA JE ROZHRANÍ PRO AGENTA.
    // Napiš, co je špatně A KTERÁ konkrétní úprava to řeší; jinak agent
    // zvolí tu snazší cestu (zúží typ, přidá pragma) místo té správné.
    private static readonly DiagnosticDescriptor Rule = new(
        id: DiagnosticId,
        title: "Aggregate root exposes a public setter",
        messageFormat:
            "Property '{0}' on aggregate root '{1}' has a public setter. " +
            "Change it to 'private set' (or an init-only setter for values fixed at " +
            "construction) and add a domain method that performs the state change and " +
            "enforces the invariants around it. Do not widen the setter back.",
        category: "DDD",
        defaultSeverity: DiagnosticSeverity.Warning,
        isEnabledByDefault: true,
        description:
            "An aggregate root owns its invariants. A public setter lets callers put " +
            "the aggregate into a state the domain never sanctioned, which turns the " +
            "aggregate into a data bag and moves the rules into whoever happens to " +
            "mutate it.");

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(Rule);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(Analyze, SyntaxKind.PropertyDeclaration);
    }

    private static void Analyze(SyntaxNodeAnalysisContext context)
    {
        var property = (PropertyDeclarationSyntax)context.Node;

        var setter = property.AccessorList?.Accessors
            .FirstOrDefault(a => a.IsKind(SyntaxKind.SetAccessorDeclaration)
                              || a.IsKind(SyntaxKind.InitAccessorDeclaration));

        if (setter is null) return;

        // init-only je v pořádku; hodnota se nastaví jen při konstrukci
        if (setter.IsKind(SyntaxKind.InitAccessorDeclaration)) return;

        // setter s vlastním modifikátorem (private/protected) je v pořádku
        if (setter.Modifiers.Count > 0) return;

        // property musí být public, aby byl problém
        if (!property.Modifiers.Any(SyntaxKind.PublicKeyword)) return;

        if (context.Node.Parent is not TypeDeclarationSyntax typeDecl) return;

        var typeSymbol = context.SemanticModel.GetDeclaredSymbol(typeDecl);
        if (typeSymbol is null) return;

        if (!IsAggregate(typeSymbol, context)) return;

        context.ReportDiagnostic(Diagnostic.Create(
            Rule,
            setter.GetLocation(),
            property.Identifier.Text,
            typeSymbol.Name));
    }

    /// <summary>
    /// Je typ agregát? Základní typy jsou konfigurovatelné přes .editorconfig,
    /// takže analyzer nemusí znát tvoje jména dopředu.
    /// </summary>
    private static bool IsAggregate(INamedTypeSymbol type, SyntaxNodeAnalysisContext context)
    {
        var configured = context.Options.AnalyzerConfigOptionsProvider
            .GetOptions(context.Node.SyntaxTree)
            .TryGetValue("ddd_aggregate_base_types", out var value)
                ? value.Split(',').Select(s => s.Trim()).ToArray()
                : ["AggregateRoot", "Entity"];

        for (var t = type; t is not null; t = t.BaseType)
        {
            if (configured.Contains(t.Name, StringComparer.Ordinal)) return true;
            if (t.AllInterfaces.Any(i => configured.Contains(i.Name, StringComparer.Ordinal)))
                return true;
        }

        return false;
    }
}
