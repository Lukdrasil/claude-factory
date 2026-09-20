# The report

Beyond the five axes, ask about error paths, data and migrations, who triggers the change and how anyone
notices it broke. A missing decision is a finding, not an invitation to invent one.

```markdown
## spec-critic - <id> (tier <yellow|red>)

### Verdict
`OK` | `needs additions before approve` - <n> blocking, <n> suggestions. One sentence why.

### Findings
- **[blocking|suggestion]** <axis> - what a fresh session is missing.
  **Proposed edit** (`## <section>`): <finished text to paste into the draft>
- **[blocking]** docs - <the public behaviour or architecture this task changes>, and `## Docs` does not say
  what that means for the documentation.
  **Proposed edit** (`## Docs`): <the docs to update in the same branch, one per line, or `none` with the one
  sentence why>

### Questions for the human
- <a decision I have nowhere to take from>
```

Budget: **the report under 300 words**. A finding is two lines: what is missing, and the finished text to
paste. The axes you walked and found clean do not appear.

If the spec is fine, finish with a **short OK**: verdict `OK`, one sentence why, and no findings pulled out
of thin air. Criticism for its own sake does not improve a spec, it only inflates it.
