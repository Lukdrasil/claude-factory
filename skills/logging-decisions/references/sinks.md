# Sinks and retention

Read alongside step 3 of `<plugin-root>/skills/logging-decisions/SKILL.md`. Routing and retention follow
how much the application matters, not how much the team likes the entry.

| Application | Goes to the central sink | Goes elsewhere | Retention |
|---|---|---|---|
| Mission-critical | Critical, Error, Warning, and low-volume Information | Debug and Trace on demand, in a separate store | about 30 days |
| Support or internal tool | Critical, or nothing | a file or a secondary sink, read when convenient | days |

The central sink aims at zero false positives: every entry in it is one somebody acts on, so an entry that
nobody has acted on for a week belongs at a lower level or in the secondary store.

An Error still visible after 30 days should already be a ticket, so retention past 30 days serves only a
named audit requirement, and then in a separate secured store with its own access control. Retention is a
claim about obligations, not about disk: the store inherits every erasure obligation of the data the
entries carry, which is the second reason personal data never enters a log line.

A category per component is what makes Debug usable: the switch is per category, so an investigation raises
one component to Debug and leaves the rest at the default.

Source of the level rules: Tim Corey, *Dev Questions* episode 325.
