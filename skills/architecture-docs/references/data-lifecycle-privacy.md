---
written_against: "web research 2026-08"
---

`written_against` names the regulatory and enforcement state this rubric was checked against — the
GDPR articles cited, the Deutsche Wohnen fine, and the EDPB's 2025 coordinated action. A regulator
publication that contradicts it means this file is stale and needs re-research, not that the
solution drifted.

# Data lifecycle and privacy — how long each copy lives, how it dies, and how you prove it

Load this when the system stores personal data, when compliance includes GDPR, residency or audit
obligations, when a cache, index, OLAP store or log pipeline that receives user data is being added,
or when an erasure or export request could plausibly arrive. `data.md` decides which secondary
stores exist and who writes them; every store it adds is another place this file has to reach.
`operations.md` owns backup and restore mechanics, `logging-and-audit.md` owns what enters the logs
in the first place, and `security.md` owns the trust boundaries around the data.

Outputs land in `03-containers.md` (each store's retention and erasure answer alongside its writing
owner), in `06-deployment.md` (the TTL jobs, the backup cycle, the keystore if crypto-shredding is
chosen), and in an ADR per `templates.md`.

Data lifecycle is decided per data class, not per database. The unit of work is the data map: what
personal data exists, where every copy lives, how long each copy may live, and by which mechanism it
dies — hard delete, anonymize, or crypto-shred.

GDPR Art. 5(1)(e) storage limitation is a standing obligation. Data must be deleted or anonymized
when its purpose ends, whether or not anyone asks; Deutsche Wohnen was fined roughly EUR 14.5M
largely for an archive that could not delete. Art. 17 erasure applies to all copies, including the
ones teams forget: search indexes, Redis, OLAP replicas, log aggregators, backups. Regulators accept
"beyond use" for backups — excluded from restore, expiring on the backup cycle — but the EDPB's 2025
coordinated enforcement, covering 32 DPAs and 764 controllers, found that most controllers had no
backup-erasure procedure at all, and that is now an enforcement focus.

The safe default is a data classification table (class → stores → retention → deletion mechanism →
lawful basis), TTL jobs per store, and one documented erasure procedure that names every secondary
store. Crypto-shredding — a key per subject, destroyed on erasure — is the only mechanism that
reaches immutable stores and backups without rewriting them. It is real engineering, and it is void
if any copy was ever stored unencrypted.

## Choosing by driver

| Signal in the repo or the interview | Where it leads |
|---|---|
| GDPR applies | retention and erasure are legally mandatory (Art. 5(1)(e), 17, and 30(1)(f) in the ROPA) |
| Each cache, index, OLAP copy and log pipeline added | another place erasure must reach — the data map grows multiplicatively |
| Expiring dumps on a 30–90 day cycle | PII ages out naturally; long-retention PITR and DR archives need crypto-shred or a documented exclusion-from-restore |
| PII kept out of logs at the source | logs leave erasure scope entirely; retrofitting redaction into a log lake is miserable |
| Aggregate or anonymized analytics | escapes GDPR, since anonymous data is out of scope; row-level user analytics drags the OLAP store into every erasure request |
| Append-only or event-sourced storage | crypto-shredding is the only viable erasure mechanism, designed in from day one |
| A steady volume of erasure requests | automation with per-store verification; one request a year can be a manual runbook |

## Nothing recorded

- **Use when** only defensible with genuinely no personal data — and IPs and user agents in logs
  usually break the claim.
- **Pros** zero effort, and an honest description of most early prototypes.
- **Cons** under GDPR this is a standing violation before any request arrives, because storage
  limitation is an obligation rather than a request-response. The first erasure request is
  unanswerable: you cannot delete what you cannot enumerate. PII accretes in logs and backups
  indefinitely.
- **Typical mistakes** assuming "we are B2B" means no personal data — contact persons, logins and
  audit trails are all personal data.

## Retention policy only

- **Use when** pre-GDPR-exposure systems, or as the first increment: a written retention schedule per
  data class, with TTL and cleanup jobs on the primary store.
- **Pros** satisfies storage limitation for the primary store and kills the worst rot — logs at 30–90
  days, stale accounts; the schedule doubles as the ROPA Art. 30(1)(f) entry.
- **Cons** it handles time-based death, not request-based death, so an Art. 17 request still has no
  procedure; and TTLs on the primary do nothing for the search index or the log lake.
- **Typical mistakes** a policy on paper with no jobs behind it, which documents what you knowingly
  fail to do.

## Retention plus erasure procedure

- **Use when** the safe default for any GDPR-exposed system: a retention schedule, TTL jobs, and a
  documented, tested per-subject erasure runbook naming every store — primary delete, cache
  invalidation, index delete-by-id, OLAP delete or anonymize, a log strategy, and a backup
  beyond-use statement. Export is handled by the same store list.
