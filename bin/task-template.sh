#!/bin/sh
# The skeletons the flow writes, printed instead of carried in prose (slim-harness M4).
#
#   task-template.sh <task|block|plan-ready|progress|handoff|investigation>
#
# One kind per run, the skeleton on stdout, nothing else. The shapes are the ones the skills describe:
# `task` the draft a triage writes (block-triage), `block` the task decompose hands to task-new.sh, both with
# the frontmatter task-format.md validates; `plan-ready` the plan a grill ends with; `progress` the snapshot a
# worker rewrites and `handoff` the section the tests phase adds to it; `investigation` the five sections an
# investigator reports in.
#
# Exit 0: the skeleton.
# Exit 1: no kind, more than one kind, or a kind that does not exist, the reason on stderr.
set -eu

die() { printf 'task-template: %s\n' "$1" >&2; exit 1; }

kinds='task|block|plan-ready|progress|handoff|investigation'
[ $# -ge 1 ] || die "usage: task-template.sh <$kinds>"
[ $# -eq 1 ] || die "one kind at a time: task-template.sh <$kinds>"

case "$1" in
  task)
    cat <<'TEMPLATE'
---
id: <new-id>
repo: <key>
branch: feat/<new-id>-<slug>
status: triaged
tier: <green|yellow|red>
archetype: <feature|bugfix|refactor|research|ops>
complexity: <low|medium|high>
runtime: default
depends_on: []
parallel_group: null
attempt: 0
max_attempts: 3
plan_hash: null
owner: null
mr_url: null
created: <YYYY-MM-DD>
---

# Goal
One sentence, and the MR title as it stands: Conventional Commits (`type(scope): subject`), at most 130 characters.

## Context
The substantive context for the work itself: what matters from the issue, rewritten in your own words, and how
to approach it. Do not repeat the title or the whole text of the issue, and do not mention anything about running
claude-os (repo-key, repos.yml, the state repo, worker sessions); that belongs under `## Internal`.

## Acceptance
A runnable criterion (a command/test), not a consideration.

## Out of scope
What from the issue does not belong in this task.

## Issue update
For the issue author, **under 150 words**, opening with the one sentence that says what will be
done. Then the problem as you understood it, the suggested approach, what is in and out of scope, and how the
result will be verified. Classify the work in plain words (kind of change, size, risk).
No claude-os internals here: no repo-key, task ids, state repo, sessions, tiers or archetypes.
This section is what gets appended to the issue description and what the dashboard
write-back button sends. Only when the source is a forge issue; for a roadmap draft, omit the section.

## Internal
- triage: <the id of this triage task; it pairs the auto-close, approving the draft closes the triage task>
- forge issue: <the issue URL>
- issue title: <title>
- milestone: <milestone, or "none">
- from comments: <what in the comments changes the assignment, or "comments change nothing">
- from attachments: <what matters in the images and files, or "none"; asset skipped lines go here too>
- tier <tier>: <why>
- complexity <complexity>: <why>

Everything claude-os-related, plus verbatim excerpts from the issue. A self-contained spec: this file alone
must be enough for a fresh session, so copy the whole text of the issue here if `## Context` does not cover it;
the implementation session works from this file without reading the issue again.

## Attempts
TEMPLATE
    ;;
  block)
    cat <<'TEMPLATE'
---
id: T-001                    # a placeholder, the server overwrites it with the id it assigns
repo: <repo-key>
branch: feat/<slug>          # the server inserts the assigned id: feat/T-005-01-<slug>
status: draft
tier: green
archetype: feature
complexity: low
runtime: default
depends_on: []
parallel_group: null
attempt: 0
max_attempts: 3
plan_hash: null
owner: null
mr_url: null
created: <YYYY-MM-DD>
---

# Goal
One sentence, and the MR title as it stands: Conventional Commits (`type(scope): subject`), at most 130 characters.

