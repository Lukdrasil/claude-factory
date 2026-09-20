# Cut-check and writing

## Cut-check

Before anything is written, resolve the product clone for `<repo-key>`. When it has `docs/architecture/`, run
the `cut-check` invocation of the `architect-review` skill over the generated task files. When it resolves and
has no such docs there is nothing to curate: skip it and say so in one line. When it cannot be resolved, stop
and ask the human where the clone is; do not skip the curation.

Then read `repos/<repo-key>/verdicts/<slug>.md` and recompute the plan hash per the verdict contract in
`architect-review`. Write the tasks only on `verdict: aligned` or `verdict: overridden-by-human` with a
matching hash. A `misaligned` verdict, a missing verdict file or a hash mismatch stops the write: tell the
human which of the three it is and create nothing.

When a verdict file was used, delete it and push that deletion; that commit concludes decompose.

## Writing

From the state clone, one task per manifest line, in manifest order, so a block's dependencies already have
ids when its turn comes:

```sh
sh <plugin-root>/bin/task-new.sh --repo <key> [--parent T-NNN] --slug <slug> --file /tmp/decompose-<slug>/01-<slug>.md
```

`--parent` is the plan's frontmatter `task:`; the block is created as `T-<parent>-NN`. With `task: none`
drop `--parent` and the next free `T-NNN` is taken. `--slug` is the slug of the generated file name, without
its `NN-` prefix: it is the proposal's title, while the default would be cut from the conventional-commit
`# Goal` line, and the name is permanent.

It prints `{"id":..., "file":...}` and exits 1 with the reason instead of writing. Before each call, rewrite
that file's `depends_on: []` to the ids already returned for the ordinals its manifest line names. If a batch
fails part-way, list which ordinals were created and which were not; on a retry send only the missing ones.
The script validates the frontmatter, never the quality of the acceptance: that is on the grill and the
human.
