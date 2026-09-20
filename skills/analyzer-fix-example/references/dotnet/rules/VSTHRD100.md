# VSTHRD100: Avoid async void methods

**Analyzer**: Microsoft.VisualStudio.Threading.Analyzers · **Kit config**: error · **Docs**: https://microsoft.github.io/vs-threading/analyzers/VSTHRD100.html

## Wrong

```csharp
namespace Orders.Features.CreateOrder;

internal sealed class OrderCreatedNotifier(IEmailSender emailSender)
{
    internal async void Notify(Guid orderId) // analyzer fires here
    {
        await emailSender.SendAsync(orderId, CancellationToken.None);
    }
}

internal interface IEmailSender
{
    Task SendAsync(Guid orderId, CancellationToken cancellationToken);
}
```

## Right

```csharp
namespace Orders.Features.CreateOrder;

internal sealed class OrderCreatedNotifier(IEmailSender emailSender)
{
    internal async Task NotifyAsync(Guid orderId, CancellationToken cancellationToken)
    {
        await emailSender.SendAsync(orderId, cancellationToken);
    }
}

internal interface IEmailSender
{
    Task SendAsync(Guid orderId, CancellationToken cancellationToken);
}
```

**Principle**: An `async void` method gives its caller no `Task` to await or observe, so an exception thrown inside it cannot be caught by the caller and instead crashes the process.

**Layer note**: In the Host layer, a framework-mandated delegate (e.g. a UI event handler) may be the only place `async void` is unavoidable; there, wrap the body in a try/catch (or a joinable task) instead of letting the exception escape, rather than trying to change the signature.
