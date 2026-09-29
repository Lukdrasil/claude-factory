# factory list

Every task in the state repo with its status, on one line each. Read-only: it writes nothing and commits
nothing, so it needs no confirmation.

## When

- the user asks what tasks there are, what is in flight, what is waiting for approval or who holds what;
- before `approve` or `done`, to find the id;
- after `solve`, to show where the task landed.

## Steps

- **Run.** `<plugin-root>/bin/factory-list.sh --root <root>` (`<root>` is `WORK_DIR`). Narrow it with
  `--repo <key>` and `--status <s>[,<s>…]`: the statuses are the ones `task-new.sh` accepts
  (`draft triaged ready claimed in_progress tests_ready review blocked failed done closed`).
  Completion: exit 0 and one line per task, or no output when nothing matches.
- **Show it.** Print the table as it came out, the columns are id, status, archetype, tier, repo, owner
  and the goal line. Sort or group only when the user asked for it. Completion: the user has the list.
- **Read the state out loud.** Say which tasks wait on the human (`triaged` needs `approve`, `review` needs
  the MR validated and then `done`) and which are held by a session (`owner:` is not `-`). Completion: every
  status in the output is either self-explanatory or explained.

An empty output means no task matched, not a broken factory; `factory-list: <root>/state/repos is not
there` means `--root` is not the factory root, check `WORK_DIR`.
