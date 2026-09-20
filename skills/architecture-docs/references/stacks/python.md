---
written_against: Python 3.14.x (free-threading officially supported, PEP 779), Django 5.2 LTS, FastAPI/Starlette and Litestar current, uv-first packaging — as of 2026-08
---

`architecture-docs audit` diffs this stamp against the ecosystem it finds in the repo to tell
"the target stack moved" from "this file is stale" — bump the line when a section's guidance
changes, not on every edit.

# Python web stack — reference

Implementation-level choices for a Python product repo, one level under `approaches.md`'s
deployment-topology/structure/communication axes. Load this file when the repo is Python; the
same options-plus-consequences discipline from `approaches.md` applies — put choices to the
human as alternatives grounded in `02-constraints.md` and `04-quality-scenarios.md`, not as a
silent pick.

## Framework choice

| Driver in the recorded scenarios / constraints | Candidates to put on the table |
|---|---|
| Admin-heavy internal tool, CRUD-dominant, small team wants one opinionated stack | Django (+ DRF or Ninja) |
| Async I/O-bound API, OpenAPI-first, AI/LLM-backend workloads | FastAPI |
| Small service, team hand-picks every library, WSGI is enough | Flask |
| FastAPI's shape but stricter typing and serialization throughput matters more than ecosystem size | Litestar |

### FastAPI

- **Use when** the service is async I/O-bound, the API is contract-first (OpenAPI matters to
  consumers), or it fronts AI/LLM/vector-store calls that spend most of their time waiting.
- **Pros** async-first with Pydantic v2 validation and automatic OpenAPI; small conceptual
  surface; plays cleanly with Starlette middleware.
- **Cons** no batteries — auth, admin, migrations, background jobs are each a separate choice
  the team must make and wire; `Depends` is per-request DI, not a general container, and gets
  deep fast; no ORM opinion, so conventions vary project to project.
- **Typical mistakes** a sync call (`requests`, a sync DB driver) inside an `async def` route,
  stalling the event loop for every concurrent request; skipping response models, which throws
  away the OpenAPI contract's value; running `uvicorn --reload` in production.

### Django (+ DRF or Ninja)

- **Use when** the product needs an admin UI, the domain is CRUD-dominant, or a small team
  benefits more from one batteries-included standard than from picking ten libraries.
- **Pros** admin panel, auth, sessions, migrations and ORM ship together and interoperate; DRF
  gives REST conventions, Ninja gives FastAPI-like typed views on the same foundation; large
  ecosystem.
- **Cons** the batteries are opinionated — replacing the ORM or auth model fights the framework;
  async views (5.x) are real, but most codebases still call the ORM synchronously underneath, so
  "async Django" often blocks the loop anyway unless every call in the path is actually async;
  heavier baseline than a single-purpose API needs.
- **Typical mistakes** the admin panel exposed on the public internet without a second auth
  layer; business logic living in views/serializers instead of models/services, so it cannot be
  unit-tested without the framework; mixing DRF and Ninja in one project with no reason; an async
  view that calls a sync ORM method and blocks the loop regardless.

### Flask

- **Use when** the service is small, the team wants to choose every dependency itself, or the
  work is extending an existing mature Flask codebase.
- **Pros** minimal core, large extension ecosystem, low ceremony, easy to read end to end.
- **Cons** WSGI by default — `async def` views exist but the server underneath is still
  synchronous unless an ASGI adapter is deployed on top; no built-in validation, DI or OpenAPI;
  project layout is reinvented per repo, so consistency depends entirely on team discipline.
- **Typical mistakes** adding async routes under sync gunicorn workers and gaining no
  concurrency; an ad hoc structure that differs from the last Flask service the team shipped;
  skipping request validation, so bad input reaches business logic unchecked.

### Litestar

- **Use when** the team wants FastAPI's ergonomics with stricter typing or faster serialization,
  and is willing to trade ecosystem size for it.
- **Pros** msgspec-based serialization outperforms Pydantic in benchmarks; typed DI is cleaner
  than `Depends`; pagination, caching and CORS patterns are built in where FastAPI leaves them to
  the team.
- **Cons** smaller ecosystem, fewer third-party integrations, smaller hiring pool, and thinner
  LLM-training-data coverage than FastAPI — mistakes in Litestar code are less likely to be
  caught by a model or a search engine.
- **Typical mistakes** choosing it off synthetic serialization benchmarks that a real endpoint's
  database and network calls will dwarf; underestimating ramp-up for a team that has never used
  it.

**Where the batteries-included trade-off bites.** Admin: Django ships one; an ad hoc admin UI
bolted onto FastAPI/Litestar/Flask is a real, often unbudgeted cost — a genuine internal-CRUD
need is a real driver toward Django. ORM: Django's ORM is fine until the query is not what its
abstraction was built for (complex reporting, bulk writes, window functions), and then it is
worked against instead of with. Auth: Django's session/user/permission subsystem saves real time
for anything cookie-session-based with users and groups; for a stateless API validating a bearer
token or JWT, that whole subsystem is dead weight carried for nothing.

## ASGI/WSGI and the server

- ASGI (uvicorn, hypercorn, Granian) serves async apps and is required for websockets, SSE and
  HTTP/2. WSGI (gunicorn without an async worker class) only serves synchronous request/response.
- Standard shape: gunicorn as process manager supervising uvicorn worker processes
  (`gunicorn -k uvicorn.workers.UvicornWorker`), or uvicorn's own multiprocess mode. One worker
  per CPU core (sometimes one fewer, to leave a core for the kernel and sidecars) — not the
  `(2 × cores) + 1` formula, which sizes sync workers blocked on I/O; an async worker already
  serves many concurrent connections inside one event loop.
