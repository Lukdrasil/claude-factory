# Tiers

The one copy of the rubric a grill, a triage and a decompose decide by. Point here, do not restate it, and
carry one sentence of why in the file the decision is written into.

**tier**: `green` trivial and unambiguous, `yellow` an ordinary change with a proposal, `red` an impact on
architecture, data or security.

**archetype**: `feature` new functionality, `bugfix` broken behaviour, `refactor` a change of shape without a
change of behaviour, `research` a report rather than an MR, `ops` a small non-destructive forge action.

**complexity**: `low` short and local, `medium` the ordinary case, `high` needs a stronger model at dispatch.

A `red` task gets `spec-critic` before a human flips it to `ready`.
