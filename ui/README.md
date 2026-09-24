# factory-ui

The Factory UI server: a .NET 10 minimal API published with Native AOT into `runtime-deps:10.0-alpine`, with
git added for the task timeline. `bin/ui-up.sh` builds it as `claude-factory-ui:<plugin version>` and runs it
as the host uid:gid with two mounts:

| mount | mode | what |
|---|---|---|
| `/state` | read-only | the factory state repo |
| `/ui` | read-write | the UI home: `token`, `port`, `sessions/<sid>/` with `session.md`, `asks/`, `answers/`, `relay`, `delivered` |

The container listens on 8080 and is published only on `127.0.0.1`.

## API

Every `/api/*` request needs the header `X-Factory-Token` equal to `/ui/token`, otherwise 401. `/` and its
static files are served without it.

| route | what |
|---|---|
| `GET /api/board` | every task's frontmatter in the columns of `factory-list.sh` |
| `GET /api/tasks/{id}` | the task's body, its blocks, plan, grill file, verdicts, progress and `git log` timeline |
| `GET /api/sessions` | every session's `session.md` fields and its asks: frontmatter, body, mtime, `sent` and the relay's `held` reason |
| `GET /api/setup` | the factory root, `repos.yml`, the toolsets and the last doctor notice |
| `GET /api/stream` | `text/event-stream`, one `data: /state/<path>` or `data: /ui/<path>` line per changed file |
| `POST /api/answers/{sid}` | body `{"ask": "<ask>", "text": "<shorthand>"}`: writes `answers/<seq>-<ask>.txt` |

`POST /api/answers/{sid}` answers 201 when written, 400 for a `sid` or `ask` outside `[A-Za-z0-9-]+`, 404 for
an unknown session or ask, and 409 for an ask whose status is not `open`. The seq runs per session, and the
file is written through a rename. The server is the only writer of answer files. `bin/ui-relay.sh` types them
into the session.

The stream comes from two `MountScanner`s, one per mount. Each compares the name, length and mtime of every
file under its mount every 250 ms. It skips a folder it cannot read and hidden entries such as `.git`.

`sent` is true once an answer file names the ask. `held` is the reason in `sessions/<sid>/relay` while the relay
holds one of the ask's answers, otherwise null.

## The page

`/#<token>` serves the pipeline page from `wwwroot/`: plain JS modules, system fonts, nothing from another origin
and no build step. The token in the URL fragment goes into the `X-Factory-Token` header of every `/api` call, the
change stream included, so the page reads `/api/stream` with `fetch`, not `EventSource`. Without a token it shows
no task.

| module | what |
|---|---|
| `pipeline.js` | `renderPipeline(board, sessions)`: the grid of tasks across the solve steps, blocks in sub-rows under their parent, the step a session reports marked `aria-current="step"`, the setup strip and the waiting-on-you counter |
| `drawer.js` | `renderDrawer(group)`: the drawer of one task or of setup, its open asks and its context |
| `ask-card.js` | `renderAsk(ask, staged)`: one ask as a round, a confirm or a notice, and `compose`, the shorthand Send posts |
| `app.js` | state, the calls, the stream and the clicks |

The counter counts the open asks nobody has sent an answer for, of sessions in herdr. Each click opens the next
one, oldest first by mtime, in its drawer. A drawer keeps an ask it opened with even after its session closes
it, so the card shows answered.

An ask with no `❓ **Qn**` is a notice, whose Send posts `ok`. One question with the options yes and no is a
confirm. Anything else is a round. A card stages one item per question until Send: an option (`Q1 B`), More
detail (`Q2 more`), Explore (`explore Q3`), Own answer (`Q4 <text>`), Discuss (`Q5 ? <text>`) or Defer
(`Q6 defer`). The `<output>` shows the joined shorthand exactly as the answer file will hold it. A card is open,
sent or answered, with the relay's held reason. The card of a session outside herdr shows no answer box.

On a narrow screen the grid scrolls sideways inside its container and the drawer takes the full width.

## Tests

`tests/ui/` holds the xunit tests of `MountScanner`. `tests/ui-server.test.sh` runs them in the SDK image, so
the host needs no .NET, and drives the container end to end through `ui-up.sh` and `ui-down.sh`.
`tests/ui-page.test.sh` drives the page in Chromium from the `mcr.microsoft.com/playwright` image against the same
fixture, `tests/ui-fixture.sh`. `ui-up.sh` reuses an existing image, so run `docker image rm
claude-factory-ui:<version>` after a change under `ui/`.
