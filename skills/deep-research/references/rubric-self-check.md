# Rubric self-check

A calibration set. The acceptance of issue #67 asks for three assignments → three different model × effort combinations;
this set gives four, so that every tier is covered.

| # | assignment | B | A | C | K | S | tier → model × effort |
|---|---|---|---|---|---|---|---|
| 1 | "What wall-clock cap does the toolset `test` binding of claude-factory put on the whole suite?" | 0 | 0 | 0 | 0 | **0** | S0 → haiku |
| 2 | "How does `state-report.sh` decide which status an agent may set, and what would have to change for a task to be pausable?" | 1 | 1 | 2 | 1 | **5** | S1 → sonnet × high |
| 3 | "Why does the policy guard sometimes deny a write inside a block worktree, and what are the options for fixing it?" | 2 | 1 | 2 | 2 | **7** | S2 → opus × medium |
| 4 | "Keep the state repo as a git clone every session pushes to, or move task state to a database?" | 3 | 2 | 3 | 3 | **11** | S3 → opus × high |

Why those scores:

1. One row in one `toolset.md`, a single reading, nothing rests on it. No escalation.
2. Two sub-questions (the rule today / what to change), "pausable" is slightly under-specified, the context is
   `state-report.sh` + the status set `task-new.sh` validates + the self-report section of every archetype
   skill (C=2), the impact is one task. The escalation `C ≥ 2 → ≥ S1` is already satisfied by the sum.
3. Three connected areas (the policy guard, the layout resolution in `lib-tasks.sh`, block and parent
   ownership), context spanning dozens of files and their test suites, and a fix to the write-safety boundary
   that reaches every task.
4. Mapping the terrain with several legitimate readings, context spanning the whole plugin plus external
   sources, and above all `K = 3`: an irreversible choice of store. The escalation `K = 3 and B ≥ 2 → S3` pins
   the tier even when a scorer reads the breadth and the context one notch lower (S = 8 was the observed drift).

**How to repeat the self-check:** take the four assignments from the first column, run **only step 1 of the
Procedure** on each (score it and print the block, do not spawn a subagent) and compare the result with the table. If the
tiers match, the rubric is calibrated. If they diverge, fix the rubric or the table — never just the
reasoning.

## Why four agents

Effort is `effort:` in the agent definition and cannot be passed at call time, so each model by effort
combination is a ready-made variant in `agents/`. A new combination is a new file, not new code.
