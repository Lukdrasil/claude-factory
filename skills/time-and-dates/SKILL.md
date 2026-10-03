---
name: time-and-dates
description: Time and date rules for the injected clock, UTC instants, durations, ranges and culture-aware formatting. Use when code reads the clock, stores or compares a date, adds durations or formats a date.
---

# Time and dates

## Rules

1. **The clock is injected.** Code reads time only through it, so tests fix it.
2. **Instants are stored and compared in UTC with an offset.** Local time is a display concern.
3. **Calendar dates are date types**, not instants at midnight.
4. **Durations are summed as duration types** and converted to hours or decimals only at the edge.
5. **Time-of-day arithmetic that can cross midnight reports the wrapped days**, and a test crosses midnight.
6. **Every range states inclusive or exclusive ends**, and a test hits both ends.
7. **Formatting and parsing name the culture**: invariant for the wire and storage, the user's for display.
8. **No value is null**, never the default or minimum date.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`. Done when you know which reference applies.
2. **List every clock read, date comparison, duration sum and date format** in the change. Done when none
   is missing.
3. **Check each against every rule.** Done when every row passes or is fixed.

## Wrong and right

- `TimeOnly.Add` wrapped past midnight silently. Right: the overload with `out int wrappedDays`.
- Hours were summed as `double`. Right: sum `TimeSpan`, convert once.
