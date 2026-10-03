# .NET reference

## Exact outcome

Assert the code a caller sees, not that something failed:

```csharp
var problem = await response.Content.ReadFromJsonAsync<ProblemDetails>();
Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
Assert.Equal("PAT_STORE_UNAVAILABLE", problem!.Extensions["code"]?.ToString());
```

## Real adapter

- Persistence tests run on the production database engine through Testcontainers. The EF Core InMemory
  provider ignores constraints, transactions, collation and raw SQL, so it never tests an adapter.
- Endpoint tests run through `WebApplicationFactory<Program>` with only the external services replaced.

## Providers

- Time: inject `TimeProvider`; tests use `FakeTimeProvider` from `Microsoft.Extensions.TimeProvider.Testing`.
- Logs: assert an entry by `EventId` and `LogLevel` with `FakeLogger` / `FakeLogCollector` from
  `Microsoft.Extensions.Diagnostics.Testing`. A test that a secret is absent from the log needs a sibling
  test where the same entry is present.

## Shared state

A class or collection fixture holds only the expensive resource (the container, the host). Each test creates
its own rows with unique keys. No `static` mutable field in a test class.
