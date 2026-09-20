# factory consolidate

Runs the `memory-consolidate` skill's procedure over one or more memory scopes of the standalone state repo, in
this session — not a spawned research task. Result: proposals with `Replaces:` in the scope's `proposals/`
queue, then curated per `curation:` (`references/curate.md`) — the `memory-curator` agent when `auto`, the
human walk when `manual`.

## When

On demand only — the user asks to consolidate, or `factory doctor` names an over-budget scope
(`missing: memory over budget in <scope> — run factory consolidate <scope>`, `<plugin-root>/bin/memory-budget.sh`). Never
scheduled: consolidation is not part of `factory solve` or any hook.

## Scope argument

`factory consolidate [repo:<key>|global|agents|all]` — default `all` when omitted.

- `repo:<key>` — `<root>/state/repos/<key>/memory/`.
- `global` — `<root>/state/memory/global/`.
- `agents` — every `<root>/state/agents/*/memory/`, one pass per agent.
- `all` — every scope present: every registered repo, global, every agent with a memory dir.

## Steps

- **Resolve the scope(s).** From the argument; for `agents`/`all` enumerate the directories present, skipping
  an empty one.
- **Per scope, follow `memory-consolidate`'s procedure** (`<plugin-root>/skills/memory-consolidate/
  SKILL.md`) — read the scope, find duplicates/contradictions/staleness, write proposals with `Replaces:`
  pointing at the sources it replaces, at most five per pass. An agent's memory is the same procedure over
  `agents/<agent>/memory/` in place of a repo's.
- **Curate.** Once every scope's proposals are written, hand off to `references/curate.md`: `curation: auto`
  spawns `memory-curator` over them (with everything else this session wrote); `curation: manual` walks them
  with the human, same as any other proposal batch.
- **Report.** Per scope: files read, proposals written, and (once curated) the counts by decision.

## Completion

Every resolved scope has been read once, its findings are proposals (not silent edits — P6 holds), and every
proposal from this pass has a recorded decision, auto or manual.
