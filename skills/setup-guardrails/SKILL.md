---
name: setup-guardrails
description: Quality-kit phase 1-2. Install analyzers, severity config, a debt freeze, AGENTS.md and a CI gate on a repo, following the reference for the toolset's stack.
disable-model-invocation: true
model: sonnet
---

# Installing agent guardrails

Build-time guardrails on an existing repo: analyzers and their severities, a frozen baseline for the debt
already there, rules for agents in `AGENTS.md`, a permission deny over the guardrail files, and a CI gate
that escalates. The invariant every stack guide shares: every step ends green, and existing findings get
frozen with the guide's baseline techniques, never mass-fixed during install.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context (the `stack: <value>` line in the toolset
frontmatter). No toolset section in the context means the clone is not registered: say
`no toolset in context — run factory add-repo first` and stop.
If `${CLAUDE_SKILL_DIR}/references/<stack>/` does not exist, say `no <stack> reference for
setup-guardrails yet` and stop. Done when the stack is named and its reference folder exists.

### 2. Follow the stack guide

Read `${CLAUDE_SKILL_DIR}/references/<stack>/README.md` and follow its steps in order. Treat every config
key, CLI flag and rule name in it as a claim to verify on first use: check the tool's official docs or
probe it in a scratch run, because a tool that silently ignores an unknown setting turns the guardrail
into a no-op. When a claim fails verification, install what the tool supports and report the discrepancy.
Done when the guide's own "Done when" holds.

## Done when

The stack guide's "Done when" is satisfied and the report to the user carries the guide's report items:
the measured numbers, what was frozen (= debt with a re-enable plan), the merge conflicts and how they were
resolved, and the CI enforcement status.
