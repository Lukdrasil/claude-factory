---
name: architecture-rules
description: Architecture placement rules for ports and adapters, module boundaries, feature slices and which layer owns what. Use when adding a type, file, project reference or cross-module call, or when unsure where code goes.
---

# Architecture placement

Each repo picks its own variant: modules with Contracts, layered Core and DataAccess, hexagon with slices.
**The repo's documents win**; the rules below apply where they are silent.

## Steps

1. **Read the repo's decisions**: `docs/architecture/`, the accepted ADRs and the layering section of
   `CLAUDE.md`. Done when you can name the project, folder and visibility of every new type.
2. **Check the change against the repo's decisions, then every rule below.** Done when every new type,
   reference and call passes or is fixed.

## Rules

### Ports and adapters

1. **The core owns the port.** Its signatures use domain types only.
2. **A port returns a result for expected failures**, takes a cancellation token and lets cancellation
   propagate.
3. **The adapter maps** infrastructure exceptions to the port's failures, and rows to domain and back with
   every field, proven by a round-trip test on the real store.

### Modules

4. **Modules talk only through their Contracts.** No foreign domain type, no shared `DbContext`.
5. **A call when the caller needs the answer now, an integration event when it announces a fact.**
6. **A cross-module read model is slim** and owned by the module that reads it.

### Feature slices

7. **One use case per folder**, `Features/<Area>/<UseCase>/`, with `internal sealed` types.
8. **Slices never call slices.** Shared logic moves into the domain or a module service when a second use
   case needs it, not before.

## Wrong and right

- A mapping in the adapter rehydrated `revokedAt = null`, and review blocked it twice. Right: a round-trip test
  on the real store.

Rules a test can check (dependency direction, references between projects) belong in the repo's architecture
tests (`architecture-tests`), not in review.
