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
| `GET /api/board` | every task's frontmatter in the columns of `factory-list.sh`, with its `request`, `priority` and `steps` (the solve steps its state records as done, read the way `bin/solve-next.sh` decides them) |
| `GET /api/tasks/{id}` | the task's body, its blocks, plan, grill file, verdicts, progress and `git log` timeline, and `html`: each of the markdown fields rendered |
| `GET /api/sessions` | every session's `session.md` fields, its asks: frontmatter, body, mtime, `sent`, `answer` (the text of its last answer that closes it, null without one), the relay's `held` reason and the ask `view`, and its `visual`: `row`, `version`, `status` of `visual.md`, null without `visual.md` and `visual.html` |
| `GET /api/setup` | the factory root, `repos.yml`, the toolsets, the last doctor notice, the `steps` and `doctorAt` of `setup/doctor.json`, the `capacity` in use and the `passes`: every scope with a `passes.yml`, or with work for a pass and none yet (`daily` and `weekly` read `never`), and the pass it is `due` for, `daily`, `weekly`, `both` or `none`, by the rule of `pass-stamp.sh --due`; `addRepos`, every `setup/add-repo/<key>.json` factory-add-repo.sh wrote (`key`, `url`, `path`, `state`, `detail`, `at`, a missing field `""`, an unreadable file skipped), newest `at` first; `onboarding`, every `repos/<key>/onboarding.md` in key order: `repo`, `status`, `at`, `stack`, `summaryHtml` (its `## Summary` rendered), and the lines of `## Checks` and `## Proposals` the regexes of the design's C5 match, as text: `checks` (`state`, `id`, `detail`, `fix`, split at the last ` Fix: `) and `proposals` (`id`, `area`, `text`) |
| `GET /api/org` | the `capacity` of sessions and of every role, `used` and `cap`, the `leases` under `.capacity/`, one of the `leads` per `repo-lead` lease, and the `ceo` session or null |
| `GET /api/requests` | every request map, live and archived, newest first: `id`, `status`, `destination`, `priority`, `parents`, `archived` |
| `GET /api/requests/{id}` | one map: its destination, notes, terms, decisions, out of scope, fog, tickets and frontier, its parents with their blocks, status and acceptance, and `html`: the destination, notes, terms and fog rendered, and the `title` and `gist` of every line of decisions and out of scope rendered inline |
| `GET /api/stream` | `text/event-stream`, one `data: /state/<path>` or `data: /ui/<path>` line per changed file |
| `POST /api/answers/{sid}` | body `{"ask": "<ask>", "text": "<shorthand>"}`: writes `answers/<seq>-<ask>.txt` |
| `GET /api/auto-answer`, `POST /api/auto-answer` | `{"on": <bool>}`: whether auto answer is on, the file `/ui/auto-answer`; the POST sets it and answers the new state |

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
Options inside a fenced block are never read. A `❓` segment without a question header is rendered after the previous
question's `html` and adds no option and no say in `kind`, or joins the preamble when no question precedes it. `body`
stays, the text the terminal shows.

Markdown is rendered by Markdig with the advanced extensions except generic attributes and media links, so no markdown
attaches an event attribute or an iframe, and raw HTML escaped. A link whose URL is not http, https, relative or a
fragment keeps its text and loses its `href`, autolinks included. `/`, its static files and the API are sent with
`Content-Security-Policy: default-src 'self'; img-src 'self' data:`, and `/visual` replaces it with its own.

`sent` is true once an answer file newer than the ask file names the ask and is not a `Q<n> redraw` or `Q<n> more`, so an ask
rewritten under the same id reads open again. `held` is the reason in `sessions/<sid>/relay` while the relay
holds any answer file of the ask newer than the ask, a `Q<n> redraw` or `Q<n> more` included, otherwise null.

## The page

`/#token=<token>`, the URL `ui-up.sh` prints, serves the pipeline page from `wwwroot/`: plain JS modules, system fonts, nothing from another origin
and no build step. The token in the URL fragment goes into the `X-Factory-Token` header of every `/api` call, the
change stream included, so the page reads `/api/stream` with `fetch`, not `EventSource`. Without a token it shows
no task. A token the server refuses reads `The UI token is not valid any more: open the URL ui-up.sh printed.`
While the change stream is down, retried every second, a cue in the corner reads that what you see may be out of
date; it clears once the stream is back.

