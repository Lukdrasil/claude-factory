---
name: logging-decisions
description: Decide what to log, at which level, with what data, into which sink and with what retention. Use while implementing, at a log call or a caught exception, and when a review touches log levels, noisy logs or alerting.
---

# Log level decisions

One question decides every entry: **who does what, and when, because this entry exists?** That is the actor
test. An entry nobody acts on is mis-levelled or should not exist, and noise hides the entry that matters.

| Who acts on the entry | Level |
|---|---|
| On-call, right now | Critical |
| Somebody opens a ticket soon, the failure was unexpected | Error |
| Somebody, before a future Error (a measurable precursor) | Warning |
| Nobody. An expected event worth a record | Information |
| Nobody. It serves an investigation, off by default | Debug or Trace |
| Nobody, ever | Remove the entry |

## Rules

- The level is what the team does, not how serious the text sounds. A Critical open for days is wrong.
- **An exception is not automatically an Error.** Catch the expected cases first and specifically: a
  cancelled request, a dropped client, invalid input, a missing record, a version conflict. Handle them and
  log at Information or not at all. Only the remainder is an Error.
- A Warning is a **measurable precursor** with a stated consequence, such as "disk at 92 %, writes fail at
  100 %". Bad input and a user-facing 404 are not warnings.
- Attach only the data needed to act. **Never personal data**, secrets, tokens or full payloads; a hashed
  id when identity is needed.
- **No browser console output in production.** Tell the user in the interface, or send it to a log service.
- **Log once**, at the boundary that decides the outcome, structured and with a category, never per layer.
- Traces answer "how long", logs answer "what needs action". Sample traces freely. **Never sample Error** or Critical.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md` for the catch order, configuration and redaction.
   Without a toolset or a reference, apply these rules with the language's standard logging API. Done when
   you know which reference applies.
2. **List the scope**, one row per log call and per catch block. Done when none is missing.
3. **Apply the actor test to each row**: who acts and when, then the level that follows, or "remove". Check
   the catch order (specific and quiet first), the attached data, and the sink per
   `${CLAUDE_SKILL_DIR}/references/sinks.md`. Done when every row carries a level and its rule.
4. **Write the review** in the shape of `${CLAUDE_SKILL_DIR}/references/review-shape.md`. Done when every
   row is a finding there or is accepted.

## References

- `${CLAUDE_SKILL_DIR}/references/review-shape.md`: the review output and its groups.
- `${CLAUDE_SKILL_DIR}/references/sinks.md`: sink routing and retention per application class.
- `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`: the stack's catch order and redaction.
