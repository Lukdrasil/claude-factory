---
name: quality-kit
description: Router for the modular-monolith quality kit. Phased adoption of analyzers, guardrails and architecture tests, per the reference for the toolset's stack.
disable-model-invocation: true
model: sonnet
---

# Quality kit router

Phased adoption of build-time quality enforcement: compiler visibility, analyzers,
architecture tests, CI escalation. Every phase ends on a green build; strictness rises only on green. A rule
gets enabled only when its findings are fixed now or frozen into a baseline: a warning nobody fixes devalues
every other warning.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context (the `stack: <value>` line in the toolset
frontmatter). No toolset section in the context means the clone is not registered: say
`no toolset in context — run factory add-repo first` and stop.
If `${CLAUDE_SKILL_DIR}/references/<stack>/` does not exist, say `no <stack> reference for
quality-kit yet` and stop. Done when the stack is named and its reference folder exists.

### 2. Read the stack reference

Read `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`: the stack's phase map, the manual phases 4 and 5,
the anti-patterns. Done when you know which phases the stack supports.

### 3. Run the phases in order

Each phase names a skill; read `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/SKILL.md` and follow it. A phase starts
when the previous one is green.

| Phase | What happens | Skill |
|---|---|---|
| 0 | Structure analysis, debt measurement, restructuring proposal (read-only) | `analyze-structure` |
| 1-2 | Baseline: analyzers, severities, banned symbols, AGENTS.md, permission deny, CI gate | `setup-guardrails` |
| 3 | Architecture tests, enabled one at a time, debt ceilings | `architecture-tests` |
| 4 | Warnings become errors in CI (manual; stack reference) | none |
| 5 | Metrics and code style in the build (optional; stack reference) | none |

On-demand helpers after their prerequisite phase:

| Skill | Use for |
|---|---|
| `analyzer-fix-example` | wrong/right fix pair for a specific rule ID |
| `add-module` | scaffold a new module (hexagon) |
| `add-slice` | scaffold a vertical slice in an existing module |
| `write-analyzer` | a build-time rule the existing analyzers cannot express |

Done when every requested phase ended green and the report names, per phase, what was enabled and
what was frozen.