| module | what |
|---|---|
| `pipeline.js` | `renderTop(sessions, tab)`: the tabs, the to-answer counter and the setup strip; `renderPipeline(board, sessions, requests, capacity)`: the filter bar and the grid of tasks across the five phases of the solve steps, grouped by request, blocks folded under their parent, the step a session reports marked `aria-current="step"` |
| `requests.js` | `renderMap(list, id, detail)` and `renderPlan(list, id, detail)`: the request list and the map, or the final plan with its read-only checklist, of the request shown |
| `org.js` | `renderOrg(org)`: the CEO, capacity, leads and leases of `/api/org`; `capacityStrip(capacity)`, `prio(p)` and `when(stamp)` |
| `memory.js` | `renderMemory(passes, ceo, note)`: the pass dates of every scope, the pass it is due for and their start buttons |
| `setup.js` | `renderSetupStrip(setup)`: the machine checklist in the strip; `renderSetupTab(setup, sessions, ceo, note)`: the Repositories section, the doctor steps and Start the CEO |
| `repos.js` | `renderRepos(setup, sessions, ceo, note)`: the Repositories section; `repoRowState(key, setup, sessions)`, a row's one state; `urlProblem(url)`, `aliasProblem(alias)`, `keyOf(url)` and the lines it sends, `addRepoLine`, `onboardLine` and `proposalLine` |
| `drawer.js` | `renderDrawer(group)`: the drawer of one task or of setup, its asks, open ones first, its sessions' visuals and its context, in decision mode with an open ask |
| `ask-card.js` | `renderAsk(ask, staged)`: one ask as a card from its ask view; `stateOf(ask)`, its one state; and `compose(view, items)`, the answer Send posts |
| `visual.js` | `renderVisual(visual)`: a session's drawn visual in an iframe with `sandbox="allow-scripts"` on `/visual`, its row, version and out-of-date mark, and Redraw, which posts `Q<row> redraw` to the session's newest open ask |
| `app.js` | state, the calls, the stream, the clicks and Esc, the focus kept across renders and the staged answers in `sessionStorage` |

The counter counts the open asks nobody has sent an answer for, of sessions in herdr, and names apart the ones
whose session has ended (`7 to answer, 1 whose session ended`); such an ask still shows in its drawer, read-only.
An ask without a `task:` counts under its session's task, so the counter, the grid and the drawer use one key. Each click opens the next one, oldest first
by mtime, in its drawer, and marks its card current with `aria-current="true"` and an outline, as `?ask=` does. A
drawer keeps an ask it opened with even after its session closes it, so the card shows answered.

The card renders the ask view of `/api/sessions`, the server's reading of the ask, and parses no markdown. An ask
with no `❓ **Qn**` is a notice. One question with the options yes and no is a confirm. Anything else is a round.
The header shows the ask's step and its question count, the session id sits in a small line at the bottom. Each
option is a full-width button holding its rendered label, `aria-pressed` and a check mark once picked, and an
`aria-label` of its key and whole label as text, inline code included, so no reader of its text nodes alone drops a
code span; the recommendation reads `Why B: ...`. A card
stages one item per question until Send: an option (`Q1 B`), Explain more (`Q2 more`), Compare options
(`explore Q3`), Write my answer (`Q4 <text>`), Ask a question (`Q5 ? <text>`) or Decide later (`Q6 defer`).
Every card, a notice included, has Write my answer: a notice posts that text verbatim, or `ok` without one.
Send posts the staged items one answer per line in question order, since free text may hold commas. Under Will be
sent: the staged items read in words, the picked option with its label, and the `<output>` below them holds them
exactly as the answer file will. Staged answers and drafts stay in the tab's `sessionStorage` across a reload.

