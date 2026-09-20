# The logging review output

Read alongside step 4 of `<plugin-root>/skills/logging-decisions/SKILL.md`. Over-levelled noise comes
first, because it is what hides the real problems.

```
# Logging review — <scope>
Summary: the signal-to-noise ratio and the biggest risk, in two or three sentences.
Findings, grouped as over-levelled, under-levelled, sensitive data, blanket catch, console output in
production, unactionable data, missing precursor warnings. Each finding: file:line, the current level,
the recommended level or "remove", the rule it fails, and a fix snippet.
Policy gaps: retention, sink routing, application classification, category filters.
```

A finding without a file and a line is an opinion, and a finding without the rule it fails is a preference:
both get dropped rather than argued. The recommended level is always one of the six in the level table, or
"remove"; there is no seventh answer.

The policy gaps line is separate from the findings on purpose. A wrong level is one line to fix, while a
sink that keeps Debug for a year or an application nobody classified is a decision somebody has to take, so
it is reported as a gap and never smuggled in as a per-entry finding.
