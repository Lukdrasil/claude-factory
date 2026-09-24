# factory-ui

The Factory UI server: a .NET 10 minimal API published with Native AOT into `runtime-deps:10.0-alpine`, with
git added for the task timeline. `bin/ui-up.sh` builds it as `claude-factory-ui:<plugin version>` and runs it
as the host uid:gid with two mounts:

| mount | mode | what |
|---|---|---|
| `/state` | read-only | the factory state repo |
| `/ui` | read-write | the UI home: `token`, `port`, `sessions/<sid>/` with `session.md`, `asks/`, `answers/`, `relay`, `delivered`, `agent`, `visual.html`, `visual.md` |

The container listens on 8080 and is published only on `127.0.0.1`.

## API

Every request whose `Host` is not `127.0.0.1:<port>` or `localhost:<port>`, with the port in `/ui/port` read per
request, is answered 403 before anything else. Every `/api/*` request needs the header `X-Factory-Token` equal to
`/ui/token`, otherwise 401. `/` and its static files are served without it.

| route | what |
|---|---|
| `GET /api/board` | every task's frontmatter in the columns of `factory-list.sh` |
| `GET /api/tasks/{id}` | the task's body, its blocks, plan, grill file, verdicts, progress and `git log` timeline, and `html`: each of the markdown fields rendered |
| `GET /api/sessions` | every session's `session.md` fields, its asks: frontmatter, body, mtime, `sent`, the relay's `held` reason and the ask `view`, and its `visual`: `row`, `version`, `status` of `visual.md`, null without `visual.md` and `visual.html` |
| `GET /api/setup` | the factory root, `repos.yml`, the toolsets and the last doctor notice |
| `GET /api/stream` | `text/event-stream`, one `data: /state/<path>` or `data: /ui/<path>` line per changed file |
| `POST /api/answers/{sid}` | body `{"ask": "<ask>", "text": "<shorthand>"}`: writes `answers/<seq>-<ask>.txt` |

`POST /api/answers/{sid}` answers 201 when written, 400 for a `sid` or `ask` outside `[A-Za-z0-9-]+`, 404 for
an unknown session or ask, and 409 for an ask whose status is not `open`. The seq runs per session, and the
file is written through a rename. The server is the only writer of answer files. `bin/ui-relay.sh` types them
into the session.

The stream comes from two `MountScanner`s, one per mount. Each compares the name, length and mtime of every
file under its mount every 250 ms. It skips a folder it cannot read and hidden entries such as `.git`.

`GET /visual?sid=<sid>&token=<token>` is the one route outside `/api` that needs the token, as a query parameter,
since an iframe sends no header. It serves `sessions/<sid>/visual.html` byte for byte as `text/html` with
`Content-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:`,
so a visual's script can read the token in its URL. The CSP stops its requests but not a navigation of its own
frame, which can carry the token to another origin. The Host check is what keeps a name rebound to 127.0.0.1
from reaching the API with it. It answers 401 for a missing or
wrong token, 400 for a missing sid or one outside `[A-Za-z0-9-]+`, and 404 without `visual.html`.

The server is the one reader of an ask. `view` is `AskParser`'s reading of the body: `kind` is `notice` without a
question, `confirm` for one question whose options are exactly yes and no, `round` otherwise. `preamble` is the
rendered text before the first `❓`, the whole body for a notice. Each question has `q`, `title`, `after`, `html`
(its text without the header, option and `➡️` lines), `options` (`key` and inline `html`), `rec` and `recKey`.
Options inside a fenced block are never read. `body` stays, the text the terminal shows.

Markdown is rendered by Markdig with the advanced extensions and raw HTML escaped. A link whose URL is not http,
https, relative or a fragment keeps its text and loses its `href`, autolinks included.

`sent` is true once an answer file newer than the ask file names the ask and is not a `Q<n> redraw` or `Q<n> more`, so an ask
rewritten under the same id reads open again. `held` is the reason in `sessions/<sid>/relay` while the relay
holds any answer file of the ask newer than the ask, a `Q<n> redraw` or `Q<n> more` included, otherwise null.

## The page

`/#token=<token>`, the URL `ui-up.sh` prints, serves the pipeline page from `wwwroot/`: plain JS modules, system fonts, nothing from another origin
and no build step. The token in the URL fragment goes into the `X-Factory-Token` header of every `/api` call, the
change stream included, so the page reads `/api/stream` with `fetch`, not `EventSource`. Without a token it shows
no task.

| module | what |
|---|---|
| `pipeline.js` | `renderPipeline(board, sessions)`: the grid of tasks across the solve steps, blocks in sub-rows under their parent, the step a session reports marked `aria-current="step"`, the setup strip and the waiting-on-you counter |
| `drawer.js` | `renderDrawer(group)`: the drawer of one task or of setup, its open asks, its sessions' visuals and its context |
| `ask-card.js` | `renderAsk(ask, staged)`: one ask as a card from its ask view, and `compose(view, items)`, the answer Send posts |
| `visual.js` | `renderVisual(visual)`: a session's drawn visual in an iframe with `sandbox="allow-scripts"` on `/visual`, its row, version and out-of-date mark, and Redraw, which posts `Q<row> redraw` to the session's newest open ask |
| `app.js` | state, the calls, the stream and the clicks |

The counter counts the open asks nobody has sent an answer for, of sessions in herdr whose `agent` is not
`gone`; a gone session's asks still show in their drawer, since the relay queues answers. Each click opens the next
one, oldest first by mtime, in its drawer. A drawer keeps an ask it opened with even after its session closes
it, so the card shows answered.

The card renders the ask view of `/api/sessions`, the server's reading of the ask, and parses no markdown. An ask
with no `❓ **Qn**` is a notice. One question with the options yes and no is a confirm. Anything else is a round.
The header shows the ask's step and its question count, the session id sits in a small line at the bottom. Each
option is a full-width button holding its rendered label, and the recommendation reads `Why B: ...`. A card
stages one item per question until Send: an option (`Q1 B`), Explain more (`Q2 more`), Compare options
(`explore Q3`), Write my answer (`Q4 <text>`), Ask a question (`Q5 ? <text>`) or Decide later (`Q6 defer`).
Every card, a notice included, has Write my answer: a notice posts that text verbatim, or `ok` without one.
Send posts the staged items one answer per line in question order, since free text may hold commas, and the
`<output>` under Will be sent: shows them exactly as the answer file will hold them. A card needs your answer,
is sent and waiting for the session, or is answered, and shows the relay's held reason whenever the ask is held.
The card of a session outside herdr shows no answer box.

On a narrow screen the grid scrolls sideways inside its container and the drawer takes the full width.

## Tests

`tests/ui/` holds the xunit tests of `MountScanner`. `tests/ui-server.test.sh` runs them in the SDK image, so
the host needs no .NET, and drives the container end to end through `ui-up.sh` and `ui-down.sh`.
`tests/ui-page.test.sh` drives the page in Chromium from the `mcr.microsoft.com/playwright` image against the same
fixture, `tests/ui-fixture.sh`. `ui-up.sh` reuses an existing image, so run `docker image rm
claude-factory-ui:<version>` after a change under `ui/`.
