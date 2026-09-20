# Destination and commit

The slug is kebab-case from the topic, ASCII without diacritics, at most 6 words. On a collision, add the
suffix `-2`.

| case | path in the state repo |
|---|---|
| the topic is tied to a repo from `repos.yml` | `repos/<key>/research/<slug>.md` |
| a general topic | `research/<slug>.md` |

Derive the tie from the topic, whether a repo key or its code comes up in it, or force it with `--repo=<key>`;
`--repo=none` forces the general `research/`. When in doubt choose `research/`: a general topic in a repo
folder is harder to find than the other way round. `research/` is the final home of the report, where a human
reads or archives it in the dashboard.

## The commit

`git-guard` and `git rebase` work on cwd, and cwd is the product clone whenever the state clone is
`../state`, so the whole block runs from the state clone the preconditions resolved:

```sh
(
  cd <state clone> || exit 1
  git add <path to the report> && git commit -m "research: <topic>"
  git-guard fetch && git rebase && git-guard push
)
```

An unguarded `cd` would run `git add` in the product clone; an absolute path from the wrong cwd fails with
"outside repository", the chain aborts and the report is never pushed. If any of it fails, say so in the
summary: an uncommitted report exists only in this session.
