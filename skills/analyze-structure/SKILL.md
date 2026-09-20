---
name: analyze-structure
description: Quality-kit phase 0. Analyze a repo's structure against the modular-monolith model, measure analyzer debt, propose restructuring (read-only report), following the reference for the toolset's stack.
disable-model-invocation: true
model: opus
---

# Structure analysis and restructuring proposal

The deliverable is a **proposal**, a markdown report: a disposition for every project (keep / rename /
split / merge / extract as module) with its target place, the target module list with each module's public
surface, an extraction order, the measured analyzer debt with the recommended escalation, and phases that
each end on a green build. Restructuring itself happens only after a human approves the proposal.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context (the `stack: <value>` line in the toolset
frontmatter). No toolset section in the context means the clone is not registered: say
`no toolset in context — run factory add-repo first` and stop.
If `${CLAUDE_SKILL_DIR}/references/<stack>/` does not exist, say `no <stack> reference for
analyze-structure yet` and stop. Done when the stack is named and its reference folder exists.

### 2. Follow the stack guide

Read `${CLAUDE_SKILL_DIR}/references/<stack>/README.md` and follow its steps in order: the project
inventory, the dependency map, the debt measurement, the confrontation with the target model, the proposal.
Done when each step's own "Done when" holds.

### 3. Save and summarize

Save the report as `docs/restructuring-proposal.md` in the target repo (create `docs/` if missing) unless
the user names another location, and summarize the main dispositions to the user. Done when every project
has a disposition, every dependency finding has a resolution in the proposal, and each phase can be
executed independently, ending green.
