---
name: analyzer-fix-example
description: Wrong/right snippet pair for a given analyzer or linter rule ID, served from the example library of the toolset's stack.
disable-model-invocation: true
model: sonnet
---

# Correct-fix example for an analyzer rule

The output always has three parts: the **wrong snippet** (minimal code that triggers the rule), the
**right snippet** (the idiomatic modern fix), and **one concrete sentence** naming the principle the fix
serves (SOLID, DIP, determinism, async correctness, type safety). Add a layer note whenever the fix differs
per architectural layer. The stack reference carries an example library, one file per rule: a served
example comes from the library when the file exists and grows the library when it does not.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context (the `stack: <value>` line in the toolset
frontmatter). No toolset section in the context means the clone is not registered: say
`no toolset in context — run factory add-repo first` and stop.
If `${CLAUDE_SKILL_DIR}/references/<stack>/` does not exist, say `no <stack> reference for
analyzer-fix-example yet` and stop. Done when the stack is named and its reference folder exists.

### 2. Follow the stack guide

Read `${CLAUDE_SKILL_DIR}/references/<stack>/README.md` and follow its steps in order: the library lookup,
the rule's intent, the layer, the fix in current idioms, proportional verification, the new example file.
Done when the guide's own "Done when" holds.

## Done when

The answer contains the wrong snippet, the right snippet, the principle sentence and, where the fix differs
per layer, a note naming the layer it applies to. A code that had no example has one now, saved in the target
repo (the skill folder ships read-only inside the plugin). The fix changes code; when the finding is legacy
debt rather than new code, say so and
offer the freezing techniques the stack guide lists for the user to choose from.