## Context
From the plan `repos/<repo-key>/plans/<slug>-plan-ready.md`, the path in full, so the architect gate can find
the verdict of the plan this task came from.
A self-contained spec: a fresh session gets only this file plus the generated CLAUDE.md.
References to existing code, ADRs and decisions from the grill the agent would not otherwise guess.

Design (approved in the grill):
<the members of the plan's ## Program design this task implements, verbatim: file, signature, what it solves>

## Acceptance
A command or test that decides done/not-done once it has run.

## Docs
`none`, or the docs to update in the same branch.

## Out of scope
What this task deliberately does not do (and which task it belongs to, if any).

## Internal
- forge issue: <the forge issue url of the task this plan came from; omit the line and the section when it has none>

## Attempts
TEMPLATE
    ;;
  plan-ready)
    cat <<'TEMPLATE'
---
repo: <repo-key>
task: <T-NNN or none>
created: <YYYY-MM-DD>
---

# Spec
One sentence: what should happen and why.

## Decisions
- <what was decided>: <why, whose choice>

## Quality scenarios
<only when a proposal is red; omit the section otherwise>

| id | Attribute | Source and stimulus | Environment | Response | Measure |
|---|---|---|---|---|---|
| QS-01 | <attribute> | <what triggers it> | <under what conditions> | <observable behaviour> | <number and unit> |

## Program design
<the sketch the human approved in the design round, verbatim: per file, members without bodies, at most two sentences each>

### `<path>` (new | existing)
<signature>
  <what it solves>

## Proposed tasks

### 1. <title>
- tier: <green|yellow|red>, <why>
- archetype: <feature|bugfix|refactor|research>
- complexity: <low|medium|high>, <why>
- depends_on: []
- goal: <one sentence>
- context: <what a fresh session must know; references to code, ADRs and decisions from the grill>
- acceptance: `<the command or test that decides done/not-done>`
- docs: <none | the docs to update in the same branch>
- design: <the members of ## Program design this task implements, by file and name | none>
- out of scope: <what does not belong in this task>

## Out of scope
What the whole spec deliberately does not do (and why).

## Gap ledger
| # | type | question | state | answer |
|---|---|---|---|---|
| 1 | decision | <question> | closed | <answer> |
TEMPLATE
    ;;
  progress)
    cat <<'TEMPLATE'
# <id>: <task title>
**<on track|blocked|acceptance green>**, the one thing a reader needs now.

## Done
- what is genuinely finished and verified

## In flight
- what you are working on right now

## Remaining
- what is still missing for acceptance

## Evidence
- `<the proving command>` -> exit 0, `<the key line of its output>`

## Last milestone
One sentence: what you got done most recently.
TEMPLATE
    ;;
  handoff)
    cat <<'TEMPLATE'
## Handoff
- **Blast radius:** the files/modules affected and why
- **Green tests:** what covers the existing behaviour (list the new characterization ones)
- **Red tests:** a list of `test -> what should turn it green`; for each, why and how it fails
- **Commands:** the toolset commands that run the whole suite / only the red tests (`test`, `test-filter <expr>`)
- **Notes:** traps found during analysis, what NOT to refactor
TEMPLATE
    ;;
  investigation)
    cat <<'TEMPLATE'
# <id>: investigation

Under **400 words**, these five sections, in order.

## Call chain
One line per step, `path/file.ext:line`, entry point to handler to domain to persistence.

## Candidate causes
Ordered, each with evidence and how to rule it out.

## Data shape
Tables, columns, mappings the chain touches, from the ORM mappings and migrations the toolset's `db-schema`
row names, never a live database.

## External contracts
Service, contract file, the operation actually called, where behaviour and contract differ, from the contract
files, typed clients and client registrations the `api-contracts` row names, never a live call.

## Open questions
What the investigator could not resolve from the repo alone.
TEMPLATE
    ;;
  *) die "unknown kind '$1': one of $kinds" ;;
esac
