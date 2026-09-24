# factory add-repo

Registers a product clone in the standalone state repo and seeds its toolset. Once per clone, from the
clone or with `--repo <clone-dir>`; a registered clone with a toolset is `nothing to do`.

## When

- after `init`, for the repo the user works in;
- for every further clone the user wants factory sessions on;
- when `doctor` reports `missing: <key> in state/repos.yml` or `missing: repos/<key>/toolset.md`.

## Steps

- **Preview.** Run `<plugin-root>/bin/factory-add-repo.sh --root <root> --repo <clone-dir>` (`<root>`
  is `WORK_DIR`). It prints what it would write as two commits in `<root>/state`, the
  `<key>: {url, default_branch, path}` line for `repos.yml` (the key is the origin URL's basename without
  `.git`) and the `repos/<key>/toolset.md` it would seed from `<plugin-root>/toolsets/<stack>.md`
  (the stack is detected from the clone's files), and exits 3 without writing. Ask with one confirm
  (`_shared/ask.md`) that carries that output verbatim as a fenced block (```` ```diff ````) between the question
  line and the options yes and no. Completion: a yes recorded.
- **Run.** After the yes: the same command with `--yes`. Completion: exit 0.
- **Read the output.** The first line is the key; then `registered …` / `toolset …` lines, or
  `nothing to do`. A `note: stack <stack> has no toolsets/<stack>.md yet` on stderr means the repo is
  registered without a toolset: tell the user and offer to write `repos/<key>/toolset.md` by hand, using the
  command vocabulary of `toolsets/dotnet.md` in this plugin. Completion: the user knows the key
  and whether a toolset exists.
- **Emoji, optional.** An `emoji:` in the repo's `repos.yml` line (`<key>: {url: …, path: …, emoji: 🦊}`) is
  the repo's mark in the session name `<emoji> <key> <id>` that `session-monitor.sh` gives every herdr tab and
  `claude --name`. Without it the repo gets a fixed pick out of sixteen by the key, the same on every run;
  set one when two repos pick the same. Completion: the user was offered it.
- **Check the toolset.** Open `<root>/state/repos/<key>/toolset.md` and compare the bindings with what the
  repo runs (solution path, test filter syntax). Edit the rows that lie, delete the rows the repo cannot
  bind, commit in the state repo. Completion: no `{{…}}` placeholder left and every remaining row is a
  command the repo runs.
- **Next.** Follow `references/doctor.md` for the same clone.
