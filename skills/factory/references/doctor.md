# factory doctor

A report over one clone in the standalone factory and the machine it runs on: what a factory session on it
will find and what is missing. It gates nothing; the value is in the fixes you offer.

## When

- at the end of `init` and after `add-repo`;
- when the user asks what is missing, or a session noted a toolset command it could not run;
- before the first `solve` on a clone.

## Steps

- **Run.** `<plugin-root>/bin/factory-doctor.sh --root <root> --repo <clone-dir>` (`<root>` is
  `WORK_DIR`; `--repo` defaults to the cwd). Completion: exit 0 and one line per check.
- **Read the output.** `ok: …` needs nothing. `missing: <what>, <fix>` (not set up yet) and
  `failing: <what>, <fix>` (set up but wrong) name what is wrong, then its fix:
  - registration, `repos/<key>/toolset.md` or no alias (`its new tasks get legacy T-<n> ids`) →
    `references/add-repo.md`, which proposes the alias;
  - a tool on PATH → the fix is its install command;
  - `stack` or `test-globs` → edit the toolset's frontmatter (shape in `toolsets/<stack>.md` of this
    plugin) and commit in the state repo;
  - `docs/architecture` → the architecture-docs bootstrap (the `architecture-docs` skill); recommend it,
    the architect review points run once the repo has a model;
  - herdr (older than 0.8.2, its server, the Claude integration, toast delivery), python3, unpushed state
    commits, one alias on two repos, MR class C, a GitHub workflow without a branch filter, no `capacity:`
    → the fix is the command or the setting the line names; forge settings and herdr's `config.toml` are
    the human's to change.
  Completion: every line is sorted into one of these.
- **Offer the fixes.** One round (`_shared/ask.md`) with a question per tool that is missing, each naming its
  install command with the options yes and no, a question per other fix that writes (a command, or an edit of
  `factory.yml` or `repos.yml`), and for `docs/architecture` a question whether to start the
  architecture-docs bootstrap now or later. Run the command of every question answered yes, then rerun
  doctor. Completion: every `missing:` and `failing:` line has a recorded answer, and the ones answered yes
  now print `ok:`.
- **Report.** Repeat the remaining `missing:` and `failing:` lines to the user with what each costs a
  session: a toolset command noted and skipped, no architect review without a model, legacy ids without an
  alias, a waiting question nobody is told about without toasts. Completion: the user has the list.

## The Setup tab

`factory-doctor.sh --json [--root <root>] [--ui-home <dir>]` runs the checks machine wide and for every
registered repo and writes `<ui home>/setup/doctor.json` (`steps: [{id, state: done|missing|failing, detail,
fix}]`; the UI home is `$FACTORY_UI_HOME`, default `~/.claude-factory/ui`). `factory-init.sh` and
`factory-add-repo.sh` run it after every run, so the Setup tab is current after each. The steps, in order:
`git`, `node`, `python3`, `docker`, `herdr`, `herdr-server`, `forge-login`, `claude`, `state-repo`,
`state-remote`, `state-push`, `work-dir`, `prompt-suggestion`, `permissions`, `herdr-integration`, `herdr-toast`, `repos`,
`aliases`, then per repo `repo:<key>:path`, `repo:<key>:alias`, `repo:<key>:toolset`, `repo:<key>:mr-class`
(forge urls only) and `repo:<key>:workflows` (GitHub only), then `capacity`, `doctor` (green when every step
before it is done) and `ceo` (the command that starts the CEO). A fix is text: the session applies one only
after a confirm ask, as above.
