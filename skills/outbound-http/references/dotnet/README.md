# .NET reference

- Typed clients through `IHttpClientFactory` (`services.AddHttpClient<TClient>()`); a long-lived client sets
  `SocketsHttpHandler.PooledConnectionLifetime`.
- Aspire ServiceDefaults call `ConfigureHttpClientDefaults(b => b.AddStandardResilienceHandler())`, which
  reaches every client. For a client with non-idempotent calls, either
  `options.Retry.DisableForUnsafeHttpMethods()` in its resilience options or `RemoveAllResilienceHandlers()`
  and an explicit pipeline (`Microsoft.Extensions.Http.Resilience`).
- Base address `https+http://<service>` through service discovery, or from options.
- `HttpClient.Timeout` covers the whole call including retries; the per-attempt timeout lives in the
  resilience options.
