---
name: wayfinder
description: Chart a request too big for one session as a shared map of decision tickets in the state repo (requests/<R-id>/), and resolve them one at a time until the way to the destination is clear and the map seeds one grill per parent. Started by the chart step session the CEO dispatches (solve-next step 3b), before any lead exists.
---

A request has arrived, too big for one agent session, and wrapped in fog: the way from here to the
**destination** isn't visible yet. Wayfinding is about finding that way, not charging at the destination. This
skill charts the way as a **shared map** in the state repo, then works its **decision tickets** (questions whose
resolution is a decision, not slices of a build to execute) one at a time until the route is clear.

The destination varies per request, and naming it is the first act of charting: it shapes every ticket. It
might be a behaviour two repositories must agree on, a decision to lock before planning starts, or a change made
in place like a data migration. One map covers every repository of the request, so the decisions that cross
repositories are made here, with the human, and each ticket says which repository it concerns.

## Plan, don't do

Wayfinder is **planning**: each ticket resolves a decision, and the map is done when the way is clear, with
nothing left to decide before the grills plan each parent. The pull to just do the work is the signal you've
reached the edge of the map and it's time to hand off: the grill, decompose and the leads do the work, after the
map is clear. Produce decisions, not deliverables; the product clones stay read-only.

## Refer by name

