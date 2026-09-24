---
name: memory-weekly
description: The weekly memory pass over one repo x agent scope, run inside the CEO session after the human's go. The memory-curator judges the drafts, the human decides their promotion into the playbook in rounds, the yes is applied, what was promoted is deleted, a plugin change becomes a K1 draft for a human PR, then the pass is stamped.
---

# memory-weekly

Nothing reaches a playbook without the human (agent-org plan 3.8, Q5). This pass prepares the promotion of the
drafts the daily pass (`memory-daily`) wrote, asks the human in rounds, and applies only the answers.

## Preconditions

- Inside the CEO session, after the human's go (typed, or the Memory tab's start button, which posts `start
  the weekly pass for <scope>`). Never `claude -p` or any other headless run.
- The argument is `repo-agent:<key>/<agent>` (`<key>/<agent>` means the same). A legacy tier (`global`,
  `repo:<key>`, `agent:<agent>`) has no drafts: say so and stop, nothing is stamped. No scope: ask for it
  through `_shared/ask.md`.
- cwd is the state clone `$WORK_DIR/state`. The scope's folder is `repos/<key>/agents/<agent>/`: `drafts/`,
  `k1/`, `playbook.md` (at most 800 words), `passes.yml`.

## Steps

1. **Read** every `drafts/*.md`, `playbook.md` (`wc -w`) and the open `k1/*.md`. No draft: stamp (step 6)
   and report. Completion: the drafts are listed with their lesson counts.
2. **Judge.** Spawn the `memory-curator` agent with a brief naming the scope, the draft paths, the
   playbook path and the agent's plugin files (`agents/<agent>.md` and the skills it runs). Its report
   holds one verdict per draft (promote, k1, wait, drop), the whole playbook as it would read after every
   promote, and its word count. Completion: every draft has a verdict and the word count is at most 800.
3. **Rounds.** Through `_shared/ask.md` (flow `memory`, step `weekly <scope>`), at most five drafts per
   round, one question per draft: its title, its lessons, the curator's text or edit, and the options
   promote, k1, wait, drop with the curator's verdict as the recommendation. An open K1 draft is a notice in
   the first round, and one the human calls merged is deleted in step 4. Completion: every draft of the
   round has an answer.
4. **Apply the round.**
   - promote: write the answered text into `playbook.md` (the curator's whole playbook, less what the human
     declined; still at most 800 words), delete the draft and every `Source:` file its lesson lines name.
   - k1: write `k1/<slug>.md` in the format below and delete the draft.
   - wait: nothing. drop: delete the draft.
   One commit per round: `<plugin-root>/bin/state-commit.sh -m "chore(memory): weekly <scope>, round <n>"
   --state $WORK_DIR/state -- <every path written or deleted>`. Completion: exit 0; the next round, until no
   draft is unanswered.
5. **K1 to the human.** Name each new `k1/` file: the human turns it into a PR on the plugin (Q2), never this
   session. Completion: the list is in the report.
6. **Stamp**: `<plugin-root>/bin/pass-stamp.sh weekly <scope> --state $WORK_DIR/state`. Completion: exit 0.
7. **Report**: promoted, K1, waiting, dropped, the playbook word count, the open K1 drafts.

## K1 draft format

```markdown
# <the plugin change in one sentence>

Target: <plugin path and section, e.g. skills/block-feature/SKILL.md, ## Steps>
Edit: <the text to paste>
Why: <why it holds for the role in every repo>
Evidence: <the lesson lines of the draft>
```
