# Model, ze kterého kit vychází

Referenční dokument. Popisuje **proč** jsou pravidla taková, jaká jsou;
užitečné, když se rozhoduješ, jestli je pravidlo v tvém případě správné,
nebo když ho chceš vysvětlit agentovi.

---

## Tři osy dělení a jak se nekříží

Hexagon dělí **horizontálně** (doména / porty / adaptéry).
Vertical slices dělí **vertikálně** (per use case).
Moduly dělí podle **bounded contextu**.

Naivní kombinace vede k `Features/CreateOrder/Domain/`, což je nesmysl;
doména je sdílená v rámci bounded contextu, ne per use case.

Fungující uspořádání:

| Osa | Rozsah | Co v ní je |
|---|---|---|
| Modul | bounded context | hexagon jako celek |
| Hexagon | uvnitř modulu | doména (střed), porty (hranice), adaptéry (venku) |
| Slice | uvnitř aplikační vrstvy | jeden use case |

Doména je **horizontální a sdílená v rámci modulu**.
Aplikační vrstva je **vertikální**.
Adaptéry jsou **horizontální**; EF mapping a HTTP klienti se přirozeně sdílejí.

---

## Směr závislostí

```
        Host (composition root)
          │  vidí jen registrační extension každého modulu
          ▼
    ┌─────────────────────────────┐
    │  Modul                      │
    │                             │
    │   Infrastructure ──┐        │  adaptéry implementují porty
    │                    ▼        │
    │   Application ── Ports      │  slices závisí na portech
    │        │                    │
    │        ▼                    │
    │     Domain                  │  nezávisí na ničem
    └─────────────────────────────┘
```

Pravidlo: **šipky míří dovnitř.** Doména je střed, nic z ní nevede ven.

Jediná výjimka: Host referencuje Infrastructure, protože musí zavolat
registrační extension. Proto test `Host_does_not_touch_module_internals`
kontroluje, že Host **nesáhne na doménu ani na slices**; reference na
Infrastructure je povolená, hlubší průnik ne.

---

## Public surface

```
Modul nabízí ven:
  Contracts; co umím udělat (DTO + interface)
  Ports; co potřebuji, aby mi někdo dodal
  AddXxxModule; jak mě zaregistrovat

Modul skrývá:
  Domain; entity, value objects, doménové služby
  Features; handlery, commandy, validátory
  Infrastructure; adaptéry, DbContext, HTTP klienti
```

Vynucení je trojité:

1. `internal` na typech; kompilátor, nejde obejít
2. `IDE0040` (explicitní modifikátory); aby se `public` nestalo omylem
3. `PublicSurfaceTests`; chytí, co první dvě propustí

---

## Proč jsou handlery internal

Handler je implementační detail slice. Když je public:

- jiný modul si ho může zavolat přímo, čímž obejde `Contracts`
- vzniká závislost na signatuře, kterou jsi nikdy nesliboval
- refaktoring slice přestane být lokální

Registrace do DI funguje i s internal typy, protože probíhá **uvnitř téže
assembly**. Kde to nefunguje: assembly scanning volaný zvenčí (Scrutor,
MediatR `RegisterServicesFromAssembly` z Hostu). Proto musí registrace
i mapování endpointů žít uvnitř modulu.

---

## Proč slices nesmí volat jiné slices

Slice je jednotka, kterou chceš umět **smazat**. Když slice A volá handler
slice B, vzniká vazba, kterou nikdo neuvidí, dokud se nepokusí B smazat.

Když dvě slices potřebují totéž, jsou tři možnosti, v tomto pořadí:

1. **Duplikovat**; pokud je to pár řádků. Slices *smějí* duplikovat,
   to je jejich smysl. Sdílení je dražší než duplikace.
2. **Posunout do domény**; pokud je to skutečný doménový koncept.
3. **Projít přes Contracts modulu**; pokud jedna slice opravdu spouští
   jiný use case. To je ale signál, že by to možná měl být event.

---

## Proč doména nesmí znát čas

`DateTime.UtcNow` v doméně znamená, že test nemůže ověřit chování na
hranici (vypršení, splatnost, časové okno) bez čekání nebo mockování
statiky. Řešení: čas přichází jako parametr nebo přes `TimeProvider`
injektovaný portem.

Totéž platí pro `Guid.NewGuid()`; identita generovaná uvnitř domény
znamená, že test nemůže předvídat výsledek.

---

## Co kit nehlídá a proč

| Princip | Proč to nejde staticky |
|---|---|
| SRP | "jeden důvod ke změně" je sémantické, ne strukturální |
| OCP | vyžaduje znát, co se v budoucnu bude měnit |
| LSP | behaviorální kontrakt není v typovém systému |
| ISP | "tlustý interface" závisí na tom, kdo ho konzumuje |

Pro SRP kit dodává **proxy signály**, ne verdikt: class coupling (CA1506,
S1200), počet metod (S1448), kognitivní komplexitu (S3776). Když třída
překročí prahy, je to výzva k pohledu, ne důkaz porušení.

DIP je jediný z SOLID, který jde vynutit dobře; právě proto na něj kit
tlačí nejvíc (BannedSymbols, testy směru závislostí).

---

## Kdy je pravidlo špatně, ne kód

Signály, že pravidlo potřebuje úpravu, ne obcházení:

- **Výjimka se opakuje** ve třech a víc případech se stejným důvodem →
  pravidlo je formulované moc široce
- **Oprava zhoršuje čitelnost** → pravidlo řeší něco, co v tvém kontextu
  problém není
- **Nikdo neumí vysvětlit proč** → pravidlo přišlo z cargo cultu, smaž ho

Naopak signály, že je špatně kód:

- oprava je mechanická a zjevná
- po opravě je kód kratší
- pravidlo tě donutilo pojmenovat něco, co dosud nemělo jméno
