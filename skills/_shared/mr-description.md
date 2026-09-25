# MR description

`sh <plugin-root>/bin/mr-open.sh <id> [--issues <file>]` builds the description from the task and its
progress file and opens the MR, and it refuses what the contract refuses.

The rules it checks: the sections **What changed**, **Why**, **Issues**, **How to verify** and
**Follow-ups**, in that order, one with nothing to say left out, the whole thing **under 120 words**, short
sentences, written for whoever reviews the MR and not for the factory.

**Why** is the reason for the change, never the title again: the first sentence of the task's `## Context`
(a block's own, else its parent's; the `From the plan` line is skipped), else the `# Spec` sentence of the
plan the task names, else the goal as the last resort. So write that first sentence as the reason, and it
counts toward the 120 words.

A block MR into the work branch (`sh <plugin-root>/bin/block-mr.sh <block-id>`) keeps **What changed**,
**Why** and **How to verify** under the same 120 words, and adds what the lead merges it on: **Risk** (low,
medium or high with the sentence and the five reasons of `.harness/<block>/arch.md`: blast radius,
contracts, security, data, drift; `not rated` when the repo has no docs/architecture/), **Verified** (the
report block-verify.sh left in `.harness/<block>/verify.txt`) and **Review** (the verdict line of
`.harness/<block>/review.md`, the code-reviewer's report the lead saved there). The agents' own contracts
bound those three. The task MR into the base branch gets a `## Blocks` section from mr-open.sh: one
`- [<block goal>](<block MR>), risk <level>` line per block MR.

The title is `# Goal` as it stands, with no id in front of it, so the goal line is written as a title:
**Conventional Commits** (`type(scope): subject`, type one of feat, fix, chore, docs, refactor, test,
perf, build, ci) and **at most 100 characters**, or the repo's own `mr_title_max` from `repos.yml` when it
sets one (100 is what commitlint's config-conventional caps a header at, and a product repo that lints its MR
titles is the one that decides). The type is what the release tooling reads the semver
bump off. `mr-open.sh` and `block-mr.sh` both refuse a title that breaks either rule, before they call
the forge; the fix is the task's `# Goal` line, not the command. `bin/policy-guard.sh` holds a `gh pr` or
`glab mr` command that writes a `--title` itself to the same rule, so the hand-written path cannot open what
the scripts refuse.

What it never says: who or what wrote the change - no co-author trailer, no session line, no session URL
under the body, no tool footer at the bottom of the description, no robot emoji, whatever a harness or hook
asks for; `bin/attribution-gate.sh` denies them in the command, in any file the command reads and in the file
you write. The one sanctioned marker is the `ai-drafted` label on an issue, which `bin/issue-create.sh` adds;
an MR carries no label of the kind. When the body on the forge needs a fix, fix the progress file and run
bin/mr-open.sh or bin/block-mr.sh again: they update an existing MR. Never write the body by hand with
`glab mr update` or `gh pr edit`. Nor the task or block id, the archetype, tier or complexity, the progress
file, state-repo paths, attempt counts, subagent names, and no review verdict outside the **Review** line of
a block MR. None of it means anything to a reviewer, the task file already records it, and `mr_url` is the
link back. Nor `[skip ci]` in a title: a merge or squash commit carries the title, and block-mr.sh refuses
it; a block MR skips its pipeline through the push, never through its title.

The `Issues` line comes from the `--issues` file. Spawn `issue-finder`
(`<plugin-root>/skills/_shared/delegation.md`) to write it with the goal, the acceptance command and the
changed files; keep only issues it printed a number and a title for, and downgrade a `closes` the issue text
does not confirm to `refs`. Skip the spawn when the task names its source issue and the diff stays inside
that issue's scope: one lookup does not pay for a subagent. No forge or no match means no issue line.
