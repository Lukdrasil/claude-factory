# factory add-repo

Registers a product clone in the standalone state repo with its id alias and seeds its toolset. Once per
clone, from the clone or with `--repo <clone-dir>`, or from a URL with `--clone <url>`, which clones it first
(see "From a URL"); a registered clone with an alias and a toolset is `nothing to do`. Every run refreshes the
Setup tab's `doctor.json` (`references/doctor.md`).

## When

- after `init`, for the repo the user works in;
- for every further clone the user wants factory sessions on;
- for a repository the user names by its URL (`add repo <url>[ alias <ALIAS>]`, typed or sent from the Setup
  tab), with `--clone`;
- when `doctor` reports `missing: <key> in state/repos.yml`, `missing: repos/<key>/toolset.md` or
  `missing: <key> has no alias`.

## Steps

- **Preview.** Run `<plugin-root>/bin/factory-add-repo.sh --root <root> --repo <clone-dir>` (`<root>`
  is `WORK_DIR`). It prints what it would write as two commits in `<root>/state`, the
  `<key>: {url, default_branch, path, alias}` line for `repos.yml` (the key is the origin URL's basename
  without `.git`; for a repo registered before aliases, its old line `-` and the new one `+`) and the
  `repos/<key>/toolset.md` it would seed from `<plugin-root>/toolsets/<stack>.md` (the stack is detected
  from the clone's files), and exits 3 without writing. The alias, 2 to 4 uppercase letters unique in
  `repos.yml`, makes the repo's new task ids `T-<ALIAS>-<n>`: `note: alias <ALIAS> proposed from the key`
  names the proposal (the initials of the key's words, else its first three letters, else the next free
  letters). Ask with one confirm (`_shared/ask.md`) that carries that output verbatim as a fenced block
  (```` ```diff ````) between the question line and the options yes, no and another alias. Completion: a yes, or
  an alias the user named, recorded.
- **Run.** After the yes: the same command with `--yes`; with another alias: preview again with
  `--alias <ALIAS>` and confirm that. Completion: exit 0.
- **Read the output.** The first line is the key; then `registered …` / `alias …` / `toolset …` lines, or
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

## From a URL (`--clone`)

The same steps, with `--clone '<url>'` in place of `--repo <clone-dir>`:
`<plugin-root>/bin/factory-add-repo.sh --root <root> --clone '<url>' [--alias <ALIAS>] [--yes]`.

- **Before any command.** The URL is text the human typed, and it lands in a command argument. Run nothing
  unless it matches `^[A-Za-z0-9._~:/@+-]+$`, does not start with `-`, and is `http://`, `https://`, `ssh://`
  or `user@host:path`; an alias must match `^[A-Z]{2,4}$`. Put the URL in single quotes exactly as received.
  Anything else is one notice (`_shared/ask.md`) that names the problem. Completion: the URL passed, or the
  notice is written.
- **Clones directory.** The clone goes to `<clones>/<key>`, `<clones>` being `clones: <absolute dir>` in
  `<root>/state/factory.yml`. It must be absolute and outside `<root>` (whose `<root>/<key>` holds the task
  worktrees), symlinks resolved. Without it the script exits 1 with
  `no clones directory: add clones: <absolute dir> to <state>/factory.yml`, which is the error notice below;
  the user adds that line (their other clones usually share one directory) and sends the URL again.
- **Preview.** It asks the remote with `git ls-remote` (no password prompt: the user's own git login, a
  credential helper, `gh auth login`, `glab auth login` or an ssh key has to work), then prints the key,
  `+ git clone <url> <clones>/<key>   (default branch <branch>)`, the alias note, the `repos.yml` line and
  `+ <state>/repos/<key>/toolset.md   from the stack found after the clone`, and exits 3 without cloning. The
  confirm carries that output as for `--repo`, with the ask id `add-repo-<key>`, flow `add-repo`, task `none`.
  An existing `<clones>/<key>` that is a clone of the same URL is reused (`note: ... reused`, no clone line).
- **Run.** After the yes, the same command with `--yes`: it clones into a temp directory
  `<clones>/.<key>.cf-clone` (one a killed run left is removed first), renames it to `<clones>/<key>`, prints
  `cloned <url> into <path>`, then registers as `--repo` does. Completion: exit 0.
- **A registered key.** The same URL again (user or token, a trailing `/` and `.git` aside) fetches and clones
  nothing: `nothing to do`, or the missing alias or toolset, in its registered `path:`. Another URL, or a
  `path:` that is no clone on disk, exits 1.
- **Exit 1 or 4.** 1 is a refusal (a bad URL, no clones directory, a key registered for another URL, a taken
  alias, a `<clones>/<key>` that is no clone of the URL), 4 means the remote cannot be reached (host, auth, no
  such repository). The reason and the fix are on stderr, with the user and token of every URL cut out: put
  both into one notice with the ask id `add-repo-<key>-error`, flow `add-repo`, task `none`. Completion: the
  notice is written, nothing retried.
- **Status for the Setup tab.** When the UI home exists the script keeps
  `<ui home>/setup/add-repo/<key>.json` current, `{"at","key","url","path","state","detail"}`: `pending` after a
  preview, `cloning` while it clones, `registered` at exit 0, `failed` at exit 1 or 4 with the reason as
  `detail`. It stores no user or token. Nothing to do for you.
