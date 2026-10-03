# .NET reference

```csharp
public static IServiceCollection AddBilling(this IServiceCollection services, IConfiguration config)
{
    services.AddOptions<BillingOptions>()
        .Bind(config.GetSection(BillingOptions.Section))
        .ValidateDataAnnotations()
        .ValidateOnStart();
    services.AddScoped<IInvoiceStore, InvoiceStore>();
    services.Decorate<IInvoiceStore, AuditedInvoiceStore>();
    return services;
}
```

- `ValidateOnStart()` is skipped when the entry assembly is `GetDocument.Insider` (build-time OpenAPI).
- A collection on an options class has no initializer; an empty default comes from `appsettings.json`.
- `Decorate` is Scrutor's; without Scrutor, register the decorator with a factory that resolves the inner
  implementation.
- `MapGroup(...).RequireAuthorization(policy)` on the group; anonymous endpoints say `AllowAnonymous()`.
- `WebApplicationFactory<Program>` must start with only `ConfigureAppConfiguration` overrides.
