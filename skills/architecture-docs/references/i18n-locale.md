---
written_against: "web research 2026-08"
---

`written_against` names the standards and product state this rubric was checked against — the IANA
tz database, ISO 4217 minor units, Postgres' ICU collation provider, and Stripe's money model. A
specification page that contradicts it means this file is stale and needs re-research, not that the
solution drifted.

# Internationalisation and locale — time, money, translated content, collation

Load this for any system with users in more than one country or timezone, with user-facing dates or
money amounts, with translatable content, or with a stated plan to expand internationally. Decide
before the first schema is frozen: retrofitting i18n costs two to five times more than building it
in. `data.md` owns the stores that hold copies of this data and `stacks/dotnet.md`, `stacks/react.md`
or `stacks/python.md` own the formatting libraries in the chosen stack.

Outputs land in `03-containers.md` (the schema decisions that follow from the storage shape), in
`02-constraints.md` when a residency or locale requirement is imposed rather than chosen, and in an
ADR per `templates.md`.

Store instants as UTC and render them in the user's IANA named timezone — `Europe/Prague`, never a
numeric offset. Offsets cannot follow DST rule changes, and abbreviations are ambiguous across
regions. There is one documented exception: future events tied to a place, such as a 9am meeting in
New York next year, must store local wall time plus the IANA zone name, because a tz-database rule
change can shift which UTC instant that local time maps to. "UTC everywhere" silently corrupts these.

Money is an integer count of ISO 4217 minor units plus a three-letter currency code — Stripe's model,
where $5 is `500` and `usd`. Never a float, because binary floats cannot represent 0.1 and rounding
drift is a financial liability, and never an amount without a currency code. The minor-unit count
varies per currency (0, 2 or 3 decimals), so formatting needs the code. FX rates and interest are the
only places where fixed-point `DECIMAL` earns its keep.

Translated content splits two ways. A separate translation table keyed `(entity_id, locale)` suits
translations that are queried or searched per language — one `tsvector` per row and a clean composite
index. A `jsonb` `{locale: value}` column suits translations that always load with the entity — fewer
joins and GIN-indexable, though cross-language search then needs specialised indexing.

Sorting and search must use ICU locale-aware collation; byte-order sort is wrong for most languages.

Retrofitting is expensive precisely because locale assumptions leak everywhere: string literals in
controllers, emails, PDFs and CLI output; date and number formatting tied to one locale; layouts
built with no headroom for text expansion or RTL.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Users or data in more than one timezone | UTC storage plus an IANA named zone per user or tenant; `timestamptz` columns; conversion only at the display edge |
| Future scheduled events tied to a physical place | store local wall time plus the IANA zone name (optionally the tzdata version) and derive UTC at read time, not precomputed UTC |
| Money amounts in more than one currency, or any money at all | integer minor units plus the ISO 4217 code in the same row; `DECIMAL` only for FX rates; reject float at code review |
| Translated content queried or full-text-searched per language | a separate translation table keyed `(entity_id, locale)` with a per-row `tsvector` |
| Translations always displayed with the parent entity, few locales | a `jsonb` locale-keyed column with a GIN index; accept weaker cross-language search |
| User-visible sorted lists or search in non-English locales | ICU collations — the Postgres ICU provider, or ICU libraries — instead of C or byte collation |
| "We'll internationalize later" | at minimum externalize strings and use locale-aware format calls now; the two-to-five-times retrofit multiplier is in the string and format sprawl, not the translation files |

## Instants and timezones

### UTC-everywhere + IANA display zone

- **Use when** the default for all recorded instants — `created_at`, and events that happened.
- **Pros** unambiguous and DST-proof for past instants; simple comparison and ordering across regions.
- **Cons** wrong for future local-time events when tz rules change; requires disciplined edge-only
  conversion.
- **Typical mistakes** storing server-local time in the DB; storing numeric offsets (`+02:00`)
  instead of zone names; applying UTC-everywhere to future recurring local events.

## Translated content

### Separate translation table

- **Use when** many locales, per-language search or filtering, and translations edited independently
  of the entity.
- **Pros** clean per-language indexing and full-text search; no schema change per new locale; easy
  "which entities lack locale X" queries.
- **Cons** an extra join on every localized read, and more tables to maintain.
- **Typical mistakes** one column per language (`title_en`, `title_de`), which means a schema
  migration per locale.

### jsonb locale-keyed columns

- **Use when** translations always load with the entity, there are few locales, and there is no
  cross-language search requirement.
- **Pros** no joins and one row per entity; GIN-indexable, and locales are trivial to add.
- **Cons** cross-language full-text search needs specialised indexing, and partial-translation
  validation lives in app code.
- **Typical mistakes** assuming `jsonb` text is searchable like a `tsvector` column without extra
  work.

## Money

### Integer minor units + ISO 4217 code

- **Use when** all stored money — Stripe's model.
- **Pros** exact arithmetic, and currency-correct formatting via ISO 4217 minor-unit metadata.
- **Cons** the currency code must be carried everywhere, and mixing currencies in arithmetic has to
  be a type error.
- **Typical mistakes** currency as a float or double; an amount column with no currency code;
  hardcoding two decimals, when JPY has 0 and BHD has 3.

## What holds whatever you pick

- Never store server-local time. Store UTC for past instants and local-time-plus-IANA-zone for future
  placed events.
- Money is integer minor units plus an ISO 4217 code. Float money is a defect, not a style choice.
- Locale-aware sort and search require ICU collation, not byte order.
- Externalize user-facing strings from day one. The retrofit costs two to five times as much and
  compounds with every feature.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the defaults: `timestamptz` in UTC with an
IANA zone stored per user, money as integer minor units plus an ISO 4217 code, externalized strings
with locale-aware format calls, and ICU collation on any user-visible sort — with translations left
in the entity's own columns until a second locale is actually funded. Name the trigger that would
change it — a second locale, a future placed event, a second currency — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: the instant storage shape,
   the translation storage shape, the money representation, and the collation provider.
2. State what each costs now and what reversing it later costs — a schema and backfill for every
   stored timestamp or amount, and the two-to-five-times multiplier on the string and format sprawl.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `03-containers.md`.
4. Float money columns, timestamps stored without a zone, and layouts with no text-expansion or RTL
   headroom are rows in `07-risks.md`. Anything the human leaves open is a `TODO(question)` per
   `templates.md`.
