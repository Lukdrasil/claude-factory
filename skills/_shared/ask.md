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
   text), several answers in one message one per line, typed in the terminal or relayed from the browser. Both are
   the human's input.
4. **Close** the ask once that turn has settled every question in it:
   `sh <plugin-root>/bin/ui-ask.sh --session <session_id> --close <ask>`. `Qn more` or a partial round leaves
   it open: answer, and write the ask again under the same id when its questions changed.

## The relay

`bin/ui-relay.sh`, one per machine in its own herdr tab, is how a browser answer becomes that next user turn.
It reads each answer file after the seq in `sessions/<sid>/delivered` and types it verbatim, no prefix, into
the pane of `session.md` with `herdr agent prompt --wait`, one answer per call, in seq order. It types only
once the pane has held `idle` or `done` for the settle time (2 s, `--settle`) since its last state change, and
only while `herdr agent get` still reports the session id; then it records the seq in `delivered`, so a
restarted relay resumes where it stopped. A herdr stall after the submit counts as typed, never as a retry.

A held answer stays queued and `sessions/<sid>/relay` holds one line `<seq> <reason>`, removed once the queue
is empty:

- `blocked`: the pane sits at a dialog. The relay never answers it; the human does, in the pane.
- `gone`: the pane is missing, or reports another session id or none.
- `prompt-failed`: herdr refused the prompt before sending it.

Every pass also writes `sessions/<sid>/agent` for every session, answers queued or not: the pane's
`agent_status`, or `gone` as above. The page reads it as the session's liveness.

`--once` makes one pass over every session, up to the first hold or working pane, and exits.
