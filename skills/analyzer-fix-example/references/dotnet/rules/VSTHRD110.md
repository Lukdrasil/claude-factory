# VSTHRD110: Observe result of async calls

**Analyzer**: Microsoft.VisualStudio.Threading.Analyzers · **Kit config**: warning · **Docs**: https://microsoft.github.io/vs-threading/analyzers/VSTHRD110.html

## Wrong

```csharp
namespace Orders.Infrastructure.Outbox;

internal sealed class OutboxFlusher(IOutboxWriter writer)
{
    internal void FlushOnStartup()
    {
        writer.FlushAsync(CancellationToken.None); // analyzer fires here
    }
}

internal interface IOutboxWriter
{
    Task FlushAsync(CancellationToken cancellationToken);
}
```

## Right

```csharp
namespace Orders.Infrastructure.Outbox;

internal sealed class OutboxFlusher(IOutboxWriter writer)
{
    internal async Task FlushOnStartupAsync(CancellationToken cancellationToken)
    {
        await writer.FlushAsync(cancellationToken);
    }
}

internal interface IOutboxWriter
{
    Task FlushAsync(CancellationToken cancellationToken);
}
```

**Principle**: An unobserved `Task` can fault silently; the exception is captured on the task object but never rethrown anywhere the caller looks; awaiting it turns a swallowed failure into one the caller can see and handle.
