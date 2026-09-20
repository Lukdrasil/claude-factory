---
name: add-slice
description: Scaffold a vertical slice (use case) as one internal file inside an existing module, following the reference for the toolset's stack.
disable-model-invocation: true
model: sonnet
---

# Adding a vertical slice

A slice is one use case as one internal file: command, handler, validator and endpoint together, deletable
with a single `rm`. It lives in the module's Features, is registered inside the module, and reaches other
functionality only through the domain and the module's own ports. Split into several files only past ~200
lines, and treat reaching that threshold as a sign the use case is too big.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context (the `stack: <value>` line in the toolset
frontmatter). No toolset section in the context means the clone is not registered: say
`no toolset in context — run factory add-repo first` and stop.
If `${CLAUDE_SKILL_DIR}/references/<stack>/` does not exist, say `no <stack> reference for
add-slice yet` and stop. Done when the stack is named and its reference folder exists.

### 2. Follow the stack guide

Read `${CLAUDE_SKILL_DIR}/references/<stack>/README.md` and follow its steps in order: the context and the
template's implicit contract, the file from the template, domain and ports, the registration inside the
module, the build. Done when the guide's own "Done when" holds.

## Done when

Build and tests are green, the slice is one internal file at the location and in the namespace the guide
requires, the endpoint is mapped through the module, and the handler reaches other functionality only
through the domain and its own ports.
