# Model guidance

How a brief is written changes with the model it targets (T-007). The coordinator picks the model
(`<plugin-root>/bin/model-for.sh`); the brief a subagent gets should match what that model is good at, not repeat the same
prose at every tier.

## haiku
Cheap and literal. The brief is a numbered checklist of concrete steps (file, command, expected output) with
no step left to inference. Do not ask haiku to weigh options; decide yourself and hand over the decision, not
the question. Output shape: short and structured (a list, a table, a status line), never prose. Never ask haiku
to reason before acting: that wastes the budget it was picked to save. Avoid ambiguity and multi-step judgment
calls.
Example: "Run `test-filter T-091-01`. Paste the last 5 lines and the exit code. Nothing else."

## sonnet
Text work that is not code: research at ordinary scope, summaries, section writing, report rendering. The
brief states the goal, the constraints and the done criterion, and leaves the path to the model. Judgment is
expected on ordinary tradeoffs, but not on scope or contract changes; those come back as a question, not a
guess. Output shape: the document asked for plus a short note of what was read. Never for generated code:
every code-writing agent runs on opus.
Example: "Write the `## Components` section for project X from the extractor's JSON. Cite the file for every claim."

## opus
Every agent that writes code (`implementer`, `step-implementer`, `test-writer`) and
genuine judgment: tests-phase analysis, review, anything at `complexity: high` or a retry. Generated code
never runs on a cheaper model; the implement phase takes effort `low`, judgment takes `high`. The brief
states the problem and the constraints, not the steps, and expects opus to find the path itself, asking rather
than guessing when the spec runs out. Output shape for judgment: a decision or analysis with the reasoning
shown. For code: the diff plus a short report of what ran and its exit code. Ask for reasoning first on a judgment call (a design
choice, a review verdict, a red-test design); for an implement step let it start working.
Example: "Design the red tests for `T-091-01` from its `## Acceptance`. State what each test proves and why it
currently fails for the right reason."
Example: "Make the red tests in `block/T-091-01` green. Do not touch `## Acceptance`. Report the commands you ran."

`model-for.sh --agent` picks the implement agent: `complexity: high` gets `implementer-senior`
(effort medium), everything else `implementer` (effort low). Phase and complexity decide it; the
attempt ladder does not, since escalation moves the model and `--agent` the agent. The model of a code-writing
agent is fixed in its definition and is opus; `model-for.sh` agrees with it at every tier.

## No `<model>-strong` twin
`model-for.sh` prints `haiku|sonnet|opus` and nothing else, except under `--agent`, where it prints an agent
name instead: `complexity: high` or `attempt>=1` escalates the **model** to opus, never effort. `effort:` in the agent file is fixed and cannot be passed per spawn, so a
strong twin would need an agent of its own (`researcher-s0` to `researcher-s3`).
