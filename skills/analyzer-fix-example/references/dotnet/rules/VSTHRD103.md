# VSTHRD103: Call async methods when in an async method

**Analyzer**: Microsoft.VisualStudio.Threading.Analyzers · **Kit config**: error · **Docs**: https://microsoft.github.io/vs-threading/analyzers/VSTHRD103.html

## Wrong

```csharp
namespace Orders.Infrastructure.Storage;

internal sealed class OrderFileStore
{
    internal async Task<string> ReadReceiptAsync(string path, CancellationToken cancellationToken)
    {
        var bytes = File.ReadAllBytesAsync(path, cancellationToken).Result; // VSTHRD103: Result synchronously blocks
        return Convert.ToBase64String(bytes);
    }
}
```

## Right

```csharp
namespace Orders.Infrastructure.Storage;

internal sealed class OrderFileStore
{
    internal async Task<string> ReadReceiptAsync(string path, CancellationToken cancellationToken)
    {
        var bytes = await File.ReadAllBytesAsync(path, cancellationToken);
        return Convert.ToBase64String(bytes);
    }
}
```

**Principle**: Blocking on `.Result`/`.Wait()` inside an `async` method holds the thread for the full duration of the work and can deadlock on the continuation, while `await` releases the thread to the pool; the method is already async, so awaiting costs nothing.

**Related**: calling a synchronous API that has an async counterpart (`File.ReadAllBytes` inside an async method) is reported by S6966/CA1849, not VSTHRD103; blocking in a *non*-async method is VSTHRD002.
