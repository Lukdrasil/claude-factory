---
written_against: "web research 2026-08"
---

`written_against` names the regulatory and specification state this rubric was checked against —
the European Accessibility Act's application date and exemptions, EN 301 549 v3.2.1 as the current
cited version with v4.1.1 expected, and the WCAG version each incorporates. An official source that
contradicts it means this file is stale and needs re-research, not that the solution drifted.

# Accessibility — the standard targeted and how it is enforced

Load this when the frontend is public-facing, when the product sells to or serves EU consumers —
e-commerce, consumer banking, transport ticketing, telecom, e-books, the European Accessibility Act
scope — or when choosing frontend architecture and component libraries, where accessibility
capability is a selection criterion. The question is what standard the product targets and how it
is enforced: component-level discipline with automation in CI, or nothing until an audit.
`frontend-delivery.md` decides the rendering model this file then prices; `stacks/react.md` owns
the component-library decision that carries most of the cost; `testing.md` owns where automated
checks sit in the wider test strategy.

Outputs land in `02-constraints.md` (the target standard as a regulatory constraint), in
`04-quality-scenarios.md` (a measurable scenario — a keyboard-only path through the primary flow),
and in an ADR per `templates.md`.

The European Accessibility Act, Directive (EU) 2019/882, applies since 28 June 2025 to
consumer-facing digital services in the EU — e-commerce, consumer banking, transport ticketing,
telecom, e-books — including non-EU companies selling into the EU. Microenterprise service
providers are exempt, and pre-existing service contracts have a transition period until 2030. The
technical reference is EN 301 549, currently v3.2.1, incorporating WCAG 2.1 AA; v4.1.1
incorporating WCAG 2.2 AA is expected to be cited in the Official Journal around late 2026, so
target WCAG 2.2 AA now. An accessibility statement describing conformance is part of the
obligation.

Architecture affects the cost of conformance. Server-rendered pages degrade more gracefully and get
semantics for free; SPAs take on focus management, route-change announcements via live regions, and
client-rendered semantics as ongoing engineering work. The cheapest lever is component-level:
accessible primitives — Radix UI, React Aria, or a design system with accessibility built in —
instead of hand-rolled dropdowns, modals and comboboxes, plus contrast checked at the moment design
tokens are defined. Automated testing with axe-core in CI, via jest-axe or Playwright, is a floor
and not a ceiling: it catches roughly 30–40% of issues by success-criteria coverage. Keyboard flows,
screen-reader behaviour and meaningful alt text need manual testing and a periodic expert audit.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| A consumer-facing service touching the EU market | the EAA applies since 28 June 2025 — a WCAG 2.2 AA programme with an accessibility statement |
| SPA with client-side routing | focus management and route-change announcements become the team's explicit job; SSR and server pages inherit browser semantics |
| Component library choice still pending | accessible primitives (Radix / React Aria class) — never hand-rolled dropdowns, modals or comboboxes |
| Automated tooling only | axe-core in CI catches roughly 30–40% of issue types — a floor, not conformance |
| Procurement or public-sector contracts | EN 301 549 conformance and a published accessibility statement |

## No accessibility posture recorded

- **Use when** defensible only for short-lived internal tools with a known, small user population.
  Never acceptable for EAA-scope services.
- **Pros** no upfront cost or process.
- **Cons** EAA non-compliance risk for EU consumer services since 28 June 2025, exposing you to
  member-state penalties and market-withdrawal orders; retrofit cost is far higher than building on
  accessible primitives; inaccessible custom widgets accumulate as debt in every feature.
- **Typical mistakes** treating accessibility as a one-time audit before launch instead of
  component-level discipline; discovering EAA applicability from a customer's legal team or a
  procurement questionnaire.

## Automated floor: axe-core in CI plus accessible primitives

- **Use when** any public-facing frontend needs a pragmatic baseline: axe-core in CI (jest-axe,
  `@axe-core/playwright`, Lighthouse), an accessible component library for all interactive widgets,
  and contrast verified at the design-token level.
