# CRAP loop

The standing feedback signal on the code a task adds (issue #293) — read by `block-feature` and `block-bugfix`,
run after acceptance is green and before the contract's `## Output`.

It is a **verdict**: `block-verify.sh` reddens a block whose run reports a changed method over the threshold,
and `block-merge.sh --verify` repeats it over the merged tree. The threshold is `crap-threshold:` in the
toolset, **8** by default.

Scope = this task's diff, never the repo. `git fetch origin && git diff --name-only origin/<base>...HEAD` names
the changed files, and the diff names the methods you touched in them. Run toolset `coverage`, then `crap`
over **those files**, and read **only** those rows. A whole-repo run is out of scope (ADR-0014).

Every changed method over **8** gets one more turn on a green suite, then a re-measure. Two levers, because
CRAP = complexity² × (1 − coverage)³ + complexity: extract a method to cut complexity, or add the missing test
to raise coverage. New coverage goes in a **new test file**: in the implement phase the policy guard denies
every edit of an existing test file, a new case inside one included (issue #290). If the case cannot live
anywhere else, it takes the `## Test deviations` route of your block skill, which has to say why a new file
will not do.
WIP push after each green.

Stop when every changed method is ≤ 8, **or** when the next turn would break `## Acceptance`, `## Out of scope`
or the behaviour the task promises. At 100 % coverage CRAP equals cyclomatic complexity, so a method that has
to stay above complexity 8 never gets there on coverage alone: record it rather than force it.

Then write `## Quality` into the progress file. Every changed method is a row, one skipped or exempt under
`_shared/test-exemptions.md` included: name it and say which. A row over 8 with no reason is a
review finding, and so is a changed method with no row.
The table is the whole section — **`note` under 15 words**, empty for a row at or under 8, and no prose
around it.

```markdown
## Quality
CRAP over the methods changed by this task (threshold 8):

| method | CRAP | note |
|---|---|---|
| `OrderParser.Parse` | 2.0 | |
| `OrderParser.Apply` | 6.8 | was 19.4 — extracted `ApplyDiscount` |
| `Program.Main` | skipped | exempt: composition root |
| `Dispatcher.Route` | 11.0 | over 8 — the switch is the task's contract; splitting it changes the public API |
```

No `crap` in the toolset: the section is one line — `no crap tooling for this repo` — and the session moves on
(the contract's Preconditions).
