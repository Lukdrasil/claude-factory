# Refinement

If the task frontmatter has `mr_url` (not `null`), you are in a refinement run (ADR-0031): the MR exists,
the branch carries finished work, and your assignment is the human's review comments, not new development from scratch.

1. Fetch the comments **once, at the start**: `<plugin-root>/bin/forge.sh mr <mr_url>` (it picks the tool from the
   host in the URL itself). Anything arriving after the start is the next refinement's problem — no polling.
2. Skip any comment that already has a reply with the marker "addressed in" — it was handled in an earlier iteration.
3. A comment that would change the task's Goal/Context/Acceptance is **not yours to implement**: self-report `blocked`
   with the question in the progress file, or record it in the progress file as a proposed follow-up task.
4. Work through the remaining comments with the normal loop from the archetype skill's Procedure; run acceptance
   verbatim as always.
5. After the final push, reply to every comment you addressed with "addressed in `<sha>`" (`<sha>` = the branch HEAD
   after the push) via `gh pr comment <mr_url> --body "…"` / `glab mr note create`.
   Do not resolve threads — the API differs between forges and a human ticks them off at the next review.
6. On GitHub, if the MR description still announces blockers this run resolved, rewrite it once (#428): it was
   written by the previous session, which did not yet know the outcome. `gh pr edit <mr_url> --body "…"`, the body
   shaped the way `session-contract.md` prescribes for the MR. Change only `--body`: the title, the
   base branch, reviewers and labels are not yours. On GitLab there is no equivalent yet; the comment stays the record.

## Receiving the review

The comments are the spec of this run, not a debate. Before touching code, reread the code as if the reviewer
is right — they saw it with fresh eyes and usually are. Then per comment: fix, verify with the archetype's
loop, reply "addressed in `<sha>`". Never argue in a thread and never explain why the code was already fine —
a technical disagreement goes the step-3 route: `blocked`, your reasoning in the progress file, a human
decides. The diff answers the comments and nothing else; adjacent improvements do not ride along.

The `## Output` section of `session-contract.md` applies unchanged; the MR already exists and is not created again.
The end is again a self-report of `review`.
