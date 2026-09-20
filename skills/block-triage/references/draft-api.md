# Creating the draft

`DASHBOARD_URL` and `DASHBOARD_API_TOKEN` are in the session environment; the controller sets them for
triage. Two parallel triages once computed "highest number + 1" from their own clones and both produced
`T-005`, so the API allocates under a lock and refuses a taken id, which git does not.

- `<new-id>` is `T-` plus the highest number in `GET /api/tasks` plus 1, zero-padded to three digits.
- `<slug>` is 2 to 4 words from the issue title, lowercase and hyphenated; the file becomes `<new-id>-<slug>.md`.
- For `archetype: ops` omit the `branch:` line entirely, an ops task having no product clone, and spell the
  action out concretely under `## Context`: `block-ops` does only what is in the task.

Write the markdown into a file **next to** `state/`, for example `../draft.md`, so it cannot end up in a
commit, check the frontmatter against the template, and send it:

```sh
curl -sS -H "Authorization: Bearer $DASHBOARD_API_TOKEN" "$DASHBOARD_URL/api/tasks" | jq -r '.tasks[].id' | sort | tail -1
jq -n --arg repo "<key>" --arg id "<new-id>" --arg slug "<slug>" --rawfile markdown ../draft.md \
   '{repo:$repo, id:$id, slug:$slug, markdown:$markdown}' \
| curl -sS -w '\n%{http_code}\n' -X POST "$DASHBOARD_URL/api/tasks" \
    -H "Authorization: Bearer $DASHBOARD_API_TOKEN" -H 'Content-Type: application/json' --data-binary @-
```

| Response | What to do |
|---|---|
| `201` `{"id":..., "file":...}` | Created and pushed; `file` is the path for `## Evidence`. Run `git-guard fetch && git rebase` so your clone has it before the self-report commit. |
| `400` `... already exists ...` | Another session took the id; take the next number and send it again. |
| `400` other | Server-side validation of the frontmatter, the enums, the branch or the slug. Fix the markdown per the error text; do not resend it unchanged. |
| `401` | The token is missing or wrong. Self-report `failed` with that reason. |
| connection failed or `5xx` | The dashboard is unreachable. Self-report `failed`; nothing was created. |

Without `DASHBOARD_API_TOKEN` in the environment, fall back to writing the file into `repos/<key>/tasks/`
with the **Write** tool and committing it with the self-report, knowing the id can collide with a parallel
triage.
