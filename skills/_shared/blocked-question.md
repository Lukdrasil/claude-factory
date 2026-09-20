# The blocked question

`## Question` is a decision surface, not a findings dump. Write it in this order and keep the whole
section **under 100 words and 12 lines** — a longer question is a question you have not finished cutting.

1. **The decision**, one or two sentences: what the human must choose, not how you got there.
2. **The options**, a numbered list, one line each, each answerable on its own. Three options are three
   lines — never an inline "… or … or …".
3. **The recommendation**, one line: which option you would take and why, so confirming is cheaper than adjudicating.
4. **Why you are blocked**, at most two lines. The evidence stays in `## Evidence` and the report.

The answer comes back as one line in the task's `## Context`, naming an option by number:

```markdown
**Answer (YYYY-MM-DD): option 2** — <optional one line>
```

An answer that picks an option and leaves the rest of the task contradicting it re-dispatches straight
into the same block. So whoever answers also applies what the option requires — `archetype`,
`## Acceptance`, `# Goal` — before flipping `blocked → ready`. Numbered options make that checkable.
