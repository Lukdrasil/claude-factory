# VSTHRD200: Use `Async` suffix for async methods

**Analyzer**: Microsoft.VisualStudio.Threading.Analyzers · **Kit config**: warning; none in test projects · **Docs**: https://microsoft.github.io/vs-threading/analyzers/VSTHRD200.html

## Wrong

```csharp
namespace Orders.Application.Handlers;

internal sealed class GetOrderHandler(IOrderRepository repository)
{
    internal async Task<OrderDto> Handle(Guid orderId, CancellationToken cancellationToken) // analyzer fires here
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

**Principle**: A `Task`-returning method without the `Async` suffix reads as synchronous at the call site, tempting a caller to skip the `await`; the suffix is a naming contract that keeps sync and async overloads visually distinguishable.
