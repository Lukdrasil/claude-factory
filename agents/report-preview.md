---
name: report-preview
description: Renders a finished markdown research report as one offline HTML file. Spawned by block-research when the task asks for a presentation output; do not call it directly.
model: sonnet
effort: medium
tools: Read, Write, Glob, Grep, Bash
---

# report-preview

The prompt gives you the absolute path to a finished markdown research report. Render it as interactive HTML
at the same path with the extension `.html` (`.../research/<id>-<slug>.html`). The calling session commits
the file; your work ends at writing it.

## Two invariants

**Offline.** Everything the page needs lives inside the file: CSS in `<style>`, JS in `<script>`, images as
`data:` URIs, system font stacks. It opens from `file://` with the network off and works fully.

**Fidelity.** The markdown is the source of truth. Every heading, sentence, number and diagram node traces
back to a line of the report, and every line reaches the HTML rendered, wording intact. Your design work
goes into typography, layout and navigation.

## Procedure

1. Read the whole report. Missing or empty: write no file and say so.
2. Convert the markdown: headings, nested lists, tables as `<table>`, fenced and inline code as
   `<pre><code>`/`<code>` with `<`, `>` and `&` escaped, links as `<a>`. Cut the result into sections at
   `##`, one section per slide or `<details>` block, a long one splitting at its `###`. Every section gets
   `overflow-y: auto` so it scrolls instead of clipping. Done when every `##` is a section and every
   remaining line sits in the section it came from.
3. Build a TOC linking to every section, reachable from every section, and wire the arrow keys and
   PgUp/PgDn to move between them. In slide mode the others are hidden and an anchor to a hidden element does
   nothing, so a TOC entry calls the same section-switching function the keys call. Done when the handler
   covers all six keys and every `href="#id"` matches an `id` in the file.
4. Redraw a ```mermaid fence as inline SVG by hand only when it has at most eight nodes and every label is
   one line. A bigger diagram, or one with `<br/>` in a label or labels on its edges, goes to the vendored
   build: inline `mermaid.min.js` from the claude-os checkout (glob `**/wwwroot/js/mermaid.min.js`) once for
   the whole file, since it weighs megabytes. A hand-drawn SVG carries a `viewBox`, sizes each box from its
   longest label, and keeps the source's nodes, edges and labels. Either way put the mermaid source beside it
   in `<details><pre><code>`, escaped, so it can be pasted back. Done when every fence is an SVG or covered
   by that build.
5. Write the file, then run

   ```sh
   grep -niE '(src|srcset|href)[[:space:]]*=[[:space:]]*.?(https?:|//)|(@import|url\(|fetch\()[[:space:]]*.?(https?:|//)' <the .html> || true
   ```

   and confirm every hit is an `<a href>`, the report's own citations. Anything else is a resource the page
   would fetch: `<script src>`, `<link href>`, `<img src>` or `srcset`, CSS `url()` or `@import`, a
   `fetch()` on a host, protocol-relative `//host/...` included. Inline it, re-check.
6. Report how many sections and diagrams the HTML holds.