Every map and ticket has a **name**: its title. In everything the human reads (the rounds, narration, the
map's Decisions so far), refer to a ticket by that name, never by a bare number or slug. A wall of `01, 02, 03`
is illegible; names read at a glance. The number and path don't vanish; they ride _inside_ the name, as the link
of `[<title>](issues/<file>)`, never stand in for it.

## The Map

The map is `<state>/requests/<R-id>/map.md`, the canonical artifact; its tickets are
`<state>/requests/<R-id>/issues/NN-<slug>.md`. Both are written and committed **only** through
`${CLAUDE_PLUGIN_ROOT}/bin/map.sh`: every call is one commit of the request's own files under the state lock,
and none pushes (state-push.sh does, in the background). Never edit them with a file tool. The exact shapes are
in `references/format.md`.

The map is an **index**, not a store. It lists the decisions made and points at the tickets that hold their
detail; a decision lives in exactly one place, its ticket, so the map never restates it, only gists it and
links. `map.sh resolve` writes that line for you.

### The map body

The whole map at low resolution, loaded once per session (`cat` it). Open tickets are **not** listed there:
`map.sh frontier <R-id>` finds them.

- `Status:` the request's lifecycle word, under the frontmatter (see Status below).
- `## Destination`: what reaching the end of this map looks like, one or two lines; every session orients to it
  before choosing a ticket. `map.sh set <R-id> destination`, the text on stdin.
- `## Notes`: domain, skills every session should consult, standing preferences for this request.
  `map.sh set <R-id> notes`.
- `## Decisions so far`: one line per resolved ticket, written by `map.sh resolve`.
- `## Not yet specified`: the fog (see Fog of war). `map.sh set <R-id> fog`.
- `## Out of scope`: work ruled beyond the destination (see Out of scope).
- `## Terms`: the vocabulary as it settles, in the grill's shape; the grills of every parent inherit it.
  `map.sh set <R-id> terms`.

`set` replaces the whole section: read the map first and write the section back with your change.

### Tickets

Each ticket is a file of the map; its number is its identity. Its body is the question, sized to one agent
session: `map.sh ticket <R-id> <type> "<title>" --repo <key>|all`, the question on stdin, prints the number.
`Repo:` is the repository the decision concerns, `all` when it binds every repository of the request.

A session **claims** a ticket first, before any work, so concurrent sessions skip it:
`map.sh claim <R-id> <NN> --by <session_id>`, the session_id of your identity line. That claim is the only
lock; an open ticket is unclaimed.

Blocking is the ticket's `Blocked by:` line. A ticket is **unblocked** when every ticket blocking it is resolved
or dropped; the **frontier** is the open, unblocked tickets, the edge of the known, and
`map.sh frontier <R-id>` prints it (`<NN> <type> <title>`).

The answer isn't part of the question; it's recorded on resolution (see Work through the map). Assets created
while resolving a ticket (a research report, a visual) are linked from the answer by path, not pasted in.

## Ticket Types

Every ticket is either **HITL** (human in the loop, worked _with_ a human who speaks for themselves) or
**AFK**, driven by the agent alone. A HITL ticket only resolves through that live exchange; the agent never
stands in for the human's side of it (a grilling agent that answers its own questions has broken this).

- **Research** (AFK): reading documentation, third-party APIs, the product code or the state repo's knowledge
  to surface a fact a decision waits on. Resolved by `claude-factory:deep-research`: score the ticket by its
  rubric, print the rubric line, and spawn the one subagent of that tier with the ticket's question as the
  assignment. The report lands at `<state>/repos/<key>/research/<slug>.md` (the ticket's `Repo:`; for `all`, the
  repository of the parent this step was started for), committed through `bin/state-commit.sh` per
  `skills/deep-research/references/destination.md`. The answer is the gist on its first line and the report's
  path under it. No research branch.
- **Prototype** (HITL): raise the fidelity of the discussion with a cheap, rough, concrete artifact to react
  to. A question of looks, layout or flow on screen gets the grill's visual brief
  (`skills/grill/references/visual-brief.md`) with `ui: docker` in herdr; otherwise an outline, a rough take or a
  stub in the round itself. Only the finding is the answer.
- **Grilling** (HITL): conversation, the default case. One round in the grill's round format
  (`skills/grill/SKILL.md`) through `skills/_shared/ask.md`: the ticket's question as the round's question, two
  to four lettered options and your recommendation. Keep `## Terms` current as the vocabulary settles, the way
  the grill does. The human's answer lands in the ticket's `## Answer` and in Decisions so far, nowhere else: no
  grill file is written while the map is open.
- **Task** (HITL or AFK): manual work that must happen before a _decision_ can be made: nothing to decide,
  prototype or research, but the discussion is blocked until it's done. Signing up for a service so its API can
  be judged, provisioning access, looking at production data so its shape can be seen. This is the one type
  that _does_ rather than decides, and it earns its place by unblocking a decision, not by delivering the
  destination. The agent drives it alone where it can without writing to a product clone (AFK); otherwise it
  hands the human a precise checklist (HITL). Resolved when the work is done; the answer records what was done
  and any resulting facts (credentials location, new URLs, row counts) later tickets depend on.

## Fog of war

The map is _deliberately_ incomplete: don't chart what you can't yet see. Beyond the live tickets lies the
**fog of war**: the dim view of decisions and investigations you can tell are coming but can't yet pin down,
because they hang on questions still open. Resolving a ticket clears the fog ahead of it, graduating whatever's
now specifiable into fresh tickets, one at a time, until the way to the destination is clear and no tickets
remain.

The map's **Not yet specified** section is where that dim view is written down: the suspected question, the
area to revisit later. It's the undiscovered frontier _toward_ the destination: everything here is in scope,
just not sharp enough to ticket. Write as loosely or as fully as the view allows. The map is not clear while
it holds any text, so the grills wait until the fog has graduated or been ruled out.

**Fog or ticket?** The test is whether you can state the question precisely now, _not_ whether you can answer
it now.

- **Ticket when** the question is already sharp, even if it's blocked and you can't act on it yet.
- **Not yet specified when** you can't yet phrase it that sharply. Don't pre-slice the fog into ticket-sized
  pieces: it's coarser than a ticket, and one patch may graduate into several tickets, or none, once the
  frontier reaches it.

**Not yet specified** excludes what's already decided (Decisions so far), what's already a live ticket, and
what's out of scope (the next section).

## Out of scope

Fog only ever gathers _toward_ the destination. The destination fixes the scope, so work beyond it is **out
of scope**: it isn't fog, and it doesn't belong in **Not yet specified**. It gets its own **Out of scope**
section on the map: work you've consciously ruled out of _this_ request. Scope, not sharpness, lands it here.

Out-of-scope work never graduates (the frontier stops at the destination), so it returns only if the
destination is redrawn, and then as a fresh request, not a resumption.

Ruling something out of scope is a scoping act, not a step on the route. When a ticket that already exists
turns out to sit past the destination (mis-scoped in while charting, or exposed by a resolution), **drop it**:
`map.sh drop <R-id> <NN>` with the gist and why on stdin closes it and leaves that one line in Out of scope,
linking the ticket. It stays out of Decisions so far, which records the route actually walked. A boundary drawn
while charting that never was a ticket goes in with `map.sh set <R-id> out-of-scope`.

## Invocation

Nobody has to type it: the CEO dispatches the chart step session for a request (solve-next step 3b,
`/claude-factory:wayfinder chart <R-id> <T-id>`, once per request, for the request's first parent) and
dispatches it again while `map.sh clear <R-id>` does not exit 0. It runs at request level, in the CEO's
workspace, before any lead exists; a lead never charts or edits a map. The human may start it by hand in the
state clone the same way.

The mode follows the map: a map at `Status: charting` with no ticket and nothing under Not yet specified is
**charted**; any other map is **worked through**. Either way, **never resolve more than one ticket per
session**, with the exception of research tickets.

Before the first step: `<state>` resolves as in the grill's preconditions, and the map exists (the CEO wrote it
with `map.sh new --next --destination "<the request>"` at intake; if not, step 3b prints the `map.sh new` line).
The request's parents are the task files whose frontmatter says `request: <R-id>`; read each one's `## Context`
and `## Related issues` from triage.

### Chart the map

1. **Name the destination.** Sharpen the request and the triage reports into the spec, decision or change this
   map is finding its way to, and write it with `map.sh set <R-id> destination`, the domain and standing
   preferences with `set notes`, the first terms with `set terms`. The destination fixes the scope, so it's
   settled first. If it cannot be named without the human, the first grilling ticket asks for it and every
   other ticket is blocked by it: charting itself asks nothing, the request runs on its own until the first
   grilling ticket.
2. **Map the frontier**, **breadth-first**: fan out across the whole space and every repository of the request
   rather than deep on any one thread, surfacing the open decisions and the first steps takeable now. **If this
   surfaces no fog** (the way to the destination is already clear), the map needs no tickets: `map.sh clear`
   exits 0 on it, run `map.sh status <R-id> planned`, and continue in this session with the plain grill
   (`skills/grill/SKILL.md`) for `<T-id>`, `map.sh export <R-id> <key>` prepended to its spec. The other parents
   get their own grill steps.
3. **Write the fog**: what you can see coming but can't phrase yet into **Not yet specified**
   (`map.sh set <R-id> fog`), and any boundary into Out of scope.
4. **Create the tickets you can specify now** with `map.sh ticket`, then wire blocking edges in a **second
   pass** (a ticket needs its number before another can reference it): `map.sh wire <R-id> <NN> --blocked-by
   <NN>,<NN>`. `--blocked-by` on `map.sh ticket` wires at creation when the blocker's number is already
   printed. Wiring sorts them into the frontier and the blocked; everything you can't yet specify stays in the
   fog. A cycle is refused.
5. **Fire the research subagents.** Claim every research ticket on the frontier and run deep-research for each
   in parallel, one subagent per ticket in the background. When the `researcher` role is full the Agent call is
   denied with the `capacity.sh wait researcher` line to run; do that, then call it again. As each returns,
   check its report, commit it, and `map.sh resolve` the ticket with the gist and the path.
6. Stop: charting is one session's work; it hand-resolves nothing but research. End with the frontier in one
   line per ticket, by name.

### Work through the map

A ticket is **optional**: without one, you pick the next decision, not the human.

1. Load the **map** (`cat` it) and `map.sh frontier <R-id>`: the low-res view, not every ticket body.
2. Choose the ticket. If one was named, use it. Otherwise take the first frontier ticket in order; research
   tickets on the frontier are fired first, all of them, as in chart step 5. **Claim it** before any work.
3. Resolve it. **Zoom as needed**: read the full file of any related or resolved ticket on demand; follow the
   skills the map's Notes name. For a grilling ticket, if the map is still `charting`, run
   `map.sh status <R-id> grilling` before the ask. The ask's frontmatter is `task: <T-id>`, `flow: wayfinder`,
   `step: Step 3b of 16: chart <R-id>`; end your turn, and the answer arrives as the next user turn.
4. Record the resolution: `map.sh resolve <R-id> <NN> --by <session_id>`, the answer on stdin, its first line
   the gist that reads alone in Decisions so far, the detail under it. That one call writes the answer, closes
   the ticket and appends the context pointer to Decisions so far.
5. Add newly surfaced tickets (create, then wire); graduate any fog the answer has made specifiable, writing
   Not yet specified back without each graduated patch so it lives only as its new ticket. If the answer
   reveals that a ticket (this one or another) sits beyond the destination, **drop it** rather than resolving it
   on the route. A ticket whose question this decision settled or changed is left for the next session, which
   resolves it by pointing at this decision; a changed question becomes a new ticket and the old one is resolved
   as superseded by it.
6. When `map.sh clear <R-id>` exits 0 after your writes, run `map.sh status <R-id> planned` (a reopened map:
   see Status) and stop. The grill of each parent follows.

Research sessions and the chart session may run while you work, so expect other writes to the map between two
of your calls; `map.sh` serializes them, and you reread the map before any `set`.

## The map feeds the grill

Once `map.sh clear <R-id>` exits 0, one grill runs per parent (solve-next step 4) with
`map.sh export <R-id> <key>` prepended to its spec: the destination, the decisions of the tickets with
`Repo: <key>` or `Repo: all` as pre-closed ledger rows, out of scope, and the terms. The grill never asks a
pre-closed row again. It ends in `repos/<key>/plans/<slug>-plan-ready.md` with `task:` and `request:` in its
frontmatter.

## Status

Every transition is a `map.sh status <R-id> <word>` call of the session that caused it: `charting` from
`map.sh new`; `grilling` when the first grilling ticket is asked; `planned` when the map is clear; `queued` on
the human's approval, `running` when the first lead starts and `done` after `task-done.sh` closes the last
parent, all three the CEO's. `planned`, `queued`, `running` and `done` need the map clear; `done` is final.

A reopened map: when a lead finds a need in another repository, the CEO adds
`map.sh ticket <R-id> grilling "<the need>" --repo <key>` and runs `map.sh status <R-id> grilling`; a planned,
queued or running map takes the ticket. It is worked like any grilling ticket: in scope, or dropped out of
scope. Once the map is clear again the CEO sets the status it had before, `running` while a lead of the
request lives.
