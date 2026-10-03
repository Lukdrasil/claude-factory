---
name: domain-invariants
description: Domain model rules for aggregates that guard their invariants, typed ids and value objects, and edge cases listed before a rule is coded. Use when writing an entity, aggregate, value object or business rule.
---

# Domain model and invariants

An **invariant** holds after every write, whatever path made the write. The aggregate owns it, so the
model makes an invalid state impossible to construct.

## Rules

1. **State changes go through methods on the aggregate**; setters are private.
2. **Creation goes through a factory that returns a result** for expected invalid input.
3. **Typed ids and value objects replace primitives** for anything with a grammar, a unit or a range.
4. **The domain has no persistence or framework references.**
5. **Domain events are dispatched after the commit.**
6. **An invariant holds on every write path**: create, update, replace, bulk, import, every UI flow. List the
   write paths before coding and test each.
7. **List the edge cases before coding a rule**, as test names: empty range, boundary day, month and year
   crossing, many records per key, overlapping periods, all-of versus one-of.
8. **Guards default to deny**: an unknown state or a missing input fails the rule.
9. **One definition per predicate** ("is active", "is editable"), referenced everywhere.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`. Done when you know which reference applies.
2. **List the write paths and edge cases** of every rule the change adds or edits. Done when each has a test
   name.
3. **Check the model against every rule.** Done when every row passes or is fixed.

## Wrong and right

- The rule used month bounds instead of the contract window, and checked one contract instead of all.
- An invariant was guarded on Add only. Right: also on edit and on the wizard path.
