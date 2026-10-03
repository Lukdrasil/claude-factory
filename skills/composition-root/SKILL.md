---
name: composition-root
description: Composition-root rules for module registration, configuration binding and validation, hosted-service order and decorators. Use when registering services, binding configuration, adding a hosted service or changing application startup.
---

# Hosting, options and the composition root

The **composition root** is the one place that wires the application. It stays small: every module
registers itself through one entry point and every misconfiguration fails at startup.

## Rules

1. **Each module exposes one registration entry point**; everything it registers stays internal.
2. **One options class per configuration section, validated at startup**, so bad configuration stops the
   start. Build-time tool runs that start the host without configuration (OpenAPI generation) skip it.
3. **Bound collections get no default in an initializer.** The binder merges configured items into the
   default instead of replacing it.
4. **Registration order is start order** for hosted services: a guard starts before what it guards.
5. **Cross-cutting behaviour wraps a port in a decorator** instead of adding a parameter to every
   implementation.
6. **Authorization is attached to each endpoint or group explicitly.** Framework defaults (a reverse proxy's
   transforms, timeouts) stay unless a stated reason changes them.
7. **The host is constructible in tests** with external services replaced through configuration.

## Steps

1. **Read the stack.** Read `stack:` from the toolset section of the injected context and, when it exists,
   `${CLAUDE_SKILL_DIR}/references/<stack>/README.md`. Done when you know which reference applies.
2. **List every registration, options class and hosted service** the change touches. Done when none is
   missing.
3. **Check each against every rule.** Done when every row passes or is fixed.

## Wrong and right

- A durability guard hosted service was registered after the sink it guarded.
- An array default was merged with the configured array instead of replaced.
