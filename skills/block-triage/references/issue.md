# Reading the issue and writing back

## Reading

```sh
<plugin-root>/bin/forge.sh issue <url> --assets ../issue-assets
```

The script picks gh or glab and the hostname from the URL. Which instances are signed in is in CLAUDE.md
under `## Forge`; `forge.sh hosts` lists them too. If the issue cannot be read, missing auth or a 404, that
is `blocked` with a question: a draft comes from the issue text, never from the title alone.

**Attachments are part of the assignment.** `--assets` downloads the issue's images and files into
`../issue-assets`, next to the state clone and never inside it, so they cannot end up in a commit, and prints
their paths under `--- assets ---`. View every image with the **Read** tool and read the text attachments,
then write what they show into the draft: it has to be self-contained, because the implementation session
works without the attachments. Note any `asset skipped:` lines under `## Internal`, so a human knows part of
the context is missing; anything you fetch by hand to make up for one goes into `../issue-assets` too.

Always read the comments and the milestone. A clarification, a change of assignment or "this no longer
applies" tends to live in the comments rather than the original text, and on a conflict the newer comment
wins. Record what you went by, and the milestone as deadline context, under `## Internal`.

## Writing the triage back

Only when the source is a forge issue, and only the draft's `## Issue update` section, nothing else. Read the
issue's current body; if it does not yet contain `**Triage <new-id>**`, append a blank line, `---`, a line
`**Triage <new-id>**` and that section under it.

Prepare the new body in a file **next to** `state/`, for example `../issue-body.md`, so it cannot end up in a
commit, and write it:

```sh
gh issue edit <url> --body "$(cat ../issue-body.md)"
glab api --hostname <host> -X PUT "projects/<url-encoded-project>/issues/<iid>" -f "description=$(cat ../issue-body.md)"
```

The body goes in inline on both forges: the guard refuses every file-valued flag on a write, because the CLI
runs as the uid that reads `/auth/forge` and would publish the credential store into the issue.

A failed write is **not fatal**: note it in the progress file under `## Remaining` and carry on. The draft
detail page has a "triage to issue" button using the same marker, so a human can push it through and nothing
gets duplicated.

The issue must never get its own text or claude-os internals back: anything that would be duplicated or
meaningless there goes under `## Internal`, not `## Context`.
