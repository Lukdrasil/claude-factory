# The score block and the subagent prompt

Print this to the user before the spawn, filled in; without it the performance choice is invisible.

```
rubric: B=<n> A=<n> C=<n> K=<n> -> S=<sum> -> <tier> (<model> × <effort>)
B: <half a sentence why>   A: <half a sentence why>
C: <half a sentence why>   K: <half a sentence why>
escalation: <rule, or "none">
```

The agent definition carries only the model and the effort; you supply the content, all of it, in the prompt.
Fill the `Tier:` line in yourself: the subagent cannot see the rubric scores or its own `effort:`, so a
placeholder left in the template comes back as an invented number in the permanent record.

```
Assignment: <the user's assignment, verbatim>

Write the report to: <absolute path to the file>

Source discipline: the source of truth is the code, documentation is a supplement; when they disagree,
the code wins. Back every claim with a `path/file.ext:line` reference, a commit SHA or a URL.
An unsupported claim does not belong in the report; what you do not know belongs in `## Left open`.

Product repos are read-only. Commit nothing and push nothing.

Write the report in exactly this structure:

# <the topic in one sentence>

**<the answer in one sentence>** - <the recommendation>

Assignment: <the assignment, verbatim>
Tier: <S0|S1|S2|S3> (<model> × <effort>), rubric B/A/C/K = <n>/<n>/<n>/<n> -> S=<sum>
Date: <YYYY-MM-DD>

## Question
Cut into sub-questions.

## Findings
An answer to every sub-question, with citations.

## Conclusion
What follows from it and what to do next.

## Left open
What could not be found out, and why.

## Sources
The files, commits and URLs the report rests on.

Budget: **the report under 1200 words**. The bold line under the title is the answer, before any argument.
One sub-question per finding, at most five lines; a citation is a reference the reader opens, so do not
quote what it points at. `## Conclusion` under 100 words, one line per item in `## Left open`. Leave out
the searches you ran, the leads that went nowhere and how confident you feel.

When you are done, return a summary in at most 6 sentences. The report must already be written to disk.
```

The report has to make sense a year from now without the context of this session, which is why it carries the
verbatim assignment and the chosen tier.
