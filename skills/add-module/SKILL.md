---
name: add-module
description: Scaffold a new module (hexagon) from the stack reference's templates, ending on a green build.
disable-model-invocation: true
model: sonnet
---

# Adding a module

One module is one hexagon: a domain with no outward dependencies, an application layer with the public
Contracts and Ports and the internal Features (slices), and an infrastructure layer with the adapters and
the module's single registration entry point. The result is the module's projects plus host registration,
ending on a green build, with the module visible to the architecture tests.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context (the `stack: <value>` line in the toolset
frontmatter). No toolset section in the context means the clone is not registered: say
`no toolset in context — run factory add-repo first` and stop.
If `${CLAUDE_SKILL_DIR}/references/<stack>/` does not exist, say `no <stack> reference for
add-module yet` and stop. Done when the stack is named and its reference folder exists.

### 2. Follow the stack guide

Read `${CLAUDE_SKILL_DIR}/references/<stack>/README.md` and follow its steps in order: the target repo's
conventions, the projects from the templates, the registration entry point, the wiring into solution and
host, the wiring into the architecture tests, the build. Done when the guide's own "Done when" holds.

## Done when

Build and tests are green, the host registers the module through its entry point, the module is visible
to the architecture tests (confirmed, not assumed), and the module's only public types are its Contracts,
Ports and registration entry point.