Each question of an open card is a box of its own, its header reading Not answered yet or `Answered: <item>`. The
recommendation's `Why <key>: ...` sits right under the recommended option, which is outlined dashed. A question
shows Write my answer and More options, which unfolds Explain more, Compare options, Ask a question and Decide later
(Explain more alone on a confirm) and stays unfolded while one of them is staged. A question body of more than 420
characters is folded until Show all. The header of an open round with more than one question reads `<k> of <n>
answered`, and Accept `<n>` recommended stages the recommended option of every question that has one and nothing
staged yet. With nothing staged the footer names the questions still to answer. After a Send the next waiting ask
opens by itself: the next one of the same drawer, else the oldest one elsewhere.

Auto answer, the switch in the top bar (hidden when the server has no `/api/auto-answer`), is one global setting
kept in `/ui/auto-answer`. While it is on the server itself, once a second and with no page open, answers every open,
unsent round of a session in herdr whose agent is not gone and whose every question has a recommended option, one
`Q<n> <key>` per line through the same answer files. A confirm, a notice, an ask of the `approve`, `done` or
`add-repo` flow, and a round with any question lacking a recommended option are always left to the human.

A card has one state, `stateOf`, shown as one chip in its header: open (Needs your answer), sent (Sent, waiting for
the session), answered, or gone (Not delivered: the session has ended) once the relay holds its answer as `gone` or
the session's `agent` is `gone`. Only an open ask of a session in herdr takes an answer: every other card is
read-only, its options disabled, with no answer box and no Send. A sent or answered card shows under Sent: the
`answer` it was sent, in words like Will be sent:, its picked options pressed. The relay's other held reasons show as a note
under the header of an open or sent card. The card of a session outside herdr shows no answer box.

A drawer with an open ask opens in decision mode: at least 60% of the viewport wide, the asks first with the
question text at about 70ch, and the blocked question, wave, panels, visuals and context in one "Task details",
collapsed on open and kept as you left it across refreshes. The open asks come first, each group oldest first.
One card's footer, Will be sent: and Send, sticks to the bottom of the drawer: the first card with a Send not
scrolled above the drawer header, so one Send shows at a time. Esc closes the drawer and puts the focus on its
row; every render keeps the focus on the control you used. The approve and done asks render with the other asks, once. Without an open ask the drawer
shows all of it in one column. The panels render the task's markdown from its `html` twin, so no panel shows a
`<pre>` of markdown.

