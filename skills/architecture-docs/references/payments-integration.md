---
written_against: "web research 2026-08"
---

`written_against` names the standard and pricing state this rubric was checked against — PCI DSS
v4.0 and 4.0.1's questionnaire boundaries, the PSD2/PSD3 timeline, and the headline rates of
Stripe, Adyen and the merchant-of-record class. A card brand's or provider's own page that
contradicts it means this file is stale and needs re-research, not that the solution drifted.

# Payments — integration depth, PSP, and the correctness mechanics

Load this when the payments step is anything other than none, or the system charges customers,
holds a ledger, or handles subscriptions. `security.md` owns the trust boundary; `regulated-data.md`
owns the regulated data the choice below either admits or keeps out; `communication.md` owns the
webhook edge's contract; `message-bus.md` owns the queue the webhook handler and the reconciliation
job run on; `data.md` owns the ledger store.

Outputs land in `01-context.md` (the PSP as an external system), in `02-constraints.md` (the
questionnaire the chosen depth commits you to, and any tax or residency obligation), in
`03-containers.md` (the webhook receiver and the ledger), and in an ADR per `templates.md`. Every
choice below reaches the human as options with consequences plus your recommendation, per
`approaches.md`.

Payments integration is chosen on two axes: how close card data (the PAN) gets to your servers,
and how much of billing you build yourself.

Hosted checkout — Stripe Checkout, payment links, Adyen Hosted Checkout — keeps the payment page
entirely on the provider's domain and yields the smallest PCI scope, SAQ A. PCI DSS v4.0,
mandatory since April 2025, nonetheless added requirements 6.4.3 (payment-page script management)
and 11.6.1 (page-tampering detection) even for SAQ A merchants. Embedded tokenized fields — Stripe
Elements, Adyen Web Components, Braintree Hosted Fields — render iframes on your page that send
card data straight to the provider; classification is SAQ A while the fields are provider-hosted
iframes, but slides to SAQ A-EP the moment your page's code can affect the payment flow, and under
PCI DSS 4.0.1 SAQ A-EP has moved much closer to SAQ D in effort. Direct API integration, where the
PAN transits or rests on your servers, puts you in SAQ D — hundreds of controls, annual
assessment, network segmentation — and is only defensible when payments *is* the product.

Merchant of record inverts the model: the MoR is the legal seller, registers and remits VAT, GST
and US sales tax across 200-plus jurisdictions and absorbs disputes, in exchange for roughly 5%
plus $0.50 per transaction, 7-14 day payouts, and loss of control over checkout and the
customer-of-record relationship.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Payments are incidental to the product, the smallest possible PCI scope is wanted, small team | hosted checkout (Stripe Checkout / payment links) — SAQ A |
| Checkout must live inside your UI and brand; conversion tuning on the payment form | embedded tokenized fields (Stripe Elements, Adyen Components) — SAQ A or SAQ A-EP |
| Payments *is* the product: PSP, card vault, payment orchestration across acquirers | direct API with the PAN on your servers — SAQ D, dedicated compliance team |
| Global SaaS sales and no appetite for VAT/GST registration in dozens of jurisdictions | merchant of record (Paddle, Lemon Squeezy, Polar) |
| Above roughly $5-10M/year volume across markets | Adyen on interchange++ — authorization-rate optimization worth weeks of onboarding |
| Selling into the EEA or UK | 3-D Secure 2 via the PSP's SCA engine; exemptions (low-value, TRA, merchant-initiated) delegated to the provider |
| Recurring revenue with plan changes, trials, proration | Stripe Billing or an MoR — never hand-rolled proration |
| Any payment flow at all | idempotency keys on creation, webhook-driven state, integer minor units, an append-only ledger, daily reconciliation against PSP settlement reports |

## None needed

- **Use when** the system never charges anyone — internal tools, free products, or billing handled
  entirely by another system.
- **Pros** no PCI scope, no PSP contract, no webhook infrastructure.
- **Cons** revisit the moment a charge, donation or paid tier appears; retrofitting payments
  touches order flow, jobs and compliance at once.
- **Typical mistakes** sneaking in a one-off "just take card details over a form" flow later
  without re-running this decision.

