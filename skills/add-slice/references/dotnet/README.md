# Adding a vertical slice

Paths written `@...` are relative to the skill folder (the one holding `SKILL.md`); bare paths live in the target repo.

The source is `@references/dotnet/Slice.cs.template`. A slice is one file holding command, handler, validator, and endpoint together, deletable with a single `rm`. Split into multiple files only past ~200 lines, and treat reaching that threshold as a signal the use case is too big.

## Steps

### 1. Establish the context

- The target module exists and has `Features/`; otherwise run `add-module` first.
- Use-case name: verb+noun in PascalCase (`ShipOrder`, `CancelReservation`), matching sibling slices.
- **The template's implicit contract**: map every member of it to what the repo actually has:
  - a result type used as `Result<T>` with `Result.Invalid(errors)` / `Result.NotFound()` / `Result.Success(value)` plus `IsSuccess`, `IsNotFound`, `Value`, and `ToProblemDictionary()`
  - a port `I<Entity>Repository` with `FindAsync(id, ct)` and `SaveAsync(entity, ct)`

  If the repo has no result type, ask the user whether to introduce one or to return `IResult` from the handler directly, matching the repo's style.

### 2. Create the slice from the template

Copy `@references/dotnet/Slice.cs.template` to `<application project>/Features/<UseCase>/<UseCase>.cs` (the Application project found in step 1). Substitute `__USECASE__`, `__usecase__` (lowercase, route path), `__MODULE__`, `__ENTITY__`, `Acme` → root namespace; the case of each placeholder is load-bearing, carry it exactly.

- The namespace must be `{Root}.{Module}.Application.Features.{UseCase}`; the architecture tests find slices by namespace, not by folder.
- Replace the template's `DoSomething` placeholder logic with the real use case; adjust command/result properties accordingly.
- Visibility: **everything internal, handler and validator `sealed`**. The handler keeps its primary constructor (the preferred style in `Features`). Time flows in via `TimeProvider` and is passed to the domain as a timestamp parameter; `CancellationToken` propagates down to the repository.

### 3. Domain and ports

When the slice needs a domain behavior or port that does not exist yet:

- add the behavior as a method on the aggregate: invariants inside, setters private (DDD001 enforces this where the custom analyzers are wired in; otherwise verify it yourself)
- add the port as an interface in `Application/Ports` with its adapter in `Infrastructure`

For logic shared with another slice, either duplicate it (slices are allowed to duplicate; that is their point) or move it into the domain when it is a genuine domain concept.

### 4. Register inside the module

In `<Module>ModuleExtensions.cs`:

- `Add<Module>Module`: register the handler and validator in DI
- `Map<Module>Module`: `<UseCase>Endpoint.Map(group)`; mapping lives in the module, because the host cannot reach an internal endpoint. For the module's first slice, uncomment the `MapGroup("/<module>")` line so `group` exists.

### 5. Verify

```bash
dotnet build && timeout 15m dotnet test
```

`SliceIsolationTests` and `PublicSurfaceTests` guard slice isolation and visibility; a red test means fix the slice, never the test.

## Done when

Build and tests are green, the slice is one internal file at `Features/<UseCase>/<UseCase>.cs` in the required namespace, the endpoint is mapped through the module, and the handler reaches other functionality only through the domain and its own ports.
