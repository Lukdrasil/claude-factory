# A merged MR, and the fallbacks

Read alongside step 3 of `<plugin-root>/skills/mr-review/SKILL.md`. The normal path is the head branch; this
file is what to do when it is gone or the forge CLI is not there.

**The merge commit.** `gh pr view <url> --json mergeCommit` and `glab mr view <url> -F json`
(`merge_commit_sha`) both report it. Check it out instead of the head branch. The diff depends on how it
landed: `git diff <merge>~1 <merge>` after a rebase or a squash merge, `git diff <merge>^1 <merge>` after a
merge commit. When the shape is unclear, `gh pr diff <url>` or `glab mr diff <url>` is the authority and the
checkout is the merge commit either way.

**Without `forge.sh`.** `gh pr view <url> --json title,body,headRefName,baseRefName,closingIssuesReferences,comments`,
or `glab mr view <url> -F json` together with `glab mr view <url> --comments`.

**Fetching.** `git fetch origin <head>` in a plain session; `git-guard fetch` on a worker, where the guard
owns the remote. The checkout is `git worktree add --detach <review-dir>/tree FETCH_HEAD`, except on a
worker, where the clone is yours alone: check out in place and `tree` is the clone itself.

**The inventory** takes `--toolset <toolset.md>` when the repo has one, and is otherwise run bare.

An empty diff is not a review: report that the MR carries no change against `<base>` and stop.
