# VSTHRD003: Avoid awaiting foreign Tasks

**Analyzer**: Microsoft.VisualStudio.Threading.Analyzers · **Kit config**: not configured; Warning by default once the package is referenced (not currently referenced) · **Docs**: https://microsoft.github.io/vs-threading/analyzers/VSTHRD003.html

## Wrong

```csharp
namespace Kit.Modules.Orders.Infrastructure.LegacyIntegration;

internal sealed class LegacyCatalogSyncAdapter
{
    private readonly Task _warmup = LoadCatalogAsync();

    internal async Task SyncAsync(CancellationToken cancellationToken)
    {
        await _warmup; // awaiting a Task created outside this method - foreign task
        await PushChangesAsync(cancellationToken);
    }

    private static Task LoadCatalogAsync() => Task.Delay(1);
    private static Task PushChangesAsync(CancellationToken cancellationToken) => Task.Delay(1, cancellationToken);
}
```

## Right

```csharp
using Microsoft.VisualStudio.Threading;

namespace Kit.Modules.Orders.Infrastructure.LegacyIntegration;

internal sealed class LegacyCatalogSyncAdapter(JoinableTaskFactory joinableTaskFactory)
{
    private readonly JoinableTask _warmup = joinableTaskFactory.RunAsync(LoadCatalogAsync);

    internal async Task SyncAsync(CancellationToken cancellationToken)
    {
        await _warmup;
        await PushChangesAsync(cancellationToken);
    }

    private static Task LoadCatalogAsync() => Task.Delay(1);
    private static Task PushChangesAsync(CancellationToken cancellationToken) => Task.Delay(1, cancellationToken);
}
```

**Principle**: Wrapping the operation in a `JoinableTask` lets the awaiting thread "join" it, sharing its own thread's ability to service the work if it needs the main thread; a plain `Task` gives the awaiter no such coordination, so a synchronous block elsewhere in the call chain can deadlock against it.

**Layer note**: This deadlock-avoidance pattern, and the `Microsoft.VisualStudio.Threading` dependency itself, belongs only in Infrastructure adapters bridging to UI-thread-affine or single-threaded legacy components; Domain and Application code should never reference `JoinableTaskFactory`.
