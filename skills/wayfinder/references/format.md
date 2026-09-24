# Request map format

The one place the shapes of a request map are written down; the UI reads them from here. Every file below is
written and committed by `bin/map.sh` only, one local commit per call under the state lock, never pushed by it.

| path in the state repo | what |
|---|---|
| `requests/<R-id>/map.md` | the map: the request's status and its index |
| `requests/<R-id>/issues/NN-<slug>.md` | one decision ticket |
| `requests/archive/<YYYY-MM>/<R-id>/` | a map at `Status: done` with its tickets, moved by `state-archive.sh --all` |

`<R-id>` is `R-YYYYMMDD-n` (`map.sh new --next` picks n under the lock, over the live and the archived ids of
that day). `NN` is the ticket number, `[0-9][0-9]*`, written with two digits at least (`01`, `02`, ... `100`);
`1` and `01` name the same ticket on the command line. `<slug>` is the title in lowercase ASCII, every other run
of characters one `-`, at most six words.

## map.md

```markdown
---
request: R-20260925-1
created: 2026-09-25
---

Status: grilling

## Destination

Invoices reach the ledger every night, from ecs and bff alike.

## Notes

Both repos post through the ledger's REST API; the human prefers one job per repo.

## Decisions so far

- [Which ledger API](issues/01-which-ledger-api.md): The REST API, v2.
- [Pick the store](issues/02-pick-the-store.md): Postgres.

## Not yet specified

How the two exports are ordered once both run.

## Out of scope

- [Get ledger access](issues/03-get-ledger-access.md): Access is the other team's rollout, not this request.

## Terms

- **Ledger**: the accounting system of record. Avoid: books
```

- The frontmatter holds `request:` and `created:`. `Status:` is the first line under it that starts with
  `Status:`, one of `charting`, `grilling`, `planned`, `queued`, `running`, `done`.
- The six sections always exist, in this order. A section is its `## ` heading, a blank line, its body and a
  blank line; an empty section is the heading and one blank line.
- `## Decisions so far` has one line per resolved ticket, in the order they were resolved:
  `- [<title>](issues/<file>): <gist>`, the gist being the first line of the ticket's answer. Only
  `map.sh resolve` writes it.
- `## Out of scope` has one line per dropped ticket, `- [<title>](issues/<file>): <why>`, written by
  `map.sh drop`, plus any boundary the charting session drew without a ticket (`map.sh set <R-id> out-of-scope`).
- `## Not yet specified` is free text, the fog. The map is clear only when it is empty.
- `## Destination`, `## Notes`, `## Terms` are free text (`map.sh set`); `## Terms` has the grill's shape,
  `- **<term>**: <definition>. Avoid: <words>`.

## issues/NN-slug.md

```markdown
# Pick the store

Type: grilling
Status: resolved
Blocked by: 01
Repo: all
Claimed by: chart_ecs-12

## Question

Where the export keeps its cursor: Postgres or the ledger's file store?

## Answer

Postgres.
The export already talks to the ecs database; the file store would be a second credential.
```

- The first line is `# <title>`. The fields are `<Field>: <value>` lines above the first `## ` heading:
  - `Type:` `research`, `prototype`, `grilling` or `task`.
  - `Status:` `open`, `claimed`, `resolved` or `dropped` (`dropped` is the out-of-scope close).
  - `Blocked by:` `none`, or ticket numbers joined by `, ` (`01, 03`).
  - `Repo:` a repo key of `repos.yml`, or `all`.
  - `Claimed by:` `none`, or the session id that claimed it.
- `## Question` is the question, the title when none was given.
- `## Answer` is empty while the ticket is open or claimed. Resolved: the answer, its first line the gist.
  Dropped: why it is out of scope. A research answer is the gist and the report's path.

## Derived views

- **Unblocked**: every ticket in `Blocked by:` is `resolved` or `dropped`.
- **Frontier** (`map.sh frontier <R-id>`): the open, unblocked tickets in number order, one line each,
  `<NN> <type> <title>`.
- **Clear** (`map.sh clear <R-id>` exits 0): no ticket `open` or `claimed`, and `## Not yet specified` empty.
  Exit 1 prints what is left, one line per ticket (`<NN> <type> <status>: <title>`) and one for the fog.

## Status

| status | set by (`map.sh status <R-id> <word>`) | when |
|---|---|---|
| `charting` | `map.sh new` | the CEO takes the request in |
| `grilling` | the session that asks the first grilling ticket; the CEO on a reopened map | a question waits for the human |
| `planned` | the session whose write made the map clear | the grills per parent can start |
| `queued` | the CEO | the human approved the plan |
| `running` | the CEO | the first lead of the request started |
| `done` | the CEO | `task-done.sh` closed the last parent |

`planned`, `queued`, `running` and `done` need the map clear; `done` follows `running` only and is final;
nothing goes back to `charting`. A map that is not done takes a new ticket in any status. A cross-repo need of
a running request (PLAN 3.2 [XR]) reopens it: a new grilling ticket and `status <R-id> grilling`; once that
ticket is resolved or dropped and the map is clear again, the CEO sets the status it had before, `running`
while a lead of the request lives, else `queued` or `planned`.

## Export

`map.sh export <R-id> <key>` prints the seed the grill of that repo's parent starts from, before its spec:

```markdown
# Request map R-20260925-1, seeded into the grill of ecs

Every ledger row below is closed on the request map: carry it into the gap ledger as it stands and never ask
it again. The plan-ready frontmatter carries `request: R-20260925-1` beside `task:`.

## Destination

Invoices reach the ledger every night, from ecs and bff alike.

## Gap ledger (pre-closed)

| # | type | question | deps | state | answer |
|---|---|---|---|---|---|
| M01 | research | Which ledger API | - | closed | The REST API, v2.; requests/R-20260925-1/issues/01-which-ledger-api.md |
| M02 | decision | Pick the store | M01 | closed | Postgres.; requests/R-20260925-1/issues/02-pick-the-store.md |

## Out of scope

- [Get ledger access](issues/03-get-ledger-access.md): Access is the other team's rollout, not this request.

## Terms

- **Ledger**: the accounting system of record. Avoid: books
```

A row is a resolved ticket with `Repo: <key>` or `Repo: all`; its type is the ledger's (`grilling` is
`decision`, `prototype` stays, `research` and `task` are `research`); `deps` names only rows of the same
export. An empty section prints `none`.
