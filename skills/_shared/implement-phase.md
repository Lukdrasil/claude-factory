# Implement phase (ADR-0030)

Read by `block-feature` and `block-bugfix` when the progress file has a `## Handoff` section.

- **The red tests are the contract.** Your job is to turn them green, not to bend them to fit. This one is not
  a request: the policy guard denies every edit of a file matching the repo's `test-globs` in this phase
  (issue #290) until you have written the analysis below — changing a test is never the first move.
- A **new** test file for code you add is still allowed — the lock protects the contract, not new coverage.
  Adding a case to an existing test file is denied too; put it in a new file, or take the escape hatch below.
- **Test deviations.** When the guard denies an edit, the answer is an analysis, not a workaround: decide which
  of the two is wrong for the goal in `## Acceptance`. If the implementation can be made to satisfy the test as
  written, fix the implementation — that is the usual answer. Only when the test itself is wrong, write the
  analysis into the progress file under `## Test deviations` — **under 60 words per test file**: the file by
  name, the exact change, and why fixing the implementation cannot get you there. With that on record the guard
  lets the edit through and logs it, and the reviewer weighs it against exactly that justification (P5,
  ADR-0030). A deviation you cannot justify that way is `blocked` with a question, not an edit.
- Development orchestration you add or change gets no test of its own:
  `<plugin-root>/skills/_shared/test-exemptions.md` says which files that is and what still has to be tested.
- Characterization tests must stay green; if one fails, that is a regression inside the blast radius.
- Every member you write or edit follows `<plugin-root>/skills/modern-idioms/SKILL.md`: the stack's current
  construct within the project's language version, free of the inefficient idioms its reference lists.
- Every comment line you add passes `<plugin-root>/skills/comment-policy/SKILL.md`: a reason, an invariant, a warning or
  an external reference the code cannot carry, with its class prefix; the comment gate denies the rest.
- Every log call and catch block you write follows `<plugin-root>/skills/logging-decisions/SKILL.md`: who acts
  on the entry decides its level, expected exceptions are caught first and quietly, and no personal data or
  secret goes into a log.
- If the contract as a whole turns out to rest on a misreading of the goal in `## Acceptance`, that is `blocked`
  with a question, not a rewrite of the tests.