- **Pros** catches the regression classes automation can see — missing labels and alt text, ARIA
  misuse, contrast — on every PR; accessible primitives eliminate the worst offenders (custom
  dropdowns, modals, comboboxes) at the source; low ongoing cost once wired, with contrast decided
  once at the token level.
- **Cons** automation cannot judge focus order, keyboard traps, screen-reader comprehension or
  alt-text quality, so a green axe run is not conformance; there is no accessibility statement or
  documented conformance claim, which EAA-scope services need; SPA-specific issues such as
  route-change announcements and focus restoration are mostly invisible to axe.
- **Typical mistakes** treating a passing axe run as "WCAG compliant", when it is a ~30–40% floor and
  not a conformance claim; building custom dropdowns and modals instead of using the accessible
  primitives already in the stack; choosing brand contrast tokens without checking WCAG ratios
  (4.5:1 for normal text, 3:1 for large text and UI components).

## WCAG 2.2 AA programme (EN 301 549 alignment for EAA scope)

- **Use when** it is required — EAA-scope consumer services in the EU, and public-sector or
  procurement contexts citing EN 301 549. Everything in the automated floor, plus manual keyboard
  and screen-reader testing, a periodic expert audit, a published accessibility statement, and
  accessibility acceptance criteria in the definition of done.
- **Pros** meets the EAA's technical expectation and is forward-compatible with EN 301 549 v4.1.1
  (WCAG 2.2 AA); manual audits catch the ~60–70% of issue types automation misses — focus
  management, reading order, error-recovery flows; the accessibility statement and audit trail are
  ready for enforcement queries and procurement.
- **Cons** a real recurring cost in expert audits, assistive-technology testing and training; it
  slows delivery if bolted on as a gate instead of built into components and the definition of
  done; WCAG 2.2 adds six new AA criteria over 2.1 — focus appearance and obscuring, dragging
  alternatives, target size 24×24, accessible authentication, and redundant entry.
- **Typical mistakes** auditing once and letting conformance rot, since every release without
  accessibility checks erodes the audited state; writing the accessibility statement without
  testing behind it, where a false conformance claim is itself an enforcement risk; certifying
  against WCAG 2.1 in 2026 without planning the WCAG 2.2 AA transition.

## What holds whatever you pick

- The EAA (Directive (EU) 2019/882) applies since 28 June 2025 to EU consumer digital services; the
  scope check belongs in system design, not in a legal review at launch.
- Target WCAG 2.2 AA now — EN 301 549 v4.1.1 adopting it is expected in the Official Journal around
  2026.
- Use accessible primitives (Radix / React Aria class) for every interactive widget; never hand-roll
  dropdowns, modals or comboboxes.
- axe-core in CI is the floor, at roughly 30–40% of issues; keyboard and screen-reader testing plus
  a periodic manual audit are what conformance actually rests on.
- Check contrast ratios when design tokens are defined, not per screen after the fact.
- SPAs must own focus management and route-change announcements explicitly; SSR and server-rendered
  pages inherit most of this from the browser.

## When the evidence is thin

If nothing recorded distinguishes the options, first settle the scope question — whether the
product serves EU consumers in an EAA category — because it decides between the two live options
rather than being a matter of taste. Absent that answer, recommend the automated floor: accessible
primitives for every interactive widget, axe-core in CI, and contrast checked at the token level,
which is the cheap part of either destination. Name the trigger that would escalate to the full
programme — a first EU consumer customer, a procurement questionnaire citing EN 301 549, a
public-sector contract — as a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human with the affected `QS-` and `C-` ids: the target standard, whether
   EAA scope applies, and what enforcement looks like in CI and in the definition of done.
2. State for each what it costs recurrently — expert audits, assistive-technology testing, training
   — and what non-conformance costs if the product is in EAA scope.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, record the target standard as a constraint in `02-constraints.md`, and add
   a measurable scenario to `04-quality-scenarios.md`.
4. An unanswered EAA scope question, an accessibility statement with no testing behind it, an audit
   with no repeat cadence, and hand-rolled interactive widgets are rows in `07-risks.md`. Anything
   the human leaves open is a `TODO(question)` per `templates.md`.
