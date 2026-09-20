# VSTHRD101: Avoid unsupported async delegates

**Analyzer**: Microsoft.VisualStudio.Threading.Analyzers · **Kit config**: not configured; Warning by default once the package is referenced (not currently referenced) · **Docs**: https://microsoft.github.io/vs-threading/analyzers/VSTHRD101.html

## Wrong

```csharp
namespace Kit.Modules.Orders.Application.Features.PlaceOrder;

internal interface IEmailSender
{
    Task SendAsync(CancellationToken cancellationToken);
}

internal sealed class OrderPlacedNotifier
{
    internal event Action? OrderPlaced;

    internal void Subscribe(IEmailSender emailSender, CancellationToken cancellationToken) =>
        OrderPlaced += async () => await emailSender.SendAsync(cancellationToken); // async void via Action delegate

    internal void Raise() => OrderPlaced?.Invoke();
}
```

## Right

```csharp
namespace Kit.Modules.Orders.Application.Features.PlaceOrder;

internal interface IEmailSender
{
    Task SendAsync(CancellationToken cancellationToken);
}

internal sealed class OrderPlacedNotifier
{
    private readonly List<Func<CancellationToken, Task>> _handlers = [];

    internal void Subscribe(IEmailSender emailSender) => _handlers.Add(emailSender.SendAsync);

    internal async Task RaiseAsync(CancellationToken cancellationToken)
    {
        foreach (var handler in _handlers)
        {
            await handler(cancellationToken);
        }
    }
}
```

**Principle**: An event backed by `Action` forces every async subscriber into `async void`, so the registration point should expose a `Func<Task>`-shaped delegate instead, giving the raiser a `Task` it can await and observe exceptions from.
