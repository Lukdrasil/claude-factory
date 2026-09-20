# factory init

Sets the machine up once: the factory root, `state/` as the local state repo, `WORK_DIR` in the settings,
then the current clone registered and checked.

## Interview

Ask at most 6 questions, each with a default the user can accept as is:

1. **Factory root**, default `~/factory`, never inside a product repo. Becomes `--root`.
2. **State repo**: adopt an existing `<root>/state`, its `repos.yml` byte for byte, or create it.
3. **State remote**, optional, default none. When given, `git -C <root>/state remote add origin <url>`
   after the apply step.
4. **Git identity**, only when `git config user.email` prints nothing.
5. **Register the current repo now?**, default yes when the cwd is a git clone with an origin remote.
6. **How tasks start**, only when `herdr` is on PATH: `herdr` opens each task as its own interactive
   session in its own tab, `manual` prints the command for you to run. Default `herdr` when it is
   installed, `manual` otherwise. Becomes `--spawn`. On a machine with no herdr, skip the question and
   say nothing: the default already answers it.

Completion: every answer recorded, from the user or the stated default.

## Steps

- **Preview.** `<plugin-root>/bin/factory-init.sh --root <root>` without `--yes`, plus `--settings <file>`
  when the settings live elsewhere than `~/.claude/settings.json`. Exit 0 with `nothing to do`: continue at
  Register. Exit 3: the output is the diff over the state repo, `repos.yml` and the settings file gaining
  `env.WORK_DIR`.
- **Confirm.** Show the diff and ask with AskUserQuestion whether to apply it. Completion: a yes or a no.
- **Apply.** On a yes, rerun the same command with `--yes`. Completion: exit 0, `applied`, a commit in
  `git -C <root>/state log --oneline`. On a no: report the diff and stop.
- **Identity and remote.** Set what questions 3 and 4 asked.
- **Register.** On a yes to question 5, follow `references/add-repo.md` for the cwd clone. Completion: the
  key is on a `<key>:` line in `<root>/state/repos.yml`.
- **Doctor.** Follow `references/doctor.md` for the same clone and offer the fixes it names.

Tell the user that the next session picks `WORK_DIR` up from the settings file; this one keeps its old
environment until it restarts.
