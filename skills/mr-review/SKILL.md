---
name: mr-review
description: Review of one merge request or pull request against the problem it solves: the linked issue, the fit, the extra, the defects along the whole chain, and the severity of each. Use on an MR or PR URL, when a triage source is an MR, and in a review task naming an MR.
---

# mr-review

Plugin root: `${CLAUDE_PLUGIN_ROOT}`. You gather the material, `mr-reviewer` judges it from a fresh context,
you check its report. The MR is read-only: nothing committed, pushed or posted.

## Preconditions

- An MR or PR URL, or a branch of a repo with a forge remote; ask when neither.
- A clone of the product repo, cwd or from `repos.yml`; `<base>` is its `default_branch`, else the
  remote's HEAD.
- A forge CLI signed in to the MR's host (`${CLAUDE_PLUGIN_ROOT}/bin/forge.sh hosts`).
- `<review-dir>` is `<root>/<key>/.harness/mr-<n>/` with `WORK_DIR` set, else `../mr-<n>/` beside the clone.
  Never inside a clone: nothing here reaches a commit.

## Steps

1. **The MR text.** `sh ${CLAUDE_PLUGIN_ROOT}/bin/forge.sh mr <url>` into `<review-dir>/mr.md`. Done when title,
   description, head branch and comments are there.
2. **The problem.** Find the issue: closing references, description links, the number in the head branch
   or a commit subject, a matching title. `forge.sh issue <url>` into `<review-dir>/issue.md`; a `T-NNN` in the
   branch means the state repo task instead. Nothing found: write `no issue linked`. Done when `issue.md`
   exists.
3. **The diff and the checkout.** Fetch the head, `git diff <base>...FETCH_HEAD` into
   `<review-dir>/review.diff`, the head checked out at `<review-dir>/tree`, and
   `sh ${CLAUDE_PLUGIN_ROOT}/bin/investigate-inventory.sh <tree>` into `<review-dir>/inventory.txt`.
   A merged MR whose head branch is gone, a missing forge CLI and the fetch commands (`mergeCommit`) live in
   `${CLAUDE_SKILL_DIR}/references/merged-mr.md`. Done when the four files exist and the diff is not empty.
4. **The review.** Spawn `mr-reviewer` with a brief per
   `${CLAUDE_PLUGIN_ROOT}/skills/_shared/delegation.md`: the five paths, `<base>`, the head branch and the
   toolset's `db-schema` and `api-contracts` rows. It has no Bash and no Task. Done when the report is back.
5. **The check.** Every finding names a `path/file.ext:line` in the diff or the checkout, `### Chain` every
   entry point the diff changes, `### Problem` the issue from `issue.md` or `no issue linked`.
   Send the report back once with what is missing; one that returns without evidence is dropped. The shape
   is `${CLAUDE_PLUGIN_ROOT}/agents/mr-reviewer.md`; you add no finding of your own, a defect the agent
   missed goes back as a question. Done when every finding you keep has evidence a human can open.
6. **The delivery.** Remove the detached worktree, keep `<review-dir>` as the audit trail, then by
   caller:
   - a plain session: the report is your answer; offer the text and post only on an explicit yes.
   - a triage (`block-triage`, or `factory solve` step 3): the report becomes the `## MR review` section
     under the draft's `## Context`, the highest severity flooring the tier: `blocking` red, `major` yellow,
     minor green.
   - a `block-review` task: it is the progress file's `## Report`, verdict and all.

   Done when the caller has it in its shape.
