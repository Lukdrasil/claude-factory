---
name: auto
description: Start factory auto on one task in a herdr pane - the herd with one interactive step, two solution sessions the human picks between, then the grill, decompose, the blocks and the task MR run by recommendation. Use when the user says auto, factory auto, or wants a task solved with one pick and no further gates. Requires HERDR_ENV=1 for the sessions; without it the commands are printed.
---

# auto

`/claude-factory:auto <the task in words> [--repo <key>]` or `/claude-factory:auto <T-id>`: the same as
`/claude-factory:factory auto`, as its own entry. Read
`${CLAUDE_PLUGIN_ROOT}/skills/factory/references/auto.md` and follow it; the herd mechanics behind it are
`${CLAUDE_PLUGIN_ROOT}/skills/factory/references/herd.md` and `${CLAUDE_PLUGIN_ROOT}/skills/herdr/SKILL.md`.

Check first:

```sh
test "${HERDR_ENV:-}" = 1
```

Outside a herdr pane the solution, grill, decompose and block sessions cannot be opened: say so, and run the
lane with the printed `cd ... && claude ...` lines the human starts by hand (`references/herd.md`, Without
herdr).

## What happens

1. **Intake and create**, as the Start of `references/solve.md`, when the argument is words; a `<T-id>` is
   reclaimed instead. One task per start, never a batch.
2. **The loop**: `sh ${CLAUDE_PLUGIN_ROOT}/bin/solve-next.sh <T-id> --auto`, do what it prints, verify its
   `Completion:` line, run it again, until step 16. Arm `herd-watch.sh <T-id> --interval 60` through the
   Monitor tool after the first dispatch and say that this session is the monitor of `<T-id>`.
3. **The one ask**: step 4a shows the two solutions and asks which; the pick is the consent for the rest.
4. **Everything else** runs by recommendation (`${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-decision.md`) up to
   the task MR, whose body lists every decision; the human reviews it and the watcher turns their review into
   fix rounds until it is merged.

The task needs a registered repo with a `crap` row in its toolset; `solve-next.sh --auto` stops at step 4a
and says so otherwise.
