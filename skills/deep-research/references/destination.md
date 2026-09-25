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
reads or archives it. A research ticket of a request map always lands under `repos/<key>/research/`, the key
the wayfinder skill names for it.

## The commit

Commit the report alone, under the state lock every writer shares, with the state clone the preconditions
resolved named explicitly, so the cwd (the product clone whenever the state clone is `$WORK_DIR/state`) does
not matter:

```sh
sh <plugin-root>/bin/state-commit.sh -m "research: <topic>" --state <state clone> -- <path to the report>
```

It never pushes: `state-push.sh` publishes the commit in the background, run by the monitor pass and the CEO
loop, never by you. Exit 2 means another session held the lock or git refused the commit; run it again. If it
still fails, say so in the summary: an uncommitted report exists only in this session.
