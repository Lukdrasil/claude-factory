# Šablona modulu

Referenční struktura jednoho modulu. Zkopíruj, přejmenuj `__MODULE__`
na jméno modulu, smaž, co nepoužiješ.

Cílem není generátor; je to **vzor, proti kterému se dá porovnat
existující modul** a vidět, co chybí.

```
src/Modules/__MODULE__/
│
├── Acme.__MODULE__.Domain/                 ← žádné závislosti ven
│   ├── Acme.__MODULE__.Domain.csproj
│   ├── <Aggregate>.cs                      internal sealed
│   ├── <ValueObject>.cs                    internal readonly record struct
│   └── <DomainEvent>.cs                    internal sealed record
│
├── Acme.__MODULE__.Application/
│   ├── Acme.__MODULE__.Application.csproj  → referencuje Domain
│   │
│   ├── Contracts/                          ← PUBLIC: co modul nabízí
│   │   ├── I__MODULE__Api.cs
│   │   └── <Dto>.cs                        plain DTO, žádné doménové typy
│   │
│   ├── Ports/                              ← PUBLIC: co modul potřebuje
│   │   ├── I<Something>Repository.cs
│   │   └── I<Something>Gateway.cs
│   │
│   └── Features/                           ← INTERNAL: vertical slices
│       ├── <UseCaseA>/
│       │   ├── <UseCaseA>Command.cs        internal sealed record
│       │   ├── <UseCaseA>Handler.cs        internal sealed
│       │   ├── <UseCaseA>Validator.cs      internal sealed
│       │   └── <UseCaseA>Endpoint.cs       internal static
│       └── <UseCaseB>/
│           └── ...
│
└── Acme.__MODULE__.Infrastructure/         → referencuje Application
    ├── Acme.__MODULE__.Infrastructure.csproj
    ├── __MODULE__ModuleExtensions.cs       ← PUBLIC: jediný vstupní bod
    ├── Persistence/
    │   ├── __MODULE__DbContext.cs          internal
    │   └── <Something>Repository.cs        internal sealed
    └── Adapters/
        └── Http<Something>Gateway.cs       internal sealed
```

## Pravidla, která z toho plynou

| Co | Viditelnost | Proč |
|---|---|---|
| Contracts | `public` | to je API modulu |
| Ports | `public`, nebo `internal` když signatura používá doménové typy (repository); Infrastructure je vidí přes `InternalsVisibleTo` | |
| `__MODULE__ModuleExtensions` | `public static` | host ho musí zavolat |
| Vše ostatní | `internal sealed` | implementační detail |

## Reference mezi projekty

```
Domain           → nic
Application      → Domain
Infrastructure   → Application (a přes něj Domain)
Host             → Infrastructure každého modulu
```

Nikdy naopak. Test `Application_does_not_depend_on_infrastructure`
to hlídá.

## Soubory v této složce

- `ModuleExtensions.cs.template`; registrační vstupní bod
- `Slice.cs.template`; kompletní vertical slice v jednom souboru
- `DesignTimeDbContextFactory.cs.template`; pro `dotnet ef migrations`
- `Domain.csproj.template`, `Application.csproj.template`,
  `Infrastructure.csproj.template`; projektové soubory

## Poznámka ke "slice v jednom souboru"

`Slice.cs.template` má command, handler, validátor i endpoint v jednom
souboru. To je záměr; slice je jednotka, kterou chceš vidět celou naráz
a umět smazat jedním `rm`. Rozdělení do čtyř souborů má smysl až když
jeden přeroste ~200 řádků, což je zároveň signál, že use case je moc velký.
