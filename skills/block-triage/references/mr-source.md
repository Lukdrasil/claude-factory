# block-triage — a merge request as the source

The source is a merge request when `## Context` has a line `- mr: <url>`, or when the issue's text or comments
link an MR that claims to solve it. The worker procedure in `SKILL.md` applies with these deltas:

- **The draft is a review task.** `archetype: review`, `branch: review/<slug>` (the writer inserts the task id
  after the prefix, so the MR's head branch cannot live here; the review takes the head from the MR),
  `mr_url:` the MR, and `- mr: <url>` copied into the draft's `## Context`. Its `## Acceptance` is the
  `## MR review` report of `<plugin-root>/skills/mr-review/SKILL.md` in the progress file.
- **The review runs later.** A triage session has no product clone to trace the chain in, so `block-review`
  runs the skill when it picks the task up. With a product clone in a session of your own
  (`factory solve <mr-url>`), run the skill yourself and let its report set the tier.
- **Read the MR as you read an issue.** `<plugin-root>/bin/forge.sh mr <url>` gives the title, the description,
  the head branch and the comments; they go under `## Internal` next to the issue. The tier is `yellow` until
  the review says otherwise, and the complexity follows the size the forge reports.
- **`## Issue update`** says that the MR will be reviewed against the issue and what the review reports:
  the problem, the fit, the extra, the chain and the findings with a severity each.
