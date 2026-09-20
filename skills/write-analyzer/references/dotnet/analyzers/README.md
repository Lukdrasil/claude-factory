# Vlastní Roslyn analyzery

Dva funkční analyzery pro pravidla, která nepokryje žádný existující
nástroj ani architektonický test.

| ID | Pravidlo | Proč vlastní analyzer |
|---|---|---|
| DDD001 | Aggregate root nesmí mít public setter | NetArchTest pracuje nad IL, kde setter je jen metoda; chybí kontext |
| DDD002 | Max počet konstruktorových závislostí | CA1506 měří všechny typy, ne jen injektované; tohle je přesnější SRP proxy |

## Zapojení

**Varianta A; projekt v řešení (doporučeno pro start):**

```xml
<!-- v každém projektu, který má být analyzovaný -->
<ItemGroup>
  <ProjectReference Include="..\..\analyzers\Acme.Analyzers.csproj"
                    OutputItemType="Analyzer"
                    ReferenceOutputAssembly="false" />
</ItemGroup>
```

Nebo globálně přes Directory.Build.props (viz `analyzers-wireup.props` vedle tohoto souboru).

**Varianta B; NuGet balíček:** až budeš analyzery sdílet napříč repy.
Vyžaduje `analyzers/dotnet/cs/` cestu v balíčku a `.globalconfig` pro
distribuci severit (klasický `.editorconfig` z NuGetu nefunguje).

## Konfigurace

```ini
[**/*.Domain/**/*.cs]
ddd_aggregate_base_types = AggregateRoot,Entity
ddd_max_constructor_dependencies = 2
dotnet_diagnostic.DDD001.severity = warning

[**/Features/**/*.cs]
ddd_max_constructor_dependencies = 4
dotnet_diagnostic.DDD002.severity = warning
```

Prahy z `.editorconfig` znamenají, že nemusíš analyzer rekompilovat,
když chceš jinou přísnost v jiné vrstvě.

## Verze balíčků (CPM)

Analyzer a jeho testy potřebují tyto `PackageVersion` záznamy v
`Directory.Packages.props` konzumujícího repa (volit nejnižší verzi
Roslynu, která pokrývá use case; vyšší verze znamená, že analyzer
nepoběží ve starších SDK):

```xml
<PackageVersion Include="Microsoft.CodeAnalysis.CSharp" Version="4.8.0" />
<PackageVersion Include="Microsoft.CodeAnalysis.Analyzers" Version="3.11.0" />
<PackageVersion Include="Microsoft.CodeAnalysis.CSharp.Analyzer.Testing" Version="1.1.2" />
<PackageVersion Include="Microsoft.CodeAnalysis.CSharp.Workspaces" Version="4.8.0" />
```

## Psaní dalších analyzerů

Startovní bod, který doporučuji místo VS šablony "Analyzer with Code Fix":
https://github.com/tom-englert/RoslynAnalyzerCookbook

Testování přes `Microsoft.CodeAnalysis.Testing`:

```csharp
await new CSharpAnalyzerTest<AggregateRootSetterAnalyzer, DefaultVerifier>
{
    // TestCode musí deklarovat i base typy, na které analyzer reaguje;
    // testovací kompilace nevidí nic jiného.
    TestCode = """
        public abstract class AggregateRoot { }

        public class Order : AggregateRoot
        {
            public string Status { get; [|set|]; }
        }
        """
}.RunAsync();
```

## Zásada pro MessageFormat

Zpráva je rozhraní pro agenta i pro juniora. Piš **co je špatně
A KTERÁ konkrétní úprava to řeší.** Bez druhé části agent zvolí
nejsnazší cestu k zelenému buildu; obvykle pragma nebo zúžení typu;
místo té správné.

Špatně: "Class does too much"
Dobře:  "'X' takes 7 injected dependencies (limit 4). Split it: group
         the dependencies that are always used together and extract
         them into a single collaborator..."
