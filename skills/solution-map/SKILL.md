---
name: solution-map
description: A developer's map of one solution — projects, components, the classes other components call and the methods they call — as markdown under docs/architecture/map/ plus one offline HTML page. Extract, explore, merge, render.
disable-model-invocation: true
model: opus
---

# Solution map

The deliverable is `docs/architecture/map/` in the product repo: `README.md` (the project graph, the reading
order, the glossary), one file per project, and `index.html`, one offline page. Facts come from an extractor,
never from reading code by hand; prose comes from explorer agents; the merge and every check stay in this
session. Everything under it is **generated**: regenerated whole, never hand-edited. Leading words:
`${CLAUDE_SKILL_DIR}/references/section-skeleton.md`. Outside the factory flow: no task, no state repo, no MR.

Argument: `[scope]`, a project name; it narrows steps 3 to 5 and the README header records it.

## Steps

### 1. Read the stack

Read `stack:` from the toolset section of the injected context. None: say
`no toolset in context — run factory add-repo first` and stop. No `${CLAUDE_SKILL_DIR}/references/<stack>/`:
say `no <stack> reference for solution-map yet` and stop. Otherwise read its `README.md`.
Done when the stack guide is loaded and names the extractor command.

### 2. Extract

Run the extractor per the stack guide into `docs/architecture/map/map.json`. Done when the JSON names every
project the solution file lists and carries its commit.

### 3. Explore

Read `${CLAUDE_SKILL_DIR}/references/section-skeleton.md`, then cut the JSON into one slice per project,
a project with more than 25 components per component. A test project (its path matches the toolset's
`test-globs`) gets no slice, only a README line. Spawn one `solution-map-explorer` per slice, in parallel,
each with a self-contained brief:
`${CLAUDE_PLUGIN_ROOT}/bin/agent-brief.sh solution-map-explorer`, the repo root, the slice inline, the
skeleton path, and the rule that a type absent from the slice is never named. Done when every slice has a
section and `sh ${CLAUDE_PLUGIN_ROOT}/bin/solution-map-check.sh md docs/architecture/map/map.json <sections>`
prints `ok`. A failing section goes back to its explorer once; a second failure drops the offending names
into the README's `## Ungrounded`.

### 4. Merge

Write `docs/architecture/map/README.md`: the commit and the scope, one mermaid `flowchart` of the projects
and their references, the cross-project edges the sections name, a reading order for a new developer (host
first, then the main flows), and a glossary of the leading words. Write one
`docs/architecture/map/<project>.md` per project from its sections, unchanged. Done when every README edge
exists in the JSON and the `md` check passes over all files.

### 5. Render

Spawn `solution-map-render` with `${CLAUDE_SKILL_DIR}/references/map-template.html`, the markdown in
README-first order, the JSON path and the output `docs/architecture/map/index.html`. The agent leaves
`<!-- slot:mermaid -->` in place; `sh ${CLAUDE_PLUGIN_ROOT}/bin/solution-map-inline.sh docs/architecture/map/index.html`
fills it with the vendored mermaid build, so diagrams render offline. Done when
`sh ${CLAUDE_PLUGIN_ROOT}/bin/solution-map-check.sh html docs/architecture/map/index.html <markdown files>`
prints `ok` and the page contains no `slot:mermaid`. One failure goes back to the agent; a second is
reported and the page left out.

### 6. Report

Report to the user: files written, projects covered, what the caps hid, ungrounded names, and the command
that regenerates the map.
