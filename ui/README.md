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
| `GET /api/setup` | the factory root, `repos.yml`, the toolsets and the last doctor notice |
| `GET /api/stream` | `text/event-stream`, one `data: /state/<path>` line per changed file |
| `POST /api/answers/{sid}` | body `{"ask": "<ask>", "text": "<shorthand>"}`: writes `answers/<seq>-<ask>.txt` |

`POST /api/answers/{sid}` answers 201 when written, 400 for a `sid` or `ask` outside `[A-Za-z0-9-]+`, 404 for
an unknown session or ask, and 409 for an ask whose status is not `open`. The seq runs per session, and the
file is written through a rename. The server is the only writer of answer files. `bin/ui-relay.sh` types them
into the session.

The stream comes from `MountScanner`, which compares the name, length and mtime of every file under `/state`
every 250 ms. It skips a folder it cannot read and hidden entries such as `.git`.

## Tests

`tests/ui/` holds the xunit tests of `MountScanner`. `tests/ui-server.test.sh` runs them in the SDK image, so
the host needs no .NET, and drives the container end to end through `ui-up.sh` and `ui-down.sh`.
