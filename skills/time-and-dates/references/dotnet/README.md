# .NET reference

| Need | Use |
|---|---|
| Clock | `TimeProvider` injected, `timeProvider.GetUtcNow()`; tests `FakeTimeProvider` |
| Instant | `DateTimeOffset` in UTC |
| Calendar date | `DateOnly` |
| Time of day | `TimeOnly`, `Add(TimeSpan, out int wrappedDays)` |
| Duration | `TimeSpan`, summed with `Aggregate(TimeSpan.Zero, (a, b) => a + b)` |
| Wire format | `ToString("O", CultureInfo.InvariantCulture)` |
| Display | the request culture, explicit in `ToString(format, culture)` |
| No value | `DateOnly?` checked with `is null`, never `== default` |

`DateTime.Now`, `DateTime.UtcNow` and `DateTimeOffset.Now` in production code are replaced by the injected
`TimeProvider`.
