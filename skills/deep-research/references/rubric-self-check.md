# Rubric self-check

A calibration set. The acceptance of issue #67 asks for three assignments → three different model × effort combinations;
this set gives four, so that every tier is covered.

| # | assignment | B | A | C | K | S | tier → model × effort |
|---|---|---|---|---|---|---|---|
| 1 | "Which .NET version does `ClaudeOs.Dashboard` target?" | 0 | 0 | 0 | 0 | **0** | S0 → haiku |
| 2 | "How does the controller signal task status, and what would have to change for a task to be pausable?" | 1 | 1 | 2 | 1 | **5** | S1 → sonnet × high |
| 3 | "Why does the watchdog sometimes mark a running research task as `stalled`, and what are the options for fixing it?" | 2 | 1 | 2 | 2 | **7** | S2 → opus × medium |
| 4 | "Stay with git as the state repo store, or move to a database?" | 3 | 2 | 3 | 3 | **11** | S3 → opus × high |

Why those scores:

1. One field in one `.csproj`, a single reading, nothing rests on it. No escalation.
2. Two sub-questions (state today / what to change), "pausable" is slightly under-specified, the context is
   `entrypoint.sh` + the task format + the dashboard (C=2), the impact is one task. The escalation `C ≥ 2 → ≥ S1`
   is already satisfied by the sum.
3. Three connected areas (watchdog, signalling, the `research` archetype), context spanning dozens of files,
   and a fix that reaches into several tasks.
4. Mapping the terrain with several legitimate readings, context spanning the whole system plus external sources, and above all
   `K = 3` — an irreversible choice of store. The escalation `K = 3 and B ≥ 2 → S3` pins the tier even when a
   scorer reads the breadth and the context one notch lower (S = 8 was the observed drift).

**How to repeat the self-check:** take the four assignments from the first column, run **only step 1 of the
Procedure** on each (score it and print the block, do not spawn a subagent) and compare the result with the table. If the
tiers match, the rubric is calibrated. If they diverge, fix the rubric or the table — never just the
reasoning.

## Why four agents

Effort is `effort:` in the agent definition and cannot be passed at call time, so each model by effort
combination is a ready-made variant in `agents/`. A new combination is a new file, not new code.
