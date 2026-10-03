---
name: reuse-first
description: Search before writing a helper, fake, constant or predicate, plus the closing check for every code change. Use before adding any helper or shared type, and before calling a code change done.
---

# Reuse first and the closing check

## Rules

1. **Search before writing** a helper, test fake, constant, error factory, options class or predicate. Search
   by behaviour, not only by name. Reuse or extend what exists.
2. **Shared code lives in its canonical home**: the repo's shared kernel, common project or test utilities.
   A second copy is a defect.
3. **One options class per configuration section.**

## Closing check

Run before calling any code change done. Done when every line holds.

1. Every new helper, fake or predicate had a search first, and the search found nothing to reuse.
2. Comments and docs that describe the changed behaviour say the new behaviour.
3. After a signature change, the whole solution builds, not only the edited project.
4. Adjacent parameters of the same type are passed as named arguments.

## Wrong and right

- `DayEditable` existed four times, `MakeError` three times, and a liveness predicate three times with
  different comparison operators. Right: one definition each, referenced everywhere.
