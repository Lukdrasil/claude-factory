# What cut-check reviews

`decompose` derives the drafts mechanically from `## Proposed tasks`, so at a plan that has not moved since an
`aligned` plan-check the drafts contain almost nothing plan-check has not already judged, and a second full
panel buys repetition rather than a second subject. cut-check therefore starts by comparing hashes, and the
answer sets its scope.

| the plan since plan-check | scope |
|---|---|
| **unchanged**: `repos/<key>/verdicts/<slug>.md` carries a `## plan-check` section, `verdict: aligned` and a `plan_hash` that still matches plan-ready.md | the cut only, the four items below and nothing else |
| **changed**, or there is no `aligned` plan-check to compare against | the full rubric of `axes.md` over the drafts, with the specialist panel in force |

The four items of the narrow scope. None is optional, and none is something plan-check could have done:

1. **The mapping.** Every `## Proposed tasks` entry has exactly one task and every task has an entry;
   `tier`, `archetype`, `complexity`, `docs` and `acceptance` are carried over unchanged. An "improved"
   acceptance or a downgraded tier is a blocking finding, because the grill made that decision and decompose
   does not remake it. `depends_on` ordinals are rewritten to real ids that resolve to tasks of this batch or
   to existing ones, with no cycles.
2. **The boundaries.** Each task is independently verifiable: one branch, one MR, an acceptance that runs
   without another task of this batch being finished first, and a `## Context` a fresh session could work
   from alone.
3. **The frontmatter invariants a plan cannot express**: the `branch` prefix per archetype, `status: draft`,
   `depends_on` resolvable, the `- forge issue:` line copied onto every task or the whole `## Internal`
   section omitted. A plan has nowhere to record these, so plan-check never saw them.
4. **The doc-fact sweep.** Every mismatch `doc-facts.sh` reports that this cut's tasks would create is
   checked against the task that owns the update, in the same branch that falsifies the count. The grill
   answered these in its ledger; here you check the answer landed in a task's `## Docs`, and a mismatch with
   no owner is a blocking finding. A claim the ledger explicitly declined stays declined. A dead citation
   from `doc-cites.sh` in a document this plan leans on is a `suggestion`.

Everything outside those four is content plan-check judged at this hash, and that verdict stands. A finding
you could only make by re-reading the plan belongs to plan-check: if it matters, the plan is edited, which
changes the hash, and both invocations run again on the wide scope.

The specialist panel is a plan-level instrument, so on an unchanged plan it does not fire at all: spawn
nothing, whatever the domain count and whatever the tier.

**This is a scope rule, not an opt-out.** cut-check still runs at every tier and for every repo with
`docs/architecture/`, and the verdict contract is unchanged.
