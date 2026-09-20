# VSTHRD002: Avoid problematic synchronous waits

**Analyzer**: Microsoft.VisualStudio.Threading.Analyzers · **Kit config**: error · **Docs**: https://microsoft.github.io/vs-threading/analyzers/VSTHRD002.html

## Wrong

```csharp
namespace Orders.Application.Handlers;

internal sealed class GetOrderHandler(IOrderRepository repository)
{
    internal OrderDto Handle(Guid orderId, CancellationToken cancellationToken)
    {
        var order = repository.GetOrderAsync(orderId, cancellationToken).Result; // analyzer fires here
        return new OrderDto(order.Id, order.Total);
    }
}

internal interface IOrderRepository
{
    Task<Order> GetOrderAsync(Guid orderId, CancellationToken cancellationToken);
}

internal sealed record Order(Guid Id, decimal Total);
internal sealed record OrderDto(Guid Id, decimal Total);
```

## Right

```csharp
namespace Orders.Application.Handlers;

internal sealed class GetOrderHandler(IOrderRepository repository)
{
    internal async Task<OrderDto> HandleAsync(Guid orderId, CancellationToken cancellationToken)
    {
        var order = await repository.GetOrderAsync(orderId, cancellationToken);
        return new OrderDto(order.Id, order.Total);
    }
}

internal interface IOrderRepository
{
    Task<Order> GetOrderAsync(Guid orderId, CancellationToken cancellationToken);
}

internal sealed record Order(Guid Id, decimal Total);
internal sealed record OrderDto(Guid Id, decimal Total);
```

**Principle**: Blocking on `.Result`/`.Wait()` ties up the calling thread until the task completes, and can deadlock when that same thread is the one the awaited continuation needs to resume on; awaiting frees the thread instead of holding it hostage.
