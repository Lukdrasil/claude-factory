# factory research

`factory research <line>`: one research question of the human's, the line `research[ <keys>][ branch
<branch>]: <text>` the UI's New request box sends as Research, `<keys>` none or more registered repository
keys joined by `,`. The CEO dispatches this session (`session-monitor.sh --step research`); it runs in the
state clone as `FACTORY_ROLE=research`, unit `research-<n>`. You answer the question with a report in the
state repo and change no product code.

## Steps

1. **Research** with `${CLAUDE_PLUGIN_ROOT}/skills/deep-research/SKILL.md`, the topic `<text>`, `--repo=<key>`
   with exactly one key and `--repo=none` otherwise. Every key is a registered clone, the `path:` of its
   `repos.yml` line, read only: `git -C <clone> fetch`, `log`, `show`, `diff` and `ls-tree`, never a checkout,
   pull, reset or build, since the clone is the human's checkout. With `branch <branch>` the assignment is that
   branch as the remote has it: `git -C <clone> fetch` first, then `origin/<branch>` read against the key's
   `default_branch`, `git -C <clone> diff <default_branch>...origin/<branch>` and its `log`. Step 6 of that
   skill, the summary to the human, is the notice of step 2 here.
2. **Tell the human** through `${CLAUDE_PLUGIN_ROOT}/skills/_shared/ask.md`, one notice with flow `research`
   and task `none`: the answer in 3 to 6 sentences and the report's path in the state repo.
3. **Report** to the CEO, `<n>` from your `FACTORY_UNIT`: `herdr agent prompt ceo "research <n> done <path>"`,
   or `herdr agent prompt ceo "research <n> stopped <reason>"` when no report was written. A refusal means the
   CEO sits at a dialog: send it again, up to 3 times, 10 seconds apart, then go on.
4. **Close your own tab**: `herdr tab close "$HERDR_TAB_ID"`. This ends the session.
