---
name: issue-create
description: Drafts an issue with the human, checks the open issues for a duplicate, and files it through bin/issue-create.sh, which adds the ai-drafted label. Use when the human asks to file an issue against a registered repo
---

# issue-create

Plugin root: `${CLAUDE_PLUGIN_ROOT}`.

Human-invoked only: no other skill calls this one. The issue script, `${CLAUDE_PLUGIN_ROOT}/bin/issue-create.sh`,
is the only code that creates an issue. Every issue it creates carries the **ai-drafted label**, the forge label
`ai-drafted`, the one sanctioned exception to the attribution rule, so a reader can tell a drafted issue from a
human one. Nothing else in the title or body says who or what wrote it.

## Procedure

1. **Settle the repo-key.** It is a key of `$WORK_DIR/state/repos.yml`. Ask when the human did not name one.
2. **Look for a duplicate.** In the clone at the key's `path:` in repos.yml, list the open issues with the forge
   its origin names, `gh issue list --state open --limit 100` for github.com and `glab issue list --per-page 100`
   for every other host. Name any issue that looks like the same problem, with its number and title.
3. **Draft.** A title that says the problem in one line, and a body with what happens, what should happen and
   how to reproduce it. Write the body to a file in your scratchpad directory, never inline in a command.
4. **Show the draft** (title, body, repo-key and any likely duplicate) and wait for the human's yes. A change
   request goes back to step 3.
5. **File it.**

   ```sh
   sh ${CLAUDE_PLUGIN_ROOT}/bin/issue-create.sh <repo-key> --title "<title>" --body-file <scratchpad>/issue.md
   ```

   Report the URL it prints. On exit 1 report its reason; do not fall back to `gh issue create` or
   `glab issue create`, which the policy guard denies without the label.
