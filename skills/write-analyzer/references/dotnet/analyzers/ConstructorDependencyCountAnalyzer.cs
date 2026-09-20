using System.Collections.Immutable;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Diagnostics;

namespace Acme.Analyzers;

/// <summary>
/// Příliš mnoho konstruktorových závislostí.
///
/// SRP nejde staticky ověřit. Tohle je proxy; počet věcí, které třída
/// potřebuje k práci, koreluje s počtem věcí, které dělá.
///
/// Proti CA1506 (class coupling) má výhodu, že měří jen INJEKTOVANÉ
/// závislosti, ne všechny použité typy. Handler, který používá deset
/// DTO, není podezřelý; handler, který si nechá injektnout šest služeb,
/// ano.
///
/// Konfigurace v .editorconfig:
///   [**/Features/**/*.cs]
///   ddd_max_constructor_dependencies = 4
///
///   [**/*.Domain/**/*.cs]
///   ddd_max_constructor_dependencies = 2
/// </summary>
[DiagnosticAnalyzer(LanguageNames.CSharp)]
public sealed class ConstructorDependencyCountAnalyzer : DiagnosticAnalyzer
{
    public const string DiagnosticId = "DDD002";

    private const int DefaultMax = 4;

    private static readonly DiagnosticDescriptor Rule = new(
        id: DiagnosticId,
        title: "Too many constructor dependencies",
        messageFormat:
            "'{0}' takes {1} injected dependencies (limit is {2}). " +
            "Split it: group the dependencies that are always used together and " +
            "extract them into a single collaborator, or split the type into " +
            "separate use cases that each need fewer. If the count is genuinely " +
            "justified, raise ddd_max_constructor_dependencies for this folder " +
            "in .editorconfig rather than suppressing the diagnostic inline.",
        category: "DDD",
        defaultSeverity: DiagnosticSeverity.Warning,
        isEnabledByDefault: true,
        description:
            "The number of things a class needs to work correlates with " +
            "the number of things it does. This is a proxy for the Single " +
            "Responsibility Principle, not proof of a violation; treat it as a " +
            "prompt to look, not a verdict.");

    public override ImmutableArray<DiagnosticDescriptor> SupportedDiagnostics =>
        ImmutableArray.Create(Rule);

    public override void Initialize(AnalysisContext context)
    {
        context.ConfigureGeneratedCodeAnalysis(GeneratedCodeAnalysisFlags.None);
        context.EnableConcurrentExecution();
        context.RegisterSyntaxNodeAction(AnalyzeConstructor, SyntaxKind.ConstructorDeclaration);
        context.RegisterSyntaxNodeAction(AnalyzePrimary, SyntaxKind.ClassDeclaration);
        context.RegisterSyntaxNodeAction(AnalyzePrimary, SyntaxKind.RecordDeclaration);
    }

    private static void AnalyzeConstructor(SyntaxNodeAnalysisContext context)
    {
        var ctor = (ConstructorDeclarationSyntax)context.Node;
        Check(context, ctor.ParameterList, ctor.Identifier.Text, ctor.ParameterList.GetLocation());
    }

    private static void AnalyzePrimary(SyntaxNodeAnalysisContext context)
    {
        var type = (TypeDeclarationSyntax)context.Node;
        if (type.ParameterList is null) return;

        Check(context, type.ParameterList, type.Identifier.Text, type.ParameterList.GetLocation());
    }

    private static void Check(
        SyntaxNodeAnalysisContext context,
        ParameterListSyntax parameters,
        string typeName,
        Location location)
    {
        var max = GetLimit(context);

        // Počítáme jen to, co vypadá jako závislost: typ, ne primitivum.
        // Handler s pěti string parametry je jiný problém (to řeší S107).
        var dependencies = parameters.Parameters
            .Select(p => p.Type is null
                ? null
                : context.SemanticModel.GetTypeInfo(p.Type).Type)
            .Count(LooksLikeDependency);

        if (dependencies <= max) return;

        context.ReportDiagnostic(Diagnostic.Create(
            Rule, location, typeName, dependencies, max));
    }

    private static bool LooksLikeDependency(ITypeSymbol? type) => type switch
    {
        null => false,
        { SpecialType: not SpecialType.None } => false,          // int, string, bool...
        { TypeKind: TypeKind.Enum } => false,
        { IsValueType: true, Name: "Guid" or "DateTime" or "DateTimeOffset" or "TimeSpan" } => false,
        _ => true,
    };

    private static int GetLimit(SyntaxNodeAnalysisContext context) =>
        context.Options.AnalyzerConfigOptionsProvider
            .GetOptions(context.Node.SyntaxTree)
            .TryGetValue("ddd_max_constructor_dependencies", out var raw)
        && int.TryParse(raw, out var parsed)
            ? parsed
            : DefaultMax;
}
