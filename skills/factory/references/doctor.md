# factory doctor

A report over one clone in the standalone factory: what a factory session on it will find and what is
missing. It gates nothing; the value is in the fixes you offer.

## When

- at the end of `init` and after `add-repo`;
- when the user asks what is missing, or a session noted a toolset command it could not run;
- before the first `solve` on a clone.

## Steps

- **Run.** `<plugin-root>/bin/factory-doctor.sh --root <root> --repo <clone-dir>` (`<root>` is
  `WORK_DIR`; `--repo` defaults to the cwd). Completion: exit 0 and one line per check.
- **Read the output.** `ok: …` needs nothing. `missing: <what> — <fix>` carries its fix after the dash:
  - registration or `repos/<key>/toolset.md` → `references/add-repo.md`;
  - a tool on PATH → the fix is its install command;
  - `stack` or `test-globs` → edit the toolset's frontmatter (shape in `toolsets/<stack>.md` of this
    plugin) and commit in the state repo;
  - `docs/architecture` → the architecture-docs bootstrap (the `architecture-docs` skill); recommend it —
    the architect review points run once the repo has a model.
  Completion: every line is sorted into one of these.
- **Offer the fixes.** One round (`_shared/ask.md`) with a question per tool that is missing, each naming its
  install command with the options yes and no, and for `docs/architecture` a question whether to start the
  architecture-docs bootstrap now or later. Run the command of every tool answered yes, then rerun doctor.
  Completion: every `missing:` line has a recorded answer, and the ones answered yes now print `ok:`.
- **Report.** Repeat the remaining `missing:` lines to the user with what each costs a session: a toolset
  command noted and skipped, no architect review without a model. Completion: the user has the list.
