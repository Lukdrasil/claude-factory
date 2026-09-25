---
name: memory-daily
description: The daily memory pass over one scope. Every proposal in the scope's queue is judged by Q7 by reading only, a verified lesson creates or updates a draft of the agent's playbook for the repo, a one-off is rejected, a one-lesson draft older than 7 days is deleted, then the pass is stamped. Runs as an interactive step session the CEO dispatches after the human's go, never headless.
---

# memory-daily

The lesson store has two levels (agent-org plan 3.8, Q3): the proposal queue a session writes into
(`_shared/knowledge-review.md`) and the drafts beside it. This pass moves what holds from the first to the
second, once a day per scope. It never writes `playbook.md` (the weekly pass does, with the human), a plugin
file, or anything outside the paths of this scope.

## Preconditions

- An interactive session the human said go for: a step session the CEO dispatches
  (`session-monitor.sh --step pass`), or one the human types. Never `claude -p` or any other headless run.
- The argument is the scope: `repo-agent:<key>/<agent>` (`<key>/<agent>` means the same), or a legacy tier
  `global`, `repo:<key>`, `agent:<agent>`. An optional second word `filed` (M2, once per scope) adds the
  scope's filed lessons. No scope: ask for it through `_shared/ask.md`.
- cwd is the state clone `$WORK_DIR/state`; the paths below are relative to it. The product clone is the
  `path:` of the key in `repos.yml`.
- **Reading only**: Read, Grep, Glob, `git log`, `git show`. No build, no test run, no edit of a product clone.

| scope | queue | filed lessons (`filed`) | drafts |
|---|---|---|---|
| `repo-agent:<key>/<agent>` | `repos/<key>/agents/<agent>/memory/proposals/` | `repos/<key>/agents/<agent>/memory/` | `repos/<key>/agents/<agent>/drafts/` |
| `global` | `memory/global/proposals/` | `memory/global/` | the repo x agent drafts a lesson names |
| `repo:<key>` | `repos/<key>/memory/proposals/` | `repos/<key>/memory/` | the same |
| `agent:<agent>` | `agents/<agent>/memory/proposals/` | `agents/<agent>/memory/` | the same |

## Q7, the one test

A lesson is kept only when all three hold; name the one that fails when it does not.

1. **Beyond one task**: it changes what a session does on another task, not only explains this one.
2. **The evidence reproduces**: the `path:line` still says it on the default branch, the commit exists, the
   file or command it cites still reads that way.
3. **No live skill covers it**: not the agent's plugin file or the skills it runs, not `playbook.md`.

## Steps

1. **List** the queue (top level, `*.md`), with `filed` the filed lessons too, and the drafts of the scope.
   Completion: every file is named once.
2. **Judge** each by Q7, reading its evidence. A lesson moves into a repo's tier only when it names that
   repo. Completion: every file has one verdict: **one-off** (the failing part of Q7), **draft** (a repo x
   agent draft: the scope's own, or in a legacy scope the one of the repo and agent the lesson names), or,
   in a legacy scope, **keep** (it holds but names no repo or fits no single agent).
3. **Apply**, one proposal at a time, with `<plugin-root>/bin/` and `--state $WORK_DIR/state` on every call:
   - one-off: `curate-apply.sh reject <proposal> --reason "<the failing part of Q7>"`.
   - draft: an existing draft that says the same thing first (read the titles), then add a lesson line to it;
     otherwise a new `drafts/<slug>.md` in the format below. Remove the proposal and commit both in one:
     `state-commit.sh -m "chore(memory): draft <slug> from <proposal>" -- <draft> <proposal>` (a proposal
     that was never committed is removed and left out of the paths).
   - keep: never approved here. Approve deletes every file a `Replaces:` line names, and policy-guard allows
     `curate-apply.sh approve` to the `ceo` role only: the proposal stays in the queue for the weekly round,
     where the CEO approves it after the human's yes (`pass-stamp.sh --due weekly` lists the scope), and the
     report names it `keep, <why it stays in this tier>`.
   - a filed lesson is never deleted here: a draft verdict adds its line with `Source: <path>`, and the weekly
     pass deletes the source once the human promotes that draft; every other verdict goes into the report
     only (retiring filed lessons is `factory consolidate`'s).
   Completion: the queue holds only the proposals of a keep verdict.
4. **Age the drafts** of the scope's own `drafts/`: a draft with one lesson line dated more than 7 days ago is
   deleted (Q6), `state-commit.sh -m "chore(memory): drop draft <slug>, one lesson for 7 days" -- <draft>`.
   Completion: no such draft is left.
5. **Stamp**: `pass-stamp.sh daily <scope>`. Completion: exit 0 and its line printed.
6. **Report**: the counts (read, one-off, drafted as new, drafted into an existing draft, kept for the weekly
   round, drafts deleted), then one line per file, `<path> -> <verdict>, <reason or draft>`.

## Draft format

```markdown
# <the rule in one sentence, as the playbook would say it>

<the playbook text: what to do and why, under 80 words>

Lessons:
- <YYYY-MM-DD, the day this pass drafted it> <task id>: <evidence, `path:line` or SHA> [Source: <filed path>]
```

A draft grows by lesson lines, never by a second rule: a different rule is a different draft.