- Async concurrency hides I/O wait, not compute: CPU-bound work inside a handler does not
  parallelize just because the function is `async def`. A CPU-bound endpoint needs more worker
  processes or a dedicated background worker (below), not more `await`.
- GIL and free-threading (2026): Python 3.14's free-threaded build is officially supported (PEP
  779), no longer experimental, and C-extension compatibility has improved sharply since 3.13 —
  but is not universal. Verify any package with hand-written C-API calls before deploying on a
  free-threaded build. For a typical ASGI service already scaled by worker processes, the gain
  from free-threading is marginal; it matters when the real bottleneck is CPU inside one process
  — batch jobs, ML inference — not request concurrency.
- Websockets/SSE need ASGI end to end, plus a reverse proxy that supports the upgrade and does
  not apply its default idle timeout to a connection meant to stay open (see Networking below).

## Background work

- **Celery** — broadest feature set (periodic tasks, chains/workflows, multiple brokers),
  heaviest to operate; the path of least resistance on a Django codebase with Beat/admin
  integration already expected.
- **Dramatiq** — smaller surface, reliability-first; the right default when losing a task is not
  acceptable (financial or compliance workloads).
- **RQ** — Redis-only, minimal setup, fine for a small app with simple fire-and-forget jobs and
  no workflow requirements.
- **arq** — asyncio-native, fits a codebase that is already async end to end; smaller community
  and fewer production war stories than the other three.
- **Cloud-managed queues** (SQS, Cloud Tasks, Pub/Sub) — no broker to operate, at the cost of
  building retry/DLQ handling against the provider's API instead of a library's.
- **Cron** — the right choice for scheduled batch work with no queueing semantics needed; do not
  add a task-queue library just to run something nightly.
- **Typical mistakes** the retry path is never exercised in tests, so the first real failure is
  also the first time anyone learns whether retries are idempotent; nobody monitors queue depth
  or dead-letter counts, so a stuck worker fails silently until a user notices; a task queue used
  as a request/response channel (the caller polls for a result) where a synchronous call would do;
  a task that is not idempotent, so a retry double-charges or double-sends.

## Packaging and runtime deployment

- **uv** is the 2026 default for new projects — fast, manages Python versions and virtualenvs,
  one lockfile, workspace support for monorepos. **Poetry** remains reasonable for publishing a
  library to PyPI. **pip-tools** is acceptable only where the org cannot adopt a new tool. No
  lockfile format is standard across tools yet — do not mix uv and Poetry in one repo expecting
  one lockfile to serve both.
- **Container images**: multi-stage build — a heavier stage with compilers and build tooling
  produces the wheels or the venv, a slim final stage copies only the app and its runtime
  dependencies. `python:slim` (Debian-based) is the safer default; distroless trims further, but
  every C-extension dependency must be verified against it — musl-vs-glibc mismatches (also an
  Alpine problem) surface exactly at this boundary. Pin the Python patch version in the base
  image: an unpinned tag lets the base OS package set move under the build, which is why Python
  images rot and builds stop being reproducible.
- Resolve the lockfile at build time, not at container start — re-resolving dependencies on
  deploy is not reproducible and can pull in a break between build and rollout.
- **Type checking** (mypy, pyright, pyrefly) is an architectural lever for code an LLM maintains,
  not a style preference: strict-mode types catch a wrong assumption before it reaches review,
  and they are the signal an agent can query to fix something without re-reading the whole
  module. Set the strictness level the codebase can sustain — strict for new code, a scoped
  migration plan for an untyped legacy base — because an ignored, permanently-failing type check
  teaches everyone to skip the signal, which is worse than not having one.

## Data access

SQLAlchemy (2.0-style, explicit `Session`/`select()`) gives full control and works outside
Django, at the cost of the team having to fix its own conventions for session scope and
loading strategy. Django ORM starts faster and enforces one convention project-wide, at the cost
of fighting the framework for anything the ORM was not shaped for — complex reporting, bulk
writes, cross-schema queries. Raw SQL (or a query builder) is the right tool for the one query
the ORM makes worse, not for the whole data layer.

Migrations are deploy-coupled, not just schema history. Alembic (SQLAlchemy) supports branching
migrations and works under any deployment topology; Django migrations are simpler but tied to the
Django app registry. Either way, a migration that is not backward-compatible with the
currently-running code breaks a rolling deploy — expand/contract (add a nullable column, deploy
code that writes both, backfill, deploy code that reads the new column only, then drop the old
one) is the pattern that avoids downtime; a single migration that renames or drops a column live
code still reads is not.

## Networking specifics this stack owns

- A reverse proxy (nginx, Caddy, or a cloud load balancer) in front of the ASGI/WSGI server is
  the norm, not an option: it terminates TLS, handles the HTTP/2 and websocket upgrade, and
  absorbs slow or malicious clients before they reach an application worker. Running uvicorn
  directly on the internet works but skips all of that.
- Long-lived connections (websockets, SSE, streaming responses) need their timeout aligned across
  both layers — the proxy's idle/read timeout is an independent clock from the app server's, and
  the shorter one wins. A 502 on a connection the app would have kept open is almost always the
  proxy's timeout firing first, not the app's.
- Set both timeouts deliberately, app slightly longer than the proxy, rather than leaving either
  one at its framework default without checking what the other is set to.
