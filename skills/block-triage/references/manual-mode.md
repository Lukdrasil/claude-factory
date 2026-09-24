# block-triage — manual mode

Started by hand in a Claude Code session with an issue URL or `<repo-key>#<number>`, cwd a clone of the state repo.
The procedure in `SKILL.md` applies with these deltas:

- **No triage task.** Skip steps 1 and 8, so no progress snapshot and no self-report; the run ends when the draft task
  is finished. In `## Internal` omit the `- triage:` line: there is no triage task to pair with.
- **`<key>` comes from `repos.yml`.** Look the repo up by host and slug; if it is not there, ask the human which
  `repo-key` the task belongs under before writing anything. Only an issue from manual mode can point outside
  `repos.yml` — when it does, say so under `## Internal`, so a fresh session knows the source is not an adopted repo.
- **Reading the issue.** `<plugin-root>/bin/forge.sh` ships with the plugin and works wherever `sh` and a
  logged-in gh/glab exist. With no `sh` — a standalone Windows install — use
  `gh issue view <url> --json number,title,body,labels,state,milestone,comments`, or
  `glab issue view <url> -F json` and `glab issue view <url> --comments`, and look at attachments through the links
  in the issue. The rest of step 2 stands: read every comment and attachment, and write what they show into the draft.
