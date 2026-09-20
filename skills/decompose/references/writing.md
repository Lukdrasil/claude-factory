# Cut-check and writing

## Cut-check

Before anything is written, resolve the product clone for `<repo-key>`. When it has `docs/architecture/`, run
the `cut-check` invocation of the `architect-review` skill over the temporary task files. When it resolves and
has no such docs there is nothing to curate: skip it and say so in one line. When it cannot be resolved, stop
and ask the human where the clone is; do not skip the curation.

Then read `repos/<repo-key>/verdicts/<slug>.md` and recompute the plan hash per the verdict contract in
`architect-review`. Write the tasks only on `verdict: aligned` or `verdict: overridden-by-human` with a
matching hash. A `misaligned` verdict, a missing verdict file or a hash mismatch stops the write: tell the
human which of the three it is and create nothing.

When a verdict file was used, delete it and push that deletion; that commit concludes decompose.

## Writing through the Task API

With `DASHBOARD_URL` set, the write goes to the API. One task at a time, checking each response.

```sh
jq -n --arg repo "<repo-key>" --arg parent "T-005" --arg slug "<file-name-slug>" --rawfile markdown /tmp/task-1.md \
   '{repo:$repo, parent:$parent, slug:$slug, markdown:$markdown}' \
| curl -sS -w '\n%{http_code}\n' -X POST "$DASHBOARD_URL/api/tasks" \
    -H "Authorization: Bearer $DASHBOARD_API_TOKEN" \
    -H 'Content-Type: application/json' --data-binary @-
```

Send `parent` = the plan's frontmatter `task:` and leave `id` out of the body: the task is created as
`T-<parent>-NN`. With `task: none` drop `parent` too and the server takes the next free `T-NNN`. The file name
is the id plus a slug, by default the first six words of `# Goal`; send `slug` whenever the goal sentence would
cut mid-phrase, because the name is permanent.

| Response | What to do |
|---|---|
| `201` `{"id":..., "file":...}` | Created; `file` is its path in the state repo. Carry on with the next one. |
| `400` `{"error":...}` | Server-side validation of the frontmatter, the enums, the status, the branch, the id, the parent or the slug. Fix the markdown per the error text; do not resend it unchanged. |
| `401` | `DASHBOARD_API_TOKEN` is missing or does not match. Stop, so a human can fix it. |
| connection failed or `5xx` | The dashboard is unreachable, **no task was created** and nothing is written anywhere else. Tell the human: "Dashboard unreachable, no tasks were created; run decompose again once it is up." |

If a batch fails part-way, list which ids were created and which were not; on a retry send only the missing
ones. The server validates the frontmatter, never the quality of the acceptance: that is on you and the human.

## Writing locally

Without `DASHBOARD_URL` there is no dashboard. From the state clone:

```sh
sh <plugin-root>/bin/task-new.sh --repo <key> [--parent T-NNN] [--slug <slug>] --file /tmp/task-1.md
```

It prints the same `{id, file}` shape as the `201` above and exits 1 with the reason instead of a `400`, so
the id it returns is the one you use in `depends_on` and report to the human either way.
