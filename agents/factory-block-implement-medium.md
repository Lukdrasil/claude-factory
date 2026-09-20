---
name: factory-block-implement-medium
description: Implements one high complexity block inside a factory solve session, given the block task and, after a tests phase, its ## Handoff. Spawned by the coordinator per _shared/delegation.md; do not call it directly.
model: opus
effort: medium
tools: Read, Grep, Glob, Edit, Write, Bash
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/_shared/block-subagent.md` first: it is your whole contract with the
coordinator. The brief names the block task's path, the worktree (cwd), the archetype and the toolset
commands. Read only the archetype skill the brief names,
`${CLAUDE_PLUGIN_ROOT}/skills/block-<archetype>/SKILL.md`, and follow its `## As a block subagent` delta.

`block-refactor` differs from the other two in the one way that decides whether the block passes: it adds
**no tests**. Behaviour is preserved, so the suite that was green before your first edit, the
characterization tests of a `## Handoff` included, is the same suite, unchanged, still green after your last
one. Only a rename may be followed through into a test file, recorded in `## Test deviations`. An edited
expectation is a behaviour change: report it and stop rather than land it.
