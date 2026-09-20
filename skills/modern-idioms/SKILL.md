---
name: modern-idioms
description: Current idiom and inefficient-construct check for every member written, per stack. Use while implementing, at the moment you write or edit a member, and when a review asks whether code is idiomatic.
---

# Modern idioms

Two lists decide every member you write: the **replacements** (an old construct and the modern one that
superseded it) and the **inefficient idioms** (a construct that compiles and passes tests but allocates,
boxes, blocks or scales badly, with its fix). Both live per stack under `references/<stack>/`. A match
against the second list is a **hit**: a defect, fixed in the members the diff touches.

## Rules

- **Match the surrounding file first.** A file written entirely in an older style stays consistent inside one
  change; the modern construct goes into new files and new members. A wholesale rewrite of an existing file is
  a refactor task of its own.
- **The analyzer decides ties.** When the reference names an analyzer rule for an idiom and the project runs
  that analyzer, the rule's verdict wins over the reference's prose.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context. While implementing,
   read `${CLAUDE_SKILL_DIR}/references/<stack>/inefficient.md` when it exists: the defects list, one table
   row per item. In a review, read the `README.md` beside it too, the replacements list. The `details.md`
   beside them carries the snippet and the sources per row code; open it only for a row you need to see in
   full. Without a toolset or a reference, apply the rules above with the language's own documentation.
   Done when you know which reference, if any, applies.
2. **Read the project's language and runtime version** from its project files. That version bounds every
   replacement: a row above it stays out, and the version stays where the project set it. Done when you can
   say which rows apply to this project.
3. **Write the change in the modern idiom** for every new or edited member, within the version from step 2:
   the language's current construct, not the one it superseded. The review walks the replacements list over
   the diff; a superseded construct it finds is a suggestion with its row code.
4. **Walk the inefficient idioms over the diff.** Every member the diff touches is checked against the list.
   Each hit is fixed in place; a hit whose fix would widen the change beyond the task, or a hit in a member
   the diff leaves untouched, goes into the progress file with its row code and the reason. Done when every
   hit is fixed or recorded.

## Review output

When the skill runs as a review rather than while implementing, report in this shape:

```
# Idiom review
| file:line | construct | replacement | rule | action |
```

One row per hit, `action` is `fixed`, `recorded` or `kept` with a reason. No rows means the diff is clean.
