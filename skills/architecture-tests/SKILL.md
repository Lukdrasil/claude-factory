---
name: architecture-tests
description: Quality-kit phase 3. Install architecture tests, enabled one at a time with debt ceilings, following the reference for the toolset's stack.
disable-model-invocation: true
model: sonnet
---

# Installing the architecture tests

Tests that hold the modular-monolith boundaries: no cycles between modules, a domain with no outward
dependencies, modules reaching each other only through their public surface, slices isolated from sibling
slices, a declared public surface and nothing more. This phase comes after `setup-guardrails`: enabling
tests before the analyzer build is green means two red things at once and nobody knows what to fix first.
Invariant: every enabled test commits green; a failing test gets fixed (few occurrences) or its namespaces
grandfathered under a ceiling (many), never disabled.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context (the `stack: <value>` line in the toolset
frontmatter). No toolset section in the context means the clone is not registered: say
`no toolset in context — run factory add-repo first` and stop.
If `${CLAUDE_SKILL_DIR}/references/<stack>/` does not exist, say `no <stack> reference for
architecture-tests yet` and stop. Done when the stack is named and its reference folder exists.

### 2. Follow the stack guide

Read `${CLAUDE_SKILL_DIR}/references/<stack>/README.md` and follow its steps in order: the preflight, the
test project, the conventions file, the tests one at a time, the debt ceilings, the gate. Done when the
guide's own "Done when" holds.

## Done when

Every enabled test is green, the ceilings hold the measured values, each grandfathered namespace has an
issue with a deadline, and the report to the user lists which tests are enabled, what was grandfathered
and why, and which tests wait for a later phase with the reason.
