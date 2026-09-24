# Entry points and task mode

Read alongside the preconditions of `<plugin-root>/skills/architecture-docs/SKILL.md`. Two entry points,
one procedure. They differ only in whether a human is reachable.

| path | how it starts | human | write scope enforced by |
|---|---|---|---|
| user-invoked | `/claude-factory:architecture-docs [bootstrap\|audit] [scope]` in a session whose cwd is a product repo clone | present, you interview | the skill, advisory |
| task | a research task whose `## Context` names this skill; `block-research` drives the session mechanics | absent, see below | the policy-guard carve-out (`docs/**`, `CONTEXT.md`, `README.md`) |

## Task mode, the one path with no human

It is the only path that leaves `TODO(question)` lines behind, and the deltas on `block-research` are:

- You do write into the product repo, `docs/**`, `CONTEXT.md` and `README.md` only, and you do deliver a
  branch and an MR, which `block-research` otherwise never does (ADR-0016).
- Every question the interview would have asked is a `TODO(question)` where it belongs **and** is repeated in
  the MR description with its options and your recommendation, so the human answers in one place.
- `product/` stays a skeleton: the files exist with their headings and one TODO question per section. Vision,
  goals, metrics and stories are never inferred from code.
- Self-report `review`, with `mr_url` set instead of `null`.

When an audit hits open points only a human can settle, do not settle them alone. Run two passes: the
human writes the answers into the task's `## Context`, then a task-mode pass consumes them as settled input.
