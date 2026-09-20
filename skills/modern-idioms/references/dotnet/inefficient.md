# Inefficient idioms (.NET)

Each row is a defect when it appears in a member the diff touches: fix it or record it (SKILL.md step 4).
`details.md` carries the snippet, the reason in full and the sources per code.

## B1 Strings
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B1.1 | string concatenation with `+` in a loop | `StringBuilder`, `string.Join` or `string.Concat` | O(n²) copies, one allocation per `+` | S1643 |
| B1.2 | `string.Format` with a non-literal format string | `CompositeFormat.Parse` once, reuse it | re-parses the template every call | CA1863, CA1305 |
| B1.3 | `StringBuilder.Append` with a one-char string | `Append(char)` overload | bulk copy vs one direct char write | CA1834, CA1830, MA0028 |
| B1.4 | `ToLower()`/`ToUpper()` to compare strings | `string.Equals(a, b, OrdinalIgnoreCase)` | two allocations, wrong-locale results | CA1862, MA0001 |
| B1.5 | `Substring` where a view would do | `AsSpan().SequenceEqual(...)` | O(n) copy plus heap allocation | CA1846, CA1845 |
| B1.6 | `IndexOf`/`Contains`/`StartsWith` with 1-char string | `char` overloads (`StartsWith('/')`) | extra string-comparison machinery | CA1858, CA1865 |
| B1.7 | testing for empty string with `== ""` | `string.IsNullOrEmpty(s)` | full comparison vs a length read | CA1820 |
| B1.8 | `Encoding.GetBytes` allocating on every call | span overload, or a `u8` literal | fresh `byte[]` allocation per call | IDE0230 |
| B1.9 | `Guid.ToString()` as a dictionary key | `Dictionary<Guid, T>` keyed directly | allocation, slower hash over 36 chars | — |
| B1.10 | `Enum.ToString()`/`Parse`/`IsDefined` in hot paths | `switch` expression or lookup table | reflection-backed lookup, boxing | MA0052, CA2248 |
| B1.11 | `new Regex(...)` constructed in a hot path | `[GeneratedRegex]` source generator | re-parses the pattern every call | SYSLIB1045, MA0110, S6444 |

## B2 LINQ and enumeration
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B2.1 | `ToList()`/`ToArray()` before one enumeration | drop the materialization call | backing-array allocation for nothing | — |
| B2.2 | repeated enumeration of an `IEnumerable<T>` param | materialize once (`ToList()`) | re-runs the pipeline, extra round-trips | CA1851 |
| B2.3 | `Count() > 0` / `.Any()` on a known concrete type | `.Count`/`.Length` property | full enumeration vs one field read | CA1827, CA1860 |
| B2.4 | `.Where(p).First()` chained LINQ | predicate overload `FirstOrDefault(p)` | second iterator allocated | MA0029, S2971 |
| B2.5 | LINQ where the collection has a purpose-built member | `Exists`/`TrueForAll`/`Min` property | extra enumerator, O(n) vs O(log n) | CA1826, S6605 |
| B2.6 | `OrderBy(k).First()` instead of `MinBy` | `MinBy`/`MaxBy` | O(n log n) sort vs one O(n) pass | — [unverified] |
| B2.7 | projecting before filtering | `Where` before the costly `Select` | expensive work on discarded elements | S6607 |
| B2.8 | `List<T>.Contains` inside a loop | `HashSet<T>`/`ToFrozenSet()` lookup | O(n·m) scan vs O(1) average lookup | — [unverified] |
| B2.9 | LINQ chains in per-frame/per-request hot loops | `foreach` over `CollectionsMarshal.AsSpan` | iterator and closure allocated per stage | — |
| B2.10 | allocating an empty collection (`new T[0]`) | `Array.Empty<T>()` or `[]` | a real zero-length heap allocation | CA1825, IDE0301 |

## B3 Async
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B3.1 | `async void` method | `async Task` | unobservable exceptions, process crash | S3168, MA0155 |
| B3.2 | blocking on a task (`.Result`, `.Wait()`) | `await` the task | deadlock risk, thread-pool starvation | S4462, MA0042 |
| B3.3 | missing `ConfigureAwait(false)` in library code | `.ConfigureAwait(false)` | captured-context hop, deadlock risk | CA2007, MA0004 |
| B3.4 | `Task.Run` wrapping an already-async call | `await` the async call directly | extra scheduling hop, no parallelism | — |
| B3.5 | `Thread.Sleep` in async code | `Task.Delay`/`TimeProvider.Delay` | blocks the pool thread for the interval | MA0045 |
| B3.6 | `async` method body with no `await` | plain method, `Task.FromResult` | needless state machine and `Task` alloc | S3168 |
| B3.7 | not forwarding the `CancellationToken` | pass `ct` to every inner call | cancellation never reaches inner work | CA2016, MA0040 |
| B3.8 | fire-and-forget: discarding a returned `Task` | `await` it, or observe via hosted service | swallowed exceptions, unordered work | MA0134, CA2025 |
| B3.9 | `ValueTask` consumed more than once | await it exactly once | undefined behavior, pooled source reused | CA2012 |
| B3.10 | sync-over-async in EF Core | `ToListAsync`/`SaveChangesAsync` | holds the request thread for the round-trip | CA1849, CA1828 |
| B3.11 | holding a lock across `await` | `SemaphoreSlim.WaitAsync` | thread-affine lock; this will not compile | CS1996 |
| B3.12 | `Parallel.ForEach` with an async body | `Parallel.ForEachAsync` | async-void delegate, lost exceptions | — |

