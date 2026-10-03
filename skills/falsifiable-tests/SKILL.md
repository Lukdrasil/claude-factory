---
name: falsifiable-tests
description: Rules that make every test able to go red. Use when writing or changing a test, and when a review judges test quality.
---

# Falsifiable tests

A test earns its place only when a plausible defect turns it **red**. Before a test is done, name the defect
that turns it red. A test with no nameable defect pins nothing and gets rewritten or deleted.

## Rules

1. **Assert the exact outcome**: the error code, the status, the value. A check that the result is one of
   several allowed values lets a wrong value through.
2. **Every absence check has a positive control**: next to "no error", "nothing logged", "not called" or
   "empty", a test with the same setup that does produce the thing, so the probe is proven to see it.
3. **Call the production code.** A test that copies the loop, query or predicate it verifies tests the copy.
4. **Exercise the real adapter** for persistence, crypto, serialization and anything else the adapter itself
   decides. An in-memory fake stands in for a port only in tests of the layers above it.
5. **An existing assertion keeps its strength.** A deliberate behaviour change updates the expected value
   and the commit says why; a looser assertion that turns a test green is a defect.
6. **Each test owns its state**: its own data and unique keys, any execution order, no mutable state shared
   between tests.
7. **Time, randomness and generated ids come from injected providers**, so the test fixes them.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`. Done when you know which reference applies.
2. **List every test** the change adds or edits. Done when none is missing.
3. **Name the defect** that turns each test red and check it against every rule. Done when every test names
   its defect and passes every rule.

## Wrong and right

- A test copied the sweep loop it verified. Right: it calls the production `SweepOnceAsync`.
- An end-to-end test authenticated against an in-memory account store. Right: the real PBKDF2 verifier.
- `Assert.Contains(kind, ["user", "service"])` survived an ordinal-comparison mutation across 39 cases.
  Right: each case asserts its one expected kind.
