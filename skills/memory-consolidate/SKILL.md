---
name: memory-consolidate
description: A consolidation pass over memory: duplicates, contradictions and stale lessons proposed for merging or retiring, plus repeated tool-call failures mined into new lessons. Called from a consolidation task of archetype research that block-research drives.
---

# memory-consolidate

Memory grows by accretion: nobody retires a lesson. This pass produces **proposals, never edits**: you never
write into `memory/` (P6, ADR-0011). `block-research` owns the session mechanics.

## Preconditions

- In the state clone `$WORK_DIR/state`, the scope is `memory/global/*.md` and `repos/<key>/memory/*.md`.
- The `proposals/` subdirectories are out of scope: a pending proposal is not memory.
- At most **five proposals per pass**: the gate is human time.
- Code, tasks and docs are out of scope: a remedy that changes one is a proposed follow-up task.

## Steps

1. **Inventory the scope**: file, claim in one sentence, evidence. Done when every file has a row.
2. **Mark the findings.** A **duplicate** is two lessons saying one thing; a **contradiction** two that
   cannot both hold, the code deciding which; a **staleness** evidence pointing at code, a command or a
   decision that no longer holds. Verify in the clone; an unverified claim is no finding. Done when every
   finding names its kind and evidence.
3. **Mine `## Tool failures`** out of `repos/<key>/tasks/*.md`. A pattern is one tool failing one way in two
   or more tasks; one-offs are noise. Verify the cause in the clone or in the skill the session ran: missing
   guidance catches the next session too. Done when every pattern is a proposal, a task, or dropped with
   the reason.
4. **Write one proposal per finding**, in the format below; a mined lesson is new and carries no `Replaces:`.
   Over the limit, keep those that shrink memory most; the rest stay open in the report. Done when no
   proposal-less finding passes as finished work.
5. **Report** into `$WORK_DIR/state/repos/<key>/research/<id>-<slug>.md`, **under 200 words**: the counts first
   (files read, findings, files left once every proposal is approved, tasks with tool failures), then one
   line per finding and per pattern, naming files by path. Done when every finding is in it.

## Proposal format

One file per proposal, beside the memory it consolidates: `$WORK_DIR/state/memory/global/proposals/<id>-<slug>.md`,
or `$WORK_DIR/state/repos/<key>/memory/proposals/<id>-<slug>.md` for a repo lesson. Never deeper, the gate looks no
further. The body is the lesson itself, **under 80 words**: a curator decides from it alone.

```markdown
# <the merged lesson in one sentence>

Why: why it holds and what happens when it is forgotten.
Evidence: <id>, `path/file.ext:line`, a commit SHA or command output.
Replaces: <path to source 1>, <path to source 2>
```

`Replaces:` lists existing paths relative to the state repo root, each gone on approval. A duplicate
merges both evidences; a contradiction says in `Why:` why the other falls; a staleness keeps the rewrite, or
proposes that the lesson goes away without a replacement. The gate has no delete button: the curator removes
the sources with git and rejects it (RUNBOOK 4). A human decides, at the gate (P6) or through
`memory-curator` (ADR-0052).