- **Pros** one month to respond to a request, and the runbook makes it answerable; the store checklist
  forces the data map to exist implicitly; the backup posture is documented rather than improvised
  per request.
- **Cons** manual runbooks decay, so every new store added without updating the runbook reopens the
  gap; and erasure is only as complete as the last person who ran it, with no automated verification.
- **Typical mistakes** erasure that runs on the DB only while the search index is never told, leaving
  the deleted user findable by search; soft-delete flags that never become hard deletes.

## Full data map with automation

- **Use when** many stores, a steady erasure volume, event-sourced or immutable storage, or a
  regulated sector: a maintained classification table wired to an erasure orchestrator that fans out
  to every registered store with per-store verification, crypto-shredding for immutable stores, and
  PII redaction at the logging source.
- **Pros** erasure is provable rather than asserted, which is what audits and the EDPB's enforcement
  focus ask for; crypto-shred reaches backups and event stores without rewriting them; it scales with
  store count instead of runbook length.
- **Cons** real engineering, particularly key-per-subject management — lose the keystore and you lose
  everything, leak one plaintext copy and the shred is theatre — plus the org discipline to keep the
  registry honest.
- **Typical mistakes** ceremony for a three-store startup, where a tested runbook covers the same
  legal ground until volume grows.

## How erasure reaches each store type

| Store type | How erasure reaches it | Typical gap |
|---|---|---|
| Primary DB | hard DELETE or anonymize-in-place per subject id | soft-delete flags never hardened; FK-orphaned rows in side tables |
| Replica | replication propagates the delete | detached replicas repurposed as reporting DBs quietly leave the stream |
| Cache (Redis, in-proc) | TTL bounds exposure; explicit invalidation for long-lived keys | long-TTL or no-TTL keys (sessions, profile blobs) outlive the primary delete |
| Search index | delete-by-document-id in the erasure procedure | the classic gap: DB deleted, index never told — the user stays findable |
| OLAP/warehouse | scheduled delete or anonymize by subject id, or ingest only pseudonymized data | ELT lands raw PII; warehouse deletes get deferred indefinitely; materialized views retain what the base deleted |
| Logs | prevention: redact at source; 30–90 day retention so entries age out | free-text lines carry emails and IPs; retention set to forever for debugging |
| Backups | "beyond use": excluded from selective restore, expiring with the cycle, re-erasure on restore documented; crypto-shred for long archives | backups held for years with no expiry; a restore silently resurrects erased subjects |

## What holds whatever you pick

- Storage limitation is a standing obligation: data dies when its purpose ends, request or no
  request. Deutsche Wohnen, roughly EUR 14.5M, for an archive that could not delete.
- Erasure applies to all copies. If the search index, cache, warehouse or log lake is not in the
  procedure, the procedure is incomplete — the EDPB's 2025 action found exactly this gap across
  hundreds of controllers.
- For backups, "beyond use" is the accepted posture: excluded from restore, expiring with the cycle,
  documented. A restore must re-apply erasures or it resurrects deleted people.
- Keep PII out of logs at the source. What never enters the log lake never needs erasing from it.
- Crypto-shredding is the only erasure that reaches immutable stores and old backups without
  rewriting them, and it is void if any copy was ever unencrypted or the key was duplicated.
- Truly anonymized data is outside GDPR; pseudonymized, re-linkable data is still personal data.
- Every new store must answer "how does erasure reach you, and what is your retention" before it
  ships. The review question costs nothing and is the whole game.

## When the evidence is thin

If nothing recorded distinguishes the options, recommend the retention-plus-erasure-procedure level:
a retention schedule per data class, TTL jobs on the primary, and one tested runbook that names
every store the system actually has. Name the trigger that would push it to automation — an
immutable or event-sourced store, a steady request volume, a regulated sector — as a row in
`07-risks.md`.

## Recording the choice

1. Put the options to the human against the affected `C-` ids: the data classes, the stores each one
   reaches, the retention per copy, and the deletion mechanism per copy.
2. State the recurring cost of each — the TTL jobs someone maintains, the runbook someone reruns,
   the keystore someone must never lose — and what an unanswerable erasure request costs.
3. Write the accepted choice as an ADR under `docs/adr/`, the rejected ones as alternatives with the
   reason each lost, and reference it from `03-containers.md` and `06-deployment.md`.
4. A store missing from the erasure procedure, a backup set with no expiry, and PII in a log lake
   with forever retention are rows in `07-risks.md`, each with an owner. Anything the human leaves
   open is a `TODO(question)` per `templates.md`.
