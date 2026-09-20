using System.Reflection;
using System.Text.RegularExpressions;
using Xunit;

namespace Architecture.Tests;

/// <summary>
/// JEDINÉ místo, kde je popsaná architektura řešení.
/// Testy v ostatních souborech jsou napsané proti tomuto popisu;
/// při adaptaci na jinou strukturu uprav tento soubor a nic jiného.
/// </summary>
public static class Conventions
{
    // -------------------------------------------------------------------
    //  1. Kde jsou moduly
    // -------------------------------------------------------------------

    /// <summary>Prefix, který mají všechny assembly řešení. Uprav.</summary>
    public const string RootNamespace = "Acme";

    /// <summary>
    /// Moduly se objeví automaticky. Konvence: assembly se jmenuje
    /// {Root}.{Modul}.{Vrstva}; např. Acme.Orders.Domain.
    /// Pokud máš jinou konvenci, přepiš tuto metodu na explicitní seznam:
    ///     public static IReadOnlyList&lt;string&gt; Modules =&gt; ["Orders", "Billing"];
    /// </summary>
    public static IReadOnlyList<string> Modules { get; } = DiscoverModules();

    // -------------------------------------------------------------------
    //  2. Jak se jmenují vrstvy uvnitř modulu
    // -------------------------------------------------------------------

    public const string DomainLayer = "Domain";
    public const string ApplicationLayer = "Application";
    public const string InfrastructureLayer = "Infrastructure";

    /// <summary>Co modul nabízí ven. Public.</summary>
    public const string ContractsFolder = "Contracts";

    /// <summary>Co modul potřebuje zvenčí. Public.</summary>
    public const string PortsFolder = "Ports";

    /// <summary>Vertical slices. Internal.</summary>
    public const string FeaturesFolder = "Features";

    /// <summary>
    /// Integrační eventy; samostatný namespace, pokud je používáš.
    /// Nech null, pokud moduly komunikují jen synchronně přes Contracts.
    /// </summary>
    public const string? IntegrationEventsFolder = null;

    // -------------------------------------------------------------------
    //  3. Výjimky z pravidel
    //
    //  Každá výjimka je technický dluh. Pokud jich přibývá,
    //  pravděpodobně je špatně pravidlo, ne kód.
    // -------------------------------------------------------------------

    /// <summary>
    /// Typy, které smí být public i mimo Contracts/Ports.
    /// Typicky: registrační extension, EF design-time factory.
    /// </summary>
    public static readonly string[] AllowedPublicTypeSuffixes =
    [
        "ModuleExtensions",              // AddOrdersModule / MapOrdersModule
        "DesignTimeDbContextFactory",    // dotnet ef migrations
    ];

    /// <summary>
    /// Namespace, které se při kontrolách ignorují úplně.
    /// Sem patří legacy kód, který teprve migruješ.
    /// Cíl je mít prázdné pole.
    /// </summary>
    public static readonly string[] GrandfatheredNamespaces =
    [
        // $"{RootNamespace}.Legacy",
    ];

    /// <summary>Regex pro NetArchTest *NamespaceMatching metody. "(?!)" nikdy nematchne.</summary>
    public static string GrandfatheredPattern =>
        GrandfatheredNamespaces.Length == 0
            ? "(?!)"
            : "^(" + string.Join("|", GrandfatheredNamespaces.Select(Regex.Escape)) + ")";

    // -------------------------------------------------------------------
    //  Pomocné metody. Předpokládají jména {Root}.{Modul}.{Vrstva} s root
    //  prefixem. Repo s konvencí {Modul}.{Vrstva} (bez prefixu) vyžaduje
    //  úpravu Ns/AssembliesOf/DiscoverModules; počítej s tím při adaptaci.
    // -------------------------------------------------------------------

    public static string Ns(string module, string layer) =>
        $"{RootNamespace}.{module}.{layer}";

    public static string Ns(string module, string layer, string folder) =>
        $"{RootNamespace}.{module}.{layer}.{folder}";

    public static string ContractsOf(string module) =>
        Ns(module, ApplicationLayer, ContractsFolder);

    public static string PortsOf(string module) =>
        Ns(module, ApplicationLayer, PortsFolder);

    public static string FeaturesOf(string module) =>
        Ns(module, ApplicationLayer, FeaturesFolder);

    /// <summary>Vše, co je uvnitř modulu a nesmí to vidět nikdo zvenčí.</summary>
    public static string[] InternalsOf(string module) =>
    [
        Ns(module, DomainLayer),
        Ns(module, InfrastructureLayer),
        FeaturesOf(module),
    ];

    /// <summary>Co modul smí nabídnout ven.</summary>
    public static string[] PublicSurfaceOf(string module)
    {
        var surface = new List<string> { ContractsOf(module), PortsOf(module) };
        if (IntegrationEventsFolder is not null)
            surface.Add(Ns(module, ApplicationLayer, IntegrationEventsFolder));
        return [.. surface];
    }

    public static IEnumerable<Assembly> AssembliesOf(string module) =>
        LoadedAssemblies().Where(a =>
            a.GetName().Name?.StartsWith($"{RootNamespace}.{module}.", StringComparison.Ordinal) == true);

    public static IEnumerable<Assembly> AllModuleAssemblies() =>
        Modules.SelectMany(AssembliesOf);

    /// <summary>xUnit MemberData zdroj.</summary>
    public static TheoryData<string> ModuleNames()
    {
        var data = new TheoryData<string>();
        foreach (var m in Modules) data.Add(m);
        return data;
    }

    private static IReadOnlyList<string> DiscoverModules() =>
        [.. LoadedAssemblies()
            .Select(a => a.GetName().Name)
            .Where(n => n?.StartsWith($"{RootNamespace}.", StringComparison.Ordinal) == true)
            .Select(n => n!.Split('.'))
            .Where(parts => parts.Length >= 3)
            .Select(parts => parts[1])
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)];

    private static Assembly[] LoadedAssemblies()
    {
        // Vynutí načtení všech modulových assembly; bez toho by
        // AppDomain obsahoval jen ty, na které už někdo sáhl.
        var dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!;
        foreach (var dll in Directory.GetFiles(dir, $"{RootNamespace}.*.dll"))
        {
            try { Assembly.LoadFrom(dll); }
            catch (BadImageFormatException) { /* nativní nebo mixed-mode */ }
            catch (FileLoadException) { /* už načtená */ }
        }

        return [.. AppDomain.CurrentDomain.GetAssemblies()
            .Where(a => !a.IsDynamic && a.GetName().Name?.StartsWith(RootNamespace, StringComparison.Ordinal) == true)];
    }
}
