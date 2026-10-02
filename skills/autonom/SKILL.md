---
name: autonom
description: Start factory autonom on one task in a herdr pane - the auto lane with no pick and no question, the two solution sessions compared and chosen by the monitor, every decision with no recommendation analysed and taken by the session, up to the task MR the human reviews. Use when the user says autonom, factory autonom, or wants a task solved with no gate before the MR. Requires HERDR_ENV=1 for the sessions; without it the commands are printed.
---

# autonom

`/claude-factory:autonom <the task in words> [--repo <key>]` or `/claude-factory:autonom <T-id>`: the same as
`/claude-factory:factory autonom`, as its own entry. Read
`${CLAUDE_PLUGIN_ROOT}/skills/factory/references/auto.md`, its `## autonom` section last, and the
`## Autonomous` section of `${CLAUDE_PLUGIN_ROOT}/skills/_shared/auto-decision.md`; follow them. The herd
mechanics behind it are `${CLAUDE_PLUGIN_ROOT}/skills/factory/references/herd.md`.

Check first:

```sh
test "${HERDR_ENV:-}" = 1
```

Outside a herdr pane the sessions cannot be opened: say so, and run the lane with the printed
`cd ... && claude ...` lines the human starts by hand.

## What happens

1. **Intake and create**, as the Start of `references/solve.md`, when the argument is words; a `<T-id>` is
   reclaimed instead. One task per start.
2. **The loop**: `sh ${CLAUDE_PLUGIN_ROOT}/bin/solve-next.sh <T-id> --autonom`, do what it prints, verify
   its `Completion:` line, run it again, until step 16. Arm `herd-watch.sh <T-id> --interval 60` through the
   Monitor tool after the first dispatch and say that this session is the monitor of `<T-id>`.
3. **No ask**: the two solutions are compared and one chosen by you, the grill, plan-check and decompose
   decide every question themselves, a blocked block is answered by its recommendation or by an analysis.
4. **What reaches the human**: a destructive or outward-facing choice (the third case of the decision rule),
   a session's permission dialog, and the task MR, whose body lists every decision marked by who took it.

The task needs a registered repo with a `crap` row in its toolset; `solve-next.sh --autonom` stops at step
4a and says so otherwise.
