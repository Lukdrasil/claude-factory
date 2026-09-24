# Visual brief

A `prototype` row whose question is one of looks, a layout, a grid or a flow on screen, can be closed by a drawn
visual instead of throwaway code. Only with `ui: docker` in herdr (`skills/_shared/ask.md`), where the page has a
drawer to show it in. One visual per grill.

## Who writes what

| file, under `<UI home>/sessions/<session_id>/` | writer | what |
|---|---|---|
| `visual.html` | a background subagent, from the brief below | the drawn visual, one self-contained page |
| `visual.md` | you, the grill session | frontmatter `row: <n>`, `version: <n>`, `status: current` or `stale` |

`<UI home>` is `$FACTORY_UI_HOME`, else `~/.claude-factory/ui`. Both files go through a temp file and a rename,
like every file the server reads. The page shows the visual in the drawer of the session's task: the row, the
version, an out-of-date mark while `status: stale`, and a Redraw button. The server serves `visual.html` at
`/visual` in an iframe with `sandbox="allow-scripts"`.

## The brief

Spawn the subagent in the background with this brief, filled in, and keep asking the round while it draws:

```
Draw row Q<n> of the grill as one HTML file and write it to <UI home>/sessions/<session_id>/visual.html
through a temp file and a rename. The question: <the row's question and its options>. What the human must
see to decide: <the finding the visual has to make visible>.

- One self-contained file: inline <style> and <script> only. Images are inline SVG or data: URIs.
- Nothing from another origin and no request at all: no fetch, no link, no font, no external image. The
  page's Content-Security-Policy blocks every one of them and the visual shows up broken.
- Draw each option side by side when the row has options, labelled with its letter.
- Never read location, document.cookie or window.parent: the frame is sandboxed and its URL carries a
  token.
- Report the path you wrote and one sentence of what the visual shows.
```

Then write `visual.md` with `version: 1` and `status: current`.

## After

- **The finding goes into the ledger row**, never the visual: one sentence of what it showed, like the finding
  of any prototype. The files stay in the session folder and are not part of the plan.
- **A changed answer** to a row this one depends on marks it stale: `status: stale`, same version.
- **`Q<n> redraw`** is the page's Redraw, relayed as a turn like any answer. It is not an answer to Q<n>, and
  the ask stays open. Spawn the subagent again with the brief updated to the changed answers, then write
  `visual.md` with the version one higher and `status: current`.
