# factory cross-repo

`factory cross-repo <T-id>`: the cross-repo need a lead reported for its parent `<T-id>`, handled in a session
of its own that the CEO dispatches (`session-monitor.sh --task <T-id> --step cross-repo`, `references/ceo.md`).
It runs in the state clone as `FACTORY_ROLE=cross-repo`, unit `<T-id>-cross-repo`. The need is the
`## Cross-repo need` section of the parent's progress file (repo, what, why, evidence, the blocks that depend on
it). You never message a lead: the CEO does, once you report. Every question to the human goes through
`_shared/ask.md` with flow `cross-repo` and task `<T-id>`.

## Steps

1. **Read the need** and the parent's `request: <R-id>`. No section committed is nothing to handle: step 4 with
   `stopped no need committed`.
2. **Ask** in the map: `sh <plugin-root>/bin/map.sh ticket <R-id> grilling "<the need>" --repo <key>` with the
   section on stdin, then `sh <plugin-root>/bin/map.sh status <R-id> grilling`, and one confirm ask: is the need
   in scope of the request? Resolve the ticket with the answer on stdin, `map.sh resolve <R-id> <NN>`.
3. **Act on the answer.**
   - In scope: a new parent in that repository under the same request id (`references/intake.md` step 3), the
     new id added to `depends_on:` of each dependent block (`sh <plugin-root>/bin/state-commit.sh -m
     "<message>" -- <files>`), then `sh <plugin-root>/bin/dag-check.sh <T-id>`.
   - Out of scope: `sh <plugin-root>/bin/map.sh drop <R-id> <NN>` with the reason on stdin, which lands under
     Out of scope, and one confirm ask whether it becomes a request of its own.
4. **Report** to the CEO: `herdr agent prompt ceo "<T-id> cross-repo in scope <new T-id>"`, `"<T-id> cross-repo
   out of scope"`, or `"<T-id> cross-repo stopped <reason>"`. On a yes to a request of its own, a second line
   `request: <the need in one line>, priority <P>` with the parent's priority. A refusal means the CEO sits at a
   dialog: send it again, up to 3 times, 10 seconds apart, then go on.
5. **Close your own tab**: `herdr tab close "$HERDR_TAB_ID"`. This ends the session.
