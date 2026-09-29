# Rubric self-check

A calibration set. The acceptance of issue #67 asks for three assignments → three different model × effort combinations;
this set gives four, so that every tier is covered.

| # | assignment | B | A | C | K | S | tier → model × effort |
|---|---|---|---|---|---|---|---|
| 1 | "What wall-clock cap does the toolset `test` binding of claude-factory put on the whole suite?" | 0 | 0 | 0 | 0 | **0** | S0 → haiku |
| 2 | "How does `worktree-add.sh` pick the base branch of a block, and what would have to change so a block can branch from another block?" | 1 | 1 | 1 | 1 | **4** | S1 → sonnet × high |
| 3 | "How does `state-report.sh` decide which status an agent may set, and what would have to change for a task to be pausable?" | 2 | 2 | 2 | 2 | **8** | S2 → opus × medium |
| 4 | "Keep the state repo as a git clone every session pushes to, or move task state to a database?" | 3 | 2 | 3 | 3 | **11** | S3 → opus × high |

Why those scores:

1. One row in one `toolset.md`, a single reading, nothing rests on it. No escalation.
2. Two sub-questions in one area (the rule today / what to change), "branch from another block" leaves small
   gaps convention fills, the context is `worktree-add.sh` and the few files it reads (C=1), and the change
   serves one task. No escalation.
3. Connects the transition table in `state-report.sh` with the status set `task-new.sh` validates and the
   owner rules of the policy guard, "pausable" has several readings (a new status, a suspend and resume, a
   released owner), the context spans several scripts and every archetype's self-report section, and the
   change reaches the task lifecycle every task relies on. The escalation `C ≥ 2 → ≥ S1` is already
   satisfied by the sum.
4. Mapping the terrain with several legitimate readings, context spanning the whole plugin plus external
   sources, and above all `K = 3`: an irreversible choice of store. The escalation `K = 3 and B ≥ 2 → S3` pins
   the tier even when a scorer reads the breadth and the context one notch lower (S = 8 was the observed drift).

**How to repeat the self-check:** take the four assignments from the first column, run **only step 1 of the
Procedure** on each (score it and print the block, do not spawn a subagent) and compare the result with the table. If the
tiers match, the rubric is calibrated. If they diverge, fix the rubric or the table, never just the
reasoning.

## Why four agents

Effort is `effort:` in the agent definition and cannot be passed at call time, so each model by effort
combination is a ready-made variant in `agents/`. A new combination is a new file, not new code.
