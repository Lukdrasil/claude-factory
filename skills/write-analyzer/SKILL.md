---
name: write-analyzer
description: Write a custom build-time analyzer for a rule the existing analyzers cannot express, with red-first tests and configured thresholds, following the reference for the toolset's stack.
disable-model-invocation: true
model: opus
---

# Writing a custom analyzer

A build-time rule for what neither an existing analyzer nor an architecture test can express: a rule that
needs syntax or semantic context (what is an aggregate, what is injected). The analyzer's message is the
interface for the agent and the junior alike: what is wrong and the specific change that fixes it. Tests go
red before green, and thresholds live in the repo's analyzer configuration, so a different strictness in a
different layer needs no recompilation.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context (the `stack: <value>` line in the toolset
frontmatter). No toolset section in the context means the clone is not registered: say
`no toolset in context — run factory add-repo first` and stop.
If `${CLAUDE_SKILL_DIR}/references/<stack>/` does not exist, say `no <stack> reference for
write-analyzer yet` and stop. Done when the stack is named and its reference folder exists.

### 2. Follow the stack guide

Read `${CLAUDE_SKILL_DIR}/references/<stack>/README.md` and follow its steps in order: confirm an analyzer
is the right tool, the diagnostic, the thresholds, the red-first tests, the wiring and severity, the run
on real code. Done when the guide's own "Done when" holds.

## Done when

The tests are green having been red first, the analyzer is wired, severity and thresholds are configured
where the guide puts them, the rule has its row in the repo's analyzer table, and the target build is green
or its findings are frozen with a baseline technique.
