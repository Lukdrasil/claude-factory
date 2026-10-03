---
name: fail-closed
description: Fail-closed error handling, where an unknown failure stays a failure. Use when writing a catch, handling a returned result or error value, or writing a background loop, a cancellation path or code shared between threads.
---

# Fail-closed errors and cancellation

An unknown failure stays a failure. It never turns into success, an empty list, `false` or not-found, because
the caller then acts on an answer nobody gave.

## Rules

1. **Every returned result or error value is inspected or propagated.** A discarded result is a swallowed
   exception.
2. **Cancellation propagates.** Rethrow it. A catch-all filters on the token the code owns, because a
   cancellation raised by somebody else's timeout is a failure, not this caller's cancellation.
3. **Only an explicit not-found becomes empty, `false` or 404.** A timeout, an unavailable store or a parse
   error surfaces as its own coded failure (502 or 503 at an HTTP edge).
4. **Catch the expected cases specifically, then one catch-all** that logs and rethrows or maps to a coded
   failure. Every exception is logged once or rethrown; `logging-decisions` sets the level.
5. **Callers get a code and a fixed message.** The exception message, upstream text and internal paths stay
   in the log.
6. **A dying background loop is visible**: it logs and stops the host or marks the service unhealthy. A
   supervisor of several loops wakes on the first to finish and cancels the rest through a linked token.
7. **Shared state is re-checked under its lock**: the disposed or closed flag is read inside the lock, one
   failing subscriber leaves the others running, and reads that must agree run in one transaction.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`. Done when you know which reference applies.
2. **List the scope**: every catch, every call returning a result, every loop and every lock the change
   touches. Done when none is missing.
3. **Check each row against every rule.** Done when every row passes or is fixed.

## Wrong and right

- A store caught only its driver's exceptions. Right: rethrow cancellation, catch the rest as
  `PAT_STORE_UNAVAILABLE`.
- Any lookup failure meant "token revoked" (401). Right: only an explicit not-found is 401, the rest is 502.
- `when (f is not OperationCanceledException)`. Right: `when (!ct.IsCancellationRequested)`.
- `Task.WhenAll(loops)` hid a dead loop for hours. Right: `Task.WhenAny` and a linked token source.
- A 500 logged `ex.Message` at Information; a catch-all returned 502 and logged nothing.
