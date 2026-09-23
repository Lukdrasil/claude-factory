# Asking the human

Every question a skill puts to the human goes through this file: a round, a confirm or a notice. It is the one
place that names the tool, so the two modes below stay the only two.

Read `ui:` from `$WORK_DIR/state/factory.yml`. Absent means `off`.

## `ui: off`, or outside herdr

With `ui: off`, or when `HERDR_ENV` is not `1`, ask with AskUserQuestion, as every skill always did.

## `ui: docker` in herdr

With `ui: docker` and `HERDR_ENV=1` the terminal and the browser answer the same **ask**, so the session never
calls AskUserQuestion:

1. **Print** the ask in the terminal, in the round format of `skills/grill/SKILL.md`: numbered questions,
   lettered options, your recommendation. A confirm is one question with the options yes and no; a notice has
   no options.
2. **Write** the same markdown behind a frontmatter through `bin/ui-ask.sh`, with the session_id of your
   identity line, and print the URL it returns:

   ```sh
   sh <plugin-root>/bin/ui-ask.sh --session <session_id> <<'EOF'
   ---
   ask: <id, [a-z0-9-]+, unique in this session>
   task: <T-NNN, or none>
   flow: <solve, init, curate, ...>
   step: <the step line, e.g. Step 4 of 16: grill T-204>
   status: open
   ---

   <the markdown you printed>
   EOF
   ```

3. **End your turn.** The answer arrives as the next user turn in the grill shorthand (`Q3 A`, `Q3 ok`, free
   text), typed in the terminal or relayed from the browser. Both are the human's input.
4. **Close** the ask once that turn has settled every question in it:
   `sh <plugin-root>/bin/ui-ask.sh --session <session_id> --close <ask>`. `Qn more` or a partial round leaves
   it open: answer, and write the ask again under the same id when its questions changed.