The header holds six tabs, and every tab keeps the counter, the setup strip and the drawer:
- Pipeline: the New request box (a text, a priority P0 to P3, P2 by default), which posts `request: <text>,
  priority <P>` as a free message to the CEO's session and is disabled with the command that starts the CEO when
  there is none; the filter bar, Search tasks, Repository, Show done and closed and the sessions in use
  (`used/cap`, the roles being the Org tab's), then the grid. The grid hides the tasks at `done` or `closed` until
  that box is ticked, Search tasks keeps the tasks whose id, goal, repo or request, or a block's id or goal, holds
  the text, any case, and Repository, shown once the board holds more than one repository, keeps the tasks of the
  one picked; with nothing left the grid reads No task matches. The filters last until a reload. The grid scrolls
  inside its own box, one viewport high at most, with its header row and Task column in view; a render keeps it
  scrolled where it was. It has five phase columns, equally wide, each titled with its steps: Plan (3, 3b, 4, 5, 6,
  8), Approve (9), Build (10, 11), Verify (12, 13) and Ship (14, 15, 16). A phase cell holds one segment per step,
  `data-step` with its label and title, done when the state records it in `steps`; the step a session reports is
  marked current apart from that (`aria-current="step"`, the cell `.cur`), a step with a letter the grid has no
  segment for under its number. Under the segments the cell reads the current step with its count done, the count
  alone, `done`, or `MR waits for you` under Ship for a task in review, and the task's open asks sit in the cell of
  its current step. A status chip reads its meaning: `failed` and `blocked` bad, `triaged` and `review` warn,
  `ready` to `tests_ready` accent, `done` ok. A task shows its repo as a chip next to its id, its priority in the
  Prio column, its live sessions as one count whose title names them (a session whose agent is `gone` is not
  drawn), and its goal on two lines, whole in its title. Its blocks fold into one line, `<n> blocks · <n> <status>`
  per status, which unfolds them in sub-rows on click and while Search tasks holds text; a block's goal is one
  line. The tasks of one request sit under its header row (id, priority, status, destination on one line), the
  request with the best priority first, then the newest, the tasks without a request last; without any request
  there is no header row.
- Map: the request list and the wayfinder map of the request picked (by default the newest live one): the
  destination, the open and claimed tickets with the frontier marked, the decisions so far, the fog and out of scope.
- Plan: the final plan of the same request, its destination, decisions and out of scope, and the checklist of its
  parents per repo with their blocks, status and acceptance. The checklist is read-only; the human approves the
  plan in the CEO's confirm ask, never on the page.
- Org: the CEO session, the capacity, one row per lead and every lease.
- Memory: the last daily and weekly pass of every scope and the pass it is due for; a scope whose first pass is
  due, work in its `drafts/` or `proposals/` and no `passes.yml` yet, reads never twice. With a CEO session each scope offers Start daily and
  Start weekly, which post `{"ask": "", "text": "start the <daily|weekly> pass for <scope>"}` to
  `/api/answers/<ceo sid>`, a free message the relay types into the CEO's pane. The page runs no pass itself.
- Setup: the Repositories section, then the steps of `doctor.json` in order, each done, missing or failing with its
  detail and fix, then Start the CEO with the fix of the `ceo` step. Every fix runs in a terminal or through a
  session's confirm ask. The Repositories section has one row per repos.yml key, then one per key only an add-repo
  file names. Add repository opens a form of a URL and an optional alias; Send posts `add repo <url>[ alias <ALIAS>]`
  as a free message to the CEO, only for an https, http, ssh or `user@host:path` URL of the add-repo charset, not
  starting with `-`, without a user or token, and an alias of 2 to 4 capital letters. A row reads, in this order:
  Waiting for your confirm while the ask `add-repo-<key>` is open in any session, with a button to it; Not confirmed.
  Send again. for a pending add-repo file without it; Cloning since; Onboarding runs while a live session's step is
  `Onboarding <key>`; Onboarding waits for a free session while the notice `add-repo-<key>-wait` is open; Onboarding
  ended without a report for a report still running; the report, done or failed; otherwise Not onboarded. A failed
  add-repo file is a banner above the row. The report shows its counts, and in Report its summary, its checks as
  text and its proposals, each with Make it a request, which posts `request: <key>: <text> (onboarding <Pn>),
  priority <P>` at the priority picked for the report, P3 unless picked. Start onboarding, Start again and Run again
  post `onboard repo <key>`. Without a CEO session every button of the section is disabled and it names the command
  that starts the CEO.

The page reads `/api/org`, `/api/requests` and `/api/requests/{id}` so that any answer but 200 counts as no data,
and treats a missing field as empty, so it runs against a server that lacks them. Besides every stream event it
reloads every 5 s, since the leases under `.capacity` never reach the stream: the capacity and the Org tab follow them.

A button whose click posts to a session is disabled and reads `…` while its post runs: Send of New request and of
Add repository, Start daily and Start weekly, Start onboarding and its reruns, Make it a request and Redraw. All but
the two Sends, whose form empties once sent, then read `✓` and stay disabled for 20 s, so a second click repeats
nothing. A failed post frees the button at once. Send of an ask reads `…` while it sends.

On a narrow screen the grid scrolls sideways inside its box, the tabs scroll inside the header and the drawer
takes the full width, decision mode included.

## Tests

`tests/ui/` holds the xunit tests of `MountScanner`. `tests/ui-server.test.sh` runs them in the SDK image, so
the host needs no .NET, and drives the container end to end through `ui-up.sh` and `ui-down.sh`.
`tests/ui-page.test.sh` drives the page in Chromium from the `mcr.microsoft.com/playwright` image against the same
fixture, `tests/ui-fixture.sh`; `tests/ui-org.test.sh`, `tests/ui-setup.test.sh` and `tests/ui-task.test.sh` do
the same for the Org tab, the setup flows with the Setup and Memory tabs, and the task drawer. `ui-up.sh` reuses an existing image, so run `docker image rm
claude-factory-ui:<version>` after a change under `ui/`. The suites never use that tag: each builds this checkout's
image under its own tag, which `tests/ui-fixture.sh` hands to `ui-up.sh` as `FACTORY_UI_IMAGE`, and removes it at
the end.
