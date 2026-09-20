# The seven review axes

Read alongside step 4 of `<plugin-root>/skills/block-review/SKILL.md`. One axis at a time, in this order.

**acceptance.** Does the change do what the task asked, and is it verified by a test? Files exempt under
`<plugin-root>/skills/_shared/test-exemptions.md` need no test of their own; product logic hidden inside one
to ride the exemption is a finding.

**correctness.** Missing cases, silent failure, broken invariants.

**security.** External input, authorization, secrets in the repo.

**test quality.** Do the assertions verify behaviour? A zero-assert test, or one asserting only not-null,
proves nothing, and a test exercising only its own mocks proves only the mocks. Then diff the test files
against the tests-phase commit, the files being the ones matching `test-globs` in the repo's toolset: a
weakened assertion, a deleted case or a test retro-fitted to the implementation is the most reliable sign of
a faked green, and it is **blocking** unless the progress file justifies it under `## Test deviations`. Last
the progress file's `## Quality` table: a row over 8 whose note records why is settled, a row over 8 with an
empty note is the finding, and a changed method with no row at all is `must` (blocking).

**docs.** Does the diff change public behaviour or architecture that a doc describes, an endpoint, a CLI
flag, a config key, a module, an external integration, while README, runbook, API contract or architecture
model stayed the same? That is a finding, and so is a `## Docs` item the branch did not do. Compare against
the diff, not against the MR description. An internal-only change is not a finding, and an absent `## Docs`
means none. A diff embodying an architectural decision with no ADR proposal is a suggestion.
`sh <plugin-root>/bin/arch-delta.sh <repo> <base-branch>` does the model half: output with no
`docs/architecture/` change and no progress-file note is a finding, and empty output while the diff adds a
component, dependency direction, external service or public endpoint is "model not updated".

**craft.** Every member the diff touches against `<plugin-root>/skills/modern-idioms/SKILL.md`: a hit the
progress file does not record is a suggestion with its row code. Every comment line the diff adds against
`<plugin-root>/skills/comment-policy/SKILL.md`: an unprefixed or restating line is a suggestion naming the
replacement.

**scope.** Something from `## Out of scope` that should not be in the diff, or a missing piece of the
assignment.

**The integrated review only.** The brief carries the `block-verify` reports, the `## Quality` table and the
`## Duplication` candidates `dup-check.sh` printed. Read them as rules.

- Every `## Duplication` candidate is judged by you against the code it names: a confirmed duplicate of a
  helper the repo has is `should` (a suggestion), naming the helper and the call that replaces the copy. A
  copied block over twelve lines is `must` (blocking). A candidate that is not a duplicate is one line under
  `### Verified`.
- One `must` anywhere makes the verdict `changes needed`.