## B4 Dictionaries and collections
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B4.1 | `ContainsKey` then indexer (double lookup) | `TryGetValue` | two hash computations instead of one | CA1854 |
| B4.2 | `ContainsKey`+`Add`, read-modify-write counter | `CollectionsMarshal.GetValueRefOrAddDefault` | three lookups vs a single probe | CA1864, CA1853, CA1868 |
| B4.3 | `foreach` over `Keys` then indexing the value | `foreach (var (k, v) in d)` | extra hash lookup per iteration | — [unverified] |
| B4.4 | growing a collection without a capacity hint | `new List<T>(count)` / `EnsureCapacity` | repeated doubling, ~2n element copies | — |
| B4.5 | non-generic collections (`ArrayList`, `Hashtable`) | generic collections (`List<int>`) | boxing on every insert and read | CA1010 |
| B4.6 | exposing a mutable `List<T>` on a public API | `IReadOnlyList<T>` | unchecked external mutation | CA1002, CA2227 |
| B4.7 | constant array literal passed as an argument | cached field or `ReadOnlySpan<T>` property | fresh array allocated on every call | CA1861, CA1878 |

## B5 Boxing and structs
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B5.1 | boxing through `object`/`params object[]` | generic overload or `params ReadOnlySpan<T>` | heap allocation per value-type argument | CA2263 |
| B5.2 | struct copies in `foreach` and call boundaries | `ref readonly` iteration and parameters | defensive copy on every access/call | IDE0250, MA0168 |
| B5.3 | struct key without `IEquatable<T>` | implement `IEquatable<T>` and `GetHashCode` | boxing, reflective field comparison | CA1815, S3898 |
| B5.4 | `Enum.HasFlag` | bitwise `(flags & x) != 0` | boxes the enum argument | CA2248 |
| B5.5 | closures allocated per loop iteration | hoist the capture, or mark lambda `static` | display-class allocation per iteration | IDE0320, S6612 |

## B6 Exceptions
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B6.1 | `Parse` in `try`/`catch` instead of `TryParse` | `TryParse` | exception cost vs a bool return | — [unverified] |
| B6.2 | swallowing with `catch (Exception)` | catch the specific type, log it | hides defects, destroys diagnostics | CA1031, S2221 |
| B6.3 | `throw ex;` losing the stack trace | bare `throw;` | stack trace reset to the rethrow site | CA2200, S3445 |
| B6.4 | exceptions on an expected path (`KeyNotFoundException`) | `TryGetValue` | throw cost on a routine, expected miss | — |
| B6.5 | hand-rolled guard clauses | `ArgumentNullException.ThrowIfNull` and friends | duplicated boilerplate, weaker inlining | CA1510, CA2264 |

## B7 Concurrency and resources
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B7.1 | `lock(this)` / `lock(typeof(X))` / `lock("lit")` | private `Lock`/`object` field | weak identity, invisible deadlocks | CA2002, MA0064 |
| B7.2 | `new HttpClient()` per request | `IHttpClientFactory` typed client | socket and ephemeral-port exhaustion | — |
| B7.3 | not disposing `IDisposable` | `using`/`await using` | leaked handles until finalizer runs | CA2000, CA1063 |
| B7.4 | un-cached `JsonSerializerOptions` per call | cached static `JsonSerializerOptions` field | rebuilds the reflection metadata graph | CA1869 |
| B7.5 | un-guarded expensive logging argument | `IsEnabled(level)` guard or `[LoggerMessage]` | argument evaluated even when disabled | CA1873, CA1848 |

## B8 I/O
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B8.1 | `File.ReadAllText` on a large file | `File.ReadLinesAsync` streaming | whole file lands on the Large Object Heap | — |
| B8.2 | synchronous file APIs inside an async method | `File.ReadAllTextAsync` | blocks the pool thread for I/O duration | CA1849, CA1835 |
| B8.3 | allocating I/O buffers instead of renting | `ArrayPool<byte>.Shared.Rent` | churns gen-0 near the LOH threshold | — |
| B8.4 | `File.Exists` then open | `try`/`catch` around the open | time-of-check/time-of-use race | — |

## B9 Time, randomness and formatting
| code | anti-pattern | fix | why | rule |
|---|---|---|---|---|
| B9.1 | `DateTime.Now` instead of UTC | `DateTimeOffset.UtcNow`/`TimeProvider` | slower, ambiguous on DST, untestable | S6563, S6562 |
| B9.2 | `DateTime` subtraction to measure elapsed time | `Stopwatch.GetTimestamp`/`GetElapsedTime` | wall clock is not monotonic | S6561 |
| B9.3 | `new Random()` per call or in a loop | `Random.Shared` | allocation, correlated seeds | — |
| B9.4 | random GUIDs as clustered database keys | `Guid.CreateVersion7()` | index fragmentation from scattered inserts | S4581 |
| B9.5 | redundant `.ToString()` in interpolation | drop the explicit call | redundant string allocation | IDE0071, MA0044 |
