# Verdict file

The one place this format is defined; the gate and decompose read it from here.

**Path**: `repos/<key>/verdicts/<plan-slug>.md` in the state repo, a sibling of `plans/`, so a plan scan
never offers a verdict as a plan. One file per plan slug, written by both invocations.

```markdown
---
verdict: aligned
plan: repos/<key>/plans/<slug>-plan-ready.md
plan_hash: 3b0c1e...
---

# <slug> - architect review

## plan-check
<the reviewer findings, verbatim>

## cut-check
<plan unchanged since plan-check, scope was the cut | plan changed since plan-check, full review>
<the reviewer findings, verbatim>
```

| field | value |
|---|---|
| `verdict` | `aligned`, `misaligned` or `overridden-by-human`. The agent returns only the first two; `overridden-by-human` is a human act on this file, never a value you write from a report. |
| `plan` | the path to plan-ready.md, relative to the state repo root |
| `plan_hash` | `sha256sum repos/<key>/plans/<slug>-plan-ready.md \| cut -d' ' -f1`, always of plan-ready.md, for both invocations, so consumers have one hash to recompute |

- `cut-check` rewrites the same file: it recomputes the hash, sets the current `verdict`, replaces its own
  section and leaves the `plan-check` section standing. The frontmatter reflects the latest invocation.
- The `## cut-check` section opens with the scope it ran under and then the findings. The format does not
  change by one character, so `architect-gate.sh`, `decompose` and `grill` read the same
  fields they read before.
- **Staleness**: editing plan-ready.md changes its hash, and the gate and decompose recompute it, so a
  mismatch counts as no verdict. After editing the plan, re-run the invocation.
- **Consumers** write tasks on `aligned` or `overridden-by-human` with a matching hash. `misaligned`, a
  missing file and a hash mismatch all block the write.
- **Lifecycle**: the verdict stays until its plan's tasks are created, then decompose deletes it in the same
  commit that concludes decompose.