## Hosted checkout

- **Use when** the default for almost everyone: redirect to Stripe Checkout, payment links or Adyen
  Hosted Checkout. Card data never touches your page or servers, and the questionnaire is SAQ A,
  the minimal one.
- **Pros** the smallest PCI scope (SAQ A), with the provider maintaining the payment page, the SCA
  and 3DS2 challenges, local payment methods and wallet buttons; the fastest to ship — a
  session-create call and two webhooks; provider-side conversion optimization and fraud tooling for
  free.
- **Cons** checkout lives on the provider's domain, so branding and layout control are limited; the
  redirect breaks single-page flows, and upsells and multi-step carts are harder; PCI DSS v4.0
  still requires script management (6.4.3) and tamper detection (11.6.1) on the page that links to
  checkout.
- **Typical mistakes** fulfilling on the success-redirect URL instead of the
  `payment_intent.succeeded` / `checkout.session.completed` webhook — the customer can close the
  tab, and the redirect can be forged; creating a new Checkout session per retry click without an
  idempotency key, producing duplicate sessions and double charges; treating SAQ A as "nothing to
  do" and skipping the v4.0 script-integrity requirements.

## Embedded tokenized fields

- **Use when** checkout must be native to your UI: Stripe Elements or the Payment Element, Adyen
  Web Components, Braintree Hosted Fields render provider iframes in your page, and card data flows
  straight to the PSP.
- **Pros** full visual control of checkout inside your brand and flow; card data still bypasses
  your servers, so you handle only tokens (PaymentMethod ids); the same webhook and idempotency
  machinery as hosted checkout, and the Payment Element auto-negotiates SCA and local methods.
- **Cons** PCI scope is SAQ A only while the fields stay provider-hosted iframes — custom JS around
  the payment flow tips you into SAQ A-EP, which PCI DSS 4.0.1 pushed close to SAQ D effort, so
  confirm the classification with a QSA; your page is now attack surface, since a compromised
  script (Magecart-style) can skim the form, which is why requirements 6.4.3 and 11.6.1 bite harder
  here; and you own the checkout UX bugs, loading states and error mapping the hosted page would
  have handled.
- **Typical mistakes** adding an unpinned third-party script to the checkout page and silently
  expanding PCI scope; reading card fields via custom JS "just for validation", which alone
  reclassifies the integration; confirming payment client-side and marking the order paid before
  the webhook arrives.

## Direct API (PAN on your servers)

- **Use when** payments *is* the product — you are a PSP, gateway, card vault or multi-acquirer
  orchestrator. A PAN transiting or resting on your infrastructure means SAQ D: the full PCI DSS
  control set, annual assessment, network segmentation, key management.
- **Pros** total control — routing across acquirers, network tokens, custom retry and cascading
  logic; no provider iframe constraints, and you can serve clients who mandate direct card
  submission.
- **Cons** SAQ D is a compliance program, not a form: hundreds of controls, quarterly ASV scans,
  pen tests, segmentation, dedicated staff. A breach here is existential — fines, forensic audits,
  card-brand delisting. And every PSP feature (SCA, local methods, vaulting) becomes your roadmap.
- **Typical mistakes** drifting into SAQ D accidentally, by proxying card JSON through your API
  "temporarily" to work around a frontend limitation; logging request bodies that contain PANs,
  since a PAN in logs is a findable, reportable breach; building this without a dedicated security
  or ops function.

## Merchant of record (Paddle / Lemon Squeezy class)

- **Use when** global software or SaaS sales where tax is the dominant pain: the MoR is the legal
  seller, registering, collecting and remitting VAT, GST and sales tax in 200-plus jurisdictions
  and absorbing dispute handling, for roughly 5% plus $0.50 all-in.
- **Pros** zero tax registrations and filings on you, with the MoR carrying seller-of-record
  liability; chargebacks, fraud and SCA are the MoR's problem; subscription billing, invoicing and
  license keys are typically bundled.
- **Cons** they are the seller, so your customer's card statement, invoices and refund relationship
  name the MoR; the take rate is higher than PSP plus tax tooling once volume grows, and payouts
  run 7-14 days behind; checkout flexibility is limited, and migrating subscriptions off an MoR
  later is painful because vaulted cards belong to their merchant account; and onboarding and
  product-type restrictions apply, since MoRs curate what they will sell.
