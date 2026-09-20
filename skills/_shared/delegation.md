# Delegation

A session may hand subtasks to subagents; it stays the orchestrator and the only writer of the state repo.
The rules of a spawn are in `<plugin-root>/skills/_shared/rules.md`, which
`<plugin-root>/bin/agent-brief.sh <agent>` prints at the top of every brief together with that agent's own
memory. Prepend its output to the brief you write.

| agent | for |
|---|---|
| `worker-explorer` | read-only recon: blast radius, references, existing tests; cheap, fan out in parallel |
| `worker-test-author` | characterization or red tests for one area; parallel over disjoint test files |
| `worker-implementer` | one well-scoped implementation step |
| `factory-block-tests` | a coordinator's tests phase for one block: analysis, red tests, `## Handoff` |
| `factory-block-implement` | a coordinator's implement phase for one block: the code, no MR, no self-report |
| `factory-block-implement-medium` | the same phase at `complexity: high`, picked by `model-for.sh --agent` |
| `factory-reviewer` | a coordinator's review of the whole diff before the MR, read-only (ADR-0053) |
| `mr-issue-linker` | the open issues a finished change solves or touches, for the MR description |
| `mr-reviewer` | one merge request judged against its issue, read-only (ADR-0054) |

Model and effort live in the agent definitions, not here.

- A subagent's "it works" is a claim, not evidence: rerun the proving command yourself before recording it.
- Duplication recon is `worker-explorer` spawns (haiku, read-only) over what
  `<plugin-root>/bin/dup-check.sh` printed, at most eight, one candidate each, never the reviewer's own search.
- Writing the MR stays here; only the issue lookup behind its `Issues` line goes to `mr-issue-linker`.
- The **task-wide** test lock: the coordinator arms it with `state-report.sh --set-phase implement`, and from
  then on the guard refuses every write to a test file of that task, for the session and its subagents alike.
  Policy hooks apply to subagent tool calls; delegation is not a way around them.
- Each block agent runs only the tests it wrote; the coordinator reruns the whole suite over the merged diff.
- At most **five** block agents run concurrently; a wider wave queues.
- A subagent's report may end with one `## Lessons` line (Why plus evidence) about its own craft, which the
  calling session turns into a proposal per `<plugin-root>/skills/_shared/knowledge-review.md`.
