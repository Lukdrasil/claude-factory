# .NET reference (Microsoft.Extensions.Logging)

## Catch order

Catch the specific and quiet cases before the generic and loud one. The order below is the shape; the
expected cases differ per operation.

```csharp
catch (OperationCanceledException) when (ct.IsCancellationRequested) { throw; }
catch (HttpRequestException ex) when (IsTransientClientNetwork(ex))
{ _notifier.Offline(); _logger.LogDebug(ex, "Transient network drop"); }
catch (ValidationException ex)
{ _logger.LogInformation("Rejected: {Reason}", ex.Message); return Result.Invalid(ex.Errors); }
catch (Exception ex)
{ _logger.LogError(ex, "Sync failed for {SyncId}", syncId); throw; }
```

The same `HttpRequestException` on a call between internal services is `LogError` or `LogCritical`, because
somebody has to act on it.

## Configuration

Debug stays in the code, switched off by default, and is enabled per category when an investigation needs it:

```json
"Logging": {
  "LogLevel": {
    "Default": "Warning",
    "MyApp.Sync": "Debug",
    "Microsoft.EntityFrameworkCore.Database.Command": "Warning"
  }
}
```

A support or internal tool sends only Critical to the central provider and everything else to a local file:
`builder.Logging.AddFilter<CentralProvider>(null, LogLevel.Critical)` next to a file provider.

## Data

Use `[LoggerMessage]` source generators for structured entries, and `Microsoft.Extensions.Compliance.Redaction`
for members that carry personal data. Log opaque ids, never names or e-mail addresses.

## Boundary

Log once, in the `IExceptionHandler`, the middleware or the job runner that decides the outcome, and carry the
`TraceId` (`ActivityTrackingOptions.TraceId` in the logger factory options) so the entry joins its trace.

## Blazor and single-page applications

No `Console.WriteLine` and no `console.log` in production. Show the user a message, or send the entry to a log
service.
