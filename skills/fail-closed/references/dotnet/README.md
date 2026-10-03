# .NET reference

## Catch shape

```csharp
try { return await _store.FindAsync(id, ct); }
catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
catch (StoreNotFoundException) { return Result.NotFound(); }
catch (Exception ex) when (!ct.IsCancellationRequested)
{
    _log.StoreUnavailable(ex, id);
    return Result.Failure(Errors.StoreUnavailable);
}
```

`when (!ct.IsCancellationRequested)` lets a cancellation of the caller's own token pass and still catches a
`TaskCanceledException` from an `HttpClient` timeout as a failure.

## Results

A method returning the repo's `Result` type is never called as a statement. When the repo has a
`[MustUseReturnValue]` attribute or an analyzer for it, put it on new result-returning methods.

## Error edge

`AddProblemDetails()` plus one `IExceptionHandler` turn the remaining exceptions into a ProblemDetails with a
code. `detail` carries the fixed message for that code, never `ex.Message`.

## Background loops

```csharp
using var cts = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
var loops = new[] { RunAAsync(cts.Token), RunBAsync(cts.Token) };
var first = await Task.WhenAny(loops);
await cts.CancelAsync();
await first;
```

`BackgroundServiceExceptionBehavior.StopHost` (the default) stops the host only when `ExecuteAsync` throws;
a loop that catches everything and continues hides its death, so it logs at Error and rethrows after the
retry budget.

## Locks

Check `_disposed` after `await _gate.WaitAsync(ct)`, not before. Raise events to each subscriber in its own
try/catch.
