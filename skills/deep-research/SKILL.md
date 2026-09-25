---
name: deep-research
description: Deep research with automatic model and effort selection. A rubric picks the tier, the session prints the score and spawns one subagent, and the output is a raw report in the state repo. Use for "look into", "find out" and "compare the options".
---

# deep-research

Answer a research assignment with one subagent and leave a **raw report in the state repo**. This session
picks the performance with the rubric.

## Preconditions

- The **state clone** is cwd if it holds `repos.yml`, otherwise `$WORK_DIR/state`; if neither, stop and say so.
- You write **only** into the state clone; product repos are read-only.

## Arguments

    /deep-research <topic> [--tier=S0|S1|S2|S3] [--repo=<key>|none]

`--tier` overrides the rubric, reported as `overridden by user`; `--repo` the destination.

## Rubric

Four dimensions, each **0 to 3**, scored by the assignment.

- **B** breadth: 0 one question, one source. 1 a few sub-questions in one area. 2 several areas to connect.
  3 mapping terrain.
- **A** ambiguity: 0 one reading. 1 small gaps convention fills. 2 several readings to name. 3 unclear what to ask.
- **C** context: 0 one file. 1 a handful of files or sources. 2 dozens of files, several repos. 3 the whole
  system plus external sources.
- **K** criticality: 0 informative. 1 one task. 2 the architecture or several tasks. 3 irreversible.

`S = B + A + C + K` picks the agent:

| S | tier | agent | model × effort |
|---|---|---|---|
| 0 to 3 | **S0** | `researcher-s0` | haiku |
| 4 to 6 | **S1** | `researcher-s1` | sonnet × high |
| 7 to 9 | **S2** | `researcher-s2` | opus × medium |
| 10 to 12 | **S3** | `researcher-s3` | opus × high |

**Escalation**, after the sum and only ever upward: `K = 3` gives at least **S2** (opus × medium); `K = 3`
with `B >= 2` gives **S3**; `C >= 2` gives at least **S1**. Haiku cannot carry the context batching.

Calibration: `references/rubric-self-check.md`.

## Steps

1. Score the assignment and print exactly this, filled in; without it the choice is invisible:

   ```
   rubric: B=<n> A=<n> C=<n> K=<n> -> S=<sum> -> <tier> (<model> × <effort>)
   B: <half a sentence why>   A: <half a sentence why>
   C: <half a sentence why>   K: <half a sentence why>
   escalation: <rule, or "none">
   ```

2. Work out the destination per `references/destination.md` and say the path.
3. Spawn one subagent, the one for the tier, with the prompt of `references/prompt.md`. One, never two.
4. Check the report exists there with its sections, filling in what is missing.
5. Commit the report in the state clone per `references/destination.md` (through `bin/state-commit.sh`; the push
   runs in the background).
6. Give the user 3 to 6 sentences and the path, never the report pasted into the chat.

**Done when** the report is committed in the state clone and the user has the path. Research
**never changes product code**: follow-up work is proposed in the report's `## Conclusion`, not committed.
