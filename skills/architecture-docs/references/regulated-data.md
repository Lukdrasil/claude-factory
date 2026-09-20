---
written_against: "web research 2026-08"
---

`written_against` names the regulatory state this rubric was checked against — PCI-DSS SAQ tiers
and storage rules, and HIPAA's BAA and retention expectations. A standards page or a cloud
provider's BAA scope list that contradicts it means this file is stale and needs re-checking, not
that the solution drifted.

# Regulated data — PCI-DSS and HIPAA as architectural constraints

The question: does PCI-DSS or HIPAA apply, and how does it reshape the architecture — scope,
vendors, logging, and crypto? Load this before choosing a payment integration, cloud services, or a
logging pipeline: these regimes constrain those choices upfront rather than validating them
afterwards. `security.md` names the regulated data class as the row that narrows every other option
in it; this file says how. The redaction the regimes demand is built in `logging-and-audit.md`; the
key storage and rotation machinery is `operations.md`; which stores hold the regulated rows at all
is `data.md`.

PCI's dominant architectural lever is scope minimisation via tokenization. If card data never
reaches your servers — Stripe Elements, hosted fields, or SDK tokenization at the point of entry —
you qualify for SAQ-A, which is days of effort, instead of SAQ-D, which means full-standard
compliance over every in-scope system and weeks to months of dedicated work. Tokenization platforms
satisfy roughly 90% of the required controls for you.

If you must be in scope, four things follow. Network segmentation isolates the cardholder-data
environment so the rest of the estate falls out of scope. The PAN must never appear readable in
logs, traces, caches or exception payloads — the permitted at-rest renderings are truncation, index
tokens, keyed hashing, or strong encryption, and display masking alone does not count. Strong TLS in
transit is mandatory. And keys must be rotated at the end of a defined cryptoperiod, NIST-guided,
with full lifecycle management.

HIPAA reshapes vendor choice instead. Every cloud service touching PHI needs a signed BAA, and
services not explicitly covered by the provider's BAA are unusable for PHI — which constrains which
managed services you may adopt at all. PHI needs AES-256 at rest and TLS 1.2+ in transit with
managed, rotated keys. Every PHI access — auth events, authorization changes, data reads, admin
actions — must be audit-logged. Compliance documentation carries a six-year retention floor, with
audit logs commonly aligned to the same six years.

The net effect on decisions: tokenize rather than hold regulated data; pick BAA-covered or
PCI-validated services only; build redaction into the logging pipeline before the first log line
ships; and treat key rotation and audit trails as launch requirements, not a hardening backlog.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| Card payments needed, no card-data business requirement | tokenize at the edge (Stripe/Adyen hosted fields or SDK); never let PAN touch your servers; target SAQ-A |
| Business genuinely requires touching PAN | accept SAQ-D or a full assessment: a segmented CDE network, PAN-unreadable storage, cryptoperiod-based key rotation, Req-10 logging |
| PHI stored or processed | BAA-covered services only; AES-256 at rest plus TLS 1.2+ in transit; a PHI-access audit log; six-year documentation retention |
| Central log aggregation planned under either regime | redaction and scrubbing at the log-shipper layer — PAN or PHI in Sentry or Datadog payloads is a reportable failure |

## Full outsourcing / tokenization (SAQ-A path)

- **Use when** the default for anyone taking payments who is not a payments company.
- **Pros** card data is out of scope, so the assessment shrinks from weeks to days, and the provider
  carries roughly 90% of the PCI controls.
- **Cons** you are dependent on the provider's UI components and SDKs, and you pay a per-transaction
  cost.
- **Typical mistakes** posting card numbers through your own backend "just to forward them", which
  puts you instantly in scope; logging full card details from webhook or debug payloads.

## In-scope CDE with segmentation

- **Use when** PAN handling is the product itself.
- **Pros** full control over the payment flow.
- **Cons** the SAQ-D or ROC burden, segmentation audits, key ceremonies and dedicated staffing.
- **Typical mistakes** a flat network that puts the whole estate in scope; relying on display
  masking as at-rest protection.

## HIPAA on BAA-covered cloud

- **Use when** any PHI workload on AWS, Azure or GCP.
- **Pros** the major clouds sign BAAs covering many managed services.
- **Cons** only explicitly BAA-covered services are usable, and shared-responsibility gaps are
  yours; the audit-log and retention plumbing is your job at the application layer.
- **Typical mistakes** using a non-BAA-covered service, or a SaaS vendor who will not sign, for PHI;
  no audit trail of who read which record.

## What holds whatever you pick

- Tokenize versus in-scope is the biggest cost decision in the whole architecture — decide it first.
- BAA-covered services only for PHI: the BAA constrains the service catalogue.
- Redact PAN and PHI in the logging pipeline itself, not through app-code discipline.
- Key rotation on a defined cryptoperiod, and PHI-access audit logs, are launch requirements.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the outsourced tokenization path for cards
— hosted fields or SDK tokenization at the point of entry, no PAN through your backend, SAQ-A as
the target — and, for PHI, a service catalogue restricted to what the provider's BAA explicitly
covers, with AES-256 at rest, TLS 1.2+ in transit, a PHI-access audit log and redaction wired into
the log shipper before the first log line ships. Name the trigger that would force the in-scope
path — a business requirement that genuinely needs the PAN, a vendor that will not sign a BAA — as
a row in `07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `QS-` and `C-` ids: whether either regime
   applies at all, and if so whether the business truly needs to touch the regulated value or only
   a token standing for it.
2. State the recurring cost of each — the per-transaction fee against the assessment burden, the
   segmentation audits, the key ceremonies, the six-year retention storage — and what moving into
   scope later costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected options as alternatives with
   the reason each lost, and reference it from `03-containers.md` beside the boundary of the
   cardholder-data environment or the PHI store.
4. The regime's "must" facts become `C-` rows: BAA-covered services only, PAN unreadable at rest,
   TLS 1.2+, the cryptoperiod, the six-year retention floor. Measurable outcomes become `QS-` rows —
   key rotation interval, audit-log retention, time to produce a PHI-access trail. Any regulated
   value reachable in a log, trace, cache or exception payload is an `R-` row in `07-risks.md` with
   an owner. Anything the human leaves open is a `TODO(question)` per `templates.md`.