- **Typical mistakes** choosing an MoR purely on fee comparison without pricing your own
  tax-compliance cost honestly; assuming you can export vaulted cards and active subscriptions
  cleanly when leaving; bringing physical goods or a marketplace, which most software MoRs will not
  onboard.

## PSP choice within a depth

Stripe wins developer experience and time-to-live at 2.9% plus $0.30. Adyen wins at enterprise
volume — interchange++ pricing and 250-plus local payment methods — but onboarding takes weeks.
Braintree is the pick when native PayPal and Venmo drive revenue. The depth decision above is the
architectural one; the PSP is the commercial one inside it, and both belong in the same ADR.

## Strong Customer Authentication

In the EEA and UK, PSD2's Strong Customer Authentication makes 3-D Secure 2 mandatory unless an
exemption applies. Use the PSP's built-in SCA engine rather than hand-rolling 3DS, and delegate the
exemptions — low-value, transaction risk analysis, merchant-initiated — to the provider. PSD3 and
the PSR reached provisional agreement in November 2025, so treat the regime as moving and record
which provider carries the change.

## Correctness mechanics

These are non-negotiable regardless of depth.

Every payment-creating POST carries an idempotency key derived from your order id, so a network
retry cannot double-charge. Payment state transitions are driven by verified webhooks —
`payment_intent.succeeded`, `charge.refunded`, `charge.dispute.created`; the browser redirect is a
UX hint, never fulfillment authority. Webhook handlers verify the signature, are idempotent on
event id, tolerate out-of-order delivery, and re-fetch high-value objects from the API.

Money is stored as integer minor units — never float — in an append-only ledger where corrections
are compensating entries. Daily reconciliation matches the PSP's settlement reports against
internal orders.

Subscription billing is a buy-first decision: Stripe Billing or an MoR handles proration, trials
and dunning, and building proration by hand is a classic sinkhole. Keep test-mode and live-mode
keys in separate configs, and never log full webhook payloads.

## What holds whatever you pick

- An idempotency key on every payment-creating POST, derived from your order or cart id — a network
  retry must never double-charge.
- Fulfil on the signature-verified webhook, never the redirect return URL; handlers idempotent on
  event id and tolerant of out-of-order delivery.
- Money is integer minor units (or DECIMAL) in an append-only ledger — corrections are compensating
  entries, never updates.
- Reconcile daily against the PSP's settlement and payout reports, and flag orphans on both sides.
- Refunds are negative ledger entries referencing the original charge; disputes pause fulfillment
  and carry an evidence deadline.
- Buy subscription billing (Stripe Billing or an MoR) — hand-rolled proration and dunning is a
  classic sinkhole.
- Separate test-mode and live-mode keys per environment, and never log full webhook payloads.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend hosted checkout on a single PSP with
fulfillment driven by signature-verified webhooks, an idempotency key per order, and an
append-only ledger in integer minor units. Name the trigger that would change it — a conversion
requirement that forces checkout into your own UI, a tax footprint that makes an MoR cheaper than
registrations, a volume level where interchange++ pays for the onboarding — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: the integration depth, the
   PCI questionnaire it commits you to, the PSP, and who is the legal seller.
2. State the recurring cost of each — the per-transaction rate, the MoR take rate against your own
   tax-compliance cost, the assessment burden a deeper integration obliges — and what reversing it
   later costs, including whether vaulted cards and live subscriptions can leave.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with
   the reason each lost, and reference it from `01-context.md`, `02-constraints.md` and
   `03-containers.md`.
4. The measurable outcomes become rows in `04-quality-scenarios.md` with a number and a unit: the
   reconciliation cadence, the dispute-evidence deadline, the webhook retry budget, and the payout
   lag the business must fund.
5. A questionnaire classification nobody has confirmed with a QSA, a reconciliation job with no
   owner, and an unpinned third-party script on the checkout page are rows in `07-risks.md`.
   Anything the human leaves open is a `TODO(question)` per `templates.md`.
