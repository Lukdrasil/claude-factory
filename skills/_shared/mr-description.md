# MR description

`sh <plugin-root>/bin/mr-open.sh <id> [--issues <file>]` builds the description from the task and its
progress file and opens the MR, and it refuses what the contract refuses.

The rules it checks: the sections **What changed**, **Why**, **Issues**, **How to verify** and
**Follow-ups**, in that order, one with nothing to say left out, the whole thing **under 120 words**, short
sentences, written for whoever reviews the MR and not for the factory.

The title is `# Goal` as it stands, with no id in front of it, so the goal line is written as a title:
**Conventional Commits** (`type(scope): subject`, type one of feat, fix, chore, docs, refactor, test,
perf, build, ci) and **at most 130 characters**. The type is what the release tooling reads the semver
bump off. `mr-open.sh` and `block-mr.sh` both refuse a title that breaks either rule, before they call
the forge; the fix is the task's `# Goal` line, not the command.

What it never says: the task or block id, the archetype, tier or complexity, the review verdict, the
progress file, state-repo paths, attempt counts, subagent names. None of it means anything to a reviewer,
the task file already records it, and `mr_url` is the link back.

The `Issues` line comes from the `--issues` file. Spawn `mr-issue-linker`
(`<plugin-root>/skills/_shared/delegation.md`) to write it with the goal, the acceptance command and the
changed files; keep only issues it printed a number and a title for, and downgrade a `closes` the issue text
does not confirm to `refs`. Skip the spawn when the task names its source issue and the diff stays inside
that issue's scope: one lookup does not pay for a subagent. No forge or no match means no issue line.
