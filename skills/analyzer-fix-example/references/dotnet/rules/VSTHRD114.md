# VSTHRD114: Avoid returning null from a Task-returning method

**Analyzer**: Microsoft.VisualStudio.Threading.Analyzers · **Kit config**: not configured; Warning by default once the package is referenced (not currently referenced) · **Docs**: https://microsoft.github.io/vs-threading/analyzers/VSTHRD114.html

## Wrong

```csharp
namespace Kit.Modules.Orders.Application.Ports;

internal sealed record Order(Guid Id, string Status);

internal interface IOrderCache
{
    Task<Order?> TryGetAsync(Guid orderId, CancellationToken cancellationToken);
}

internal sealed class NullOrderCache : IOrderCache
{
    public Task<Order?> TryGetAsync(Guid orderId, CancellationToken cancellationToken) => null; // non-async method returning a null Task
}
```

## Right

```csharp
namespace Kit.Modules.Orders.Application.Ports;

internal sealed record Order(Guid Id, string Status);

internal interface IOrderCache
{
    Task<Order?> TryGetAsync(Guid orderId, CancellationToken cancellationToken);
}

internal sealed class NullOrderCache : IOrderCache
{
    public Task<Order?> TryGetAsync(Guid orderId, CancellationToken cancellationToken) => Task.FromResult<Order?>(null);
}
```

**Principle**: Awaiting a `null` Task throws a `NullReferenceException` at the call site instead of producing the intended result, so a non-async method must return `Task.FromResult`/`Task.CompletedTask` even for a "nothing to report" case.
