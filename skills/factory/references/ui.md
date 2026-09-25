# factory ui

Starts or stops the Factory UI, the container `ui/README.md` describes. It writes nothing to the user's settings
or to the state repo, so it needs no confirmation.

## When

- the user asks to start, open or show the UI, or for its URL: `ui`;
- the user asks to stop it: `ui down`.

## Steps

- **Start.** `sh <plugin-root>/bin/ui-up.sh --state <root>/state` (`<root>` is `WORK_DIR`; without a
  `state/repos.yml` there, run it with no `--state`). The first run builds the image, which takes minutes.
  Completion: exit 0 and the printed URL `http://127.0.0.1:<port>/#token=<token>` given to the user as it came
  out, since the page shows nothing without the token.
- **Stop.** `sh <plugin-root>/bin/ui-down.sh`. Completion: exit 0.

Exit 3 means Docker is not running, exit 4 that this session is not inside herdr (`HERDR_ENV=1`): report the
line it printed, do not work around it. A change under `ui/` needs `docker image rm claude-factory-ui:<version>`
before the next start, since `ui-up.sh` reuses an existing image.
