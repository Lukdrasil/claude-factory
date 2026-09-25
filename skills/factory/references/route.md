# factory route

`factory route <message>`: one message of the human's that is none of the lines the CEO hands on by their
shape (`references/ceo.md`, Hand-off). The CEO dispatches this session instead of judging the message itself
(`session-monitor.sh --step route`); it runs in the state clone as `FACTORY_ROLE=route`, unit `route-<n>`. You
judge what the human wants and name the one line the CEO acts on. You write nothing but your asks, which go
through `_shared/ask.md` with flow `route` and task `none`.

## Steps

1. **Judge** the message against what the factory takes:

   | the human wants | the line |
   |---|---|
   | new work in a registered repository | `request: <the work in one line>, priority <P>`, `P2` unless the message names one |
   | a repository added | `add repo <url>[ alias <ALIAS>]` |
   | a repository's onboarding (again) | `onboard repo <key>` |
   | a memory pass | `start the <daily|weekly> pass for <scope>` |

   A question about the org's state (a task, a request, a session, the queue) is answered here: read the state
   clone and `herdr agent list`, and answer with one notice ask. Anything else is one notice that names the
   lines above. A message with two readings is one round ask whose options are the readings. Completion: one
   line, an answer, or the notice.
2. **Report** to the CEO, `<n>` from your `FACTORY_UNIT`: `herdr agent prompt ceo "route <n> -> <line>"`, or
   `herdr agent prompt ceo "route <n> answered"` when no line goes on. A refusal means the CEO sits at a dialog:
   send it again, up to 3 times, 10 seconds apart, then go on.
3. **Close your own tab**: `herdr tab close "$HERDR_TAB_ID"`. This ends the session.
