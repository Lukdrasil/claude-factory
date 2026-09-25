# Review rubric

The evidence a finding carries, the severity that turns findings into a verdict, and the report. The five
axes every finding is drawn from are in `axes.md`, and stale documentation in `drift.md`. Read them before the
input, so you read the plan against the rubric instead of fitting the rubric to the plan afterwards.

You judge a plan or a task cut against what the product repo **records**: `docs/architecture/`,
`docs/product/`, `docs/adr/` and `CONTEXT.md`. An objection with nothing recorded behind it is not a finding;
it is either a question for the human or silence.

## Evidence

Every finding carries one of these, and it has to resolve when the human opens it:

| form | for |
|---|---|
| `path/file.ext:line` | anything you read out of the code |
| `ADR-NNNN` | a decision that was taken |
| `docs/architecture/<doc> § <section>` | a documented boundary, constraint or responsibility |
| `QS-NN` / `R-NN` | a quality scenario row in `04-quality-scenarios.md`, a risk row in `07-risks.md` |

A proposal in the plan is cited by its heading or ordinal; a task draft by its title.

`<plugin-root>/bin/doc-cites.sh` checks the `path/file.ext:line` form mechanically: a citation whose file is
gone or whose line is past the end of the file is dead, and a finding carrying one goes back for evidence.

## Severity and verdict

- **blocking**: the plan contradicts something recorded, a constraint, a quality scenario's measure, a
  container or dependency row, an accepted ADR; or two proposals collide on one public contract.
- **suggestion**: everything else worth saying, including drift between the docs and the code.

The verdict is `misaligned` when there is at least one blocking finding, `aligned` otherwise. Suggestions
never make a verdict `misaligned`.

## Report

What the `plan-architect` agent returns and what the host skill checks. A specialist returns its
`### Findings` in the same shape, for its domain, and no `### Verdict`.

```markdown
## architect-review - <plan-check|cut-check>: <slug>

### Verdict
`aligned` | `misaligned` - <n> blocking, <n> suggestions. One sentence why.

### Findings
- **[blocking|suggestion]** <axis> - what the plan does and what recorded thing it contradicts.
  **Evidence**: <path/file.ext:line | ADR-NNNN | docs/architecture/<doc> § <section> | QS-NN>
  **Proposed edit**: <finished text for the plan section or the task draft>

### Questions for the human
- <a choice there is nothing recorded to decide from>
```

Budget: **the report under 500 words**. The verdict line carries the counts, so the human knows what they are
deciding before reading a finding. A finding is the three lines above and no fourth: the evidence is a
reference the human opens, not a passage quoted back, and the proposed edit is finished text. One line per
question. The rubric you applied and the checks that came back clean are not part of the report.

`aligned` with no findings is a valid outcome and the common one. Findings invented to look thorough cost the
human a decision and buy nothing.
