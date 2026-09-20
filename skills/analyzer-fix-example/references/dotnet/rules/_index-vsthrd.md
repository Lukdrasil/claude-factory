# VSTHRD rules index (Microsoft.VisualStudio.Threading.Analyzers) + BannedApiAnalyzers

Source: [microsoft/vs-threading analyzers index](https://raw.githubusercontent.com/microsoft/vs-threading/main/doc/analyzers/index.md)
(the live docs site moved this content to GitHub Pages; the table below is sourced from the last
markdown revision of `doc/analyzers/index.md` before that move, plus the individual
`doc/analyzers/VSTHRDxxx.md` pages for titles) and
[dotnet/roslyn-analyzers Microsoft.CodeAnalysis.BannedApiAnalyzers.md](https://raw.githubusercontent.com/dotnet/roslyn-analyzers/main/src/Microsoft.CodeAnalysis.BannedApiAnalyzers/Microsoft.CodeAnalysis.BannedApiAnalyzers.md).

Doc URL pattern (VSTHRD): `https://microsoft.github.io/vs-threading/analyzers/<ID>.html` (current site) /
`https://github.com/microsoft/vs-threading/blob/main/doc/analyzers/<ID>.md` (source).

Doc URL pattern (RS00xx): `https://github.com/dotnet/roslyn-analyzers/blob/main/src/Microsoft.CodeAnalysis.BannedApiAnalyzers/BannedApiAnalyzers.Help.md`.

| ID | Title | Default severity |
| --- | --- | --- |
| [VSTHRD001](https://microsoft.github.io/vs-threading/analyzers/VSTHRD001.html) | Avoid legacy thread switching methods | Warning |
| [VSTHRD002](https://microsoft.github.io/vs-threading/analyzers/VSTHRD002.html) | Avoid problematic synchronous waits | Warning |
| [VSTHRD003](https://microsoft.github.io/vs-threading/analyzers/VSTHRD003.html) | Avoid awaiting foreign Tasks | Warning |
| [VSTHRD004](https://microsoft.github.io/vs-threading/analyzers/VSTHRD004.html) | Await SwitchToMainThreadAsync | Error |
| [VSTHRD010](https://microsoft.github.io/vs-threading/analyzers/VSTHRD010.html) | Invoke single-threaded types on Main thread | Warning |
| [VSTHRD011](https://microsoft.github.io/vs-threading/analyzers/VSTHRD011.html) | Use `AsyncLazy<T>` | Error |
| [VSTHRD012](https://microsoft.github.io/vs-threading/analyzers/VSTHRD012.html) | Provide JoinableTaskFactory where allowed | Warning |
| [VSTHRD100](https://microsoft.github.io/vs-threading/analyzers/VSTHRD100.html) | Avoid `async void` methods | Warning |
| [VSTHRD101](https://microsoft.github.io/vs-threading/analyzers/VSTHRD101.html) | Avoid unsupported async delegates | Warning |
| [VSTHRD102](https://microsoft.github.io/vs-threading/analyzers/VSTHRD102.html) | Implement internal logic asynchronously | Info |
| [VSTHRD103](https://microsoft.github.io/vs-threading/analyzers/VSTHRD103.html) | Call async methods when in an async method | Warning |
| [VSTHRD104](https://microsoft.github.io/vs-threading/analyzers/VSTHRD104.html) | Offer async option | Info |
| [VSTHRD105](https://microsoft.github.io/vs-threading/analyzers/VSTHRD105.html) | Avoid method overloads that assume `TaskScheduler.Current` | Warning |
| [VSTHRD106](https://microsoft.github.io/vs-threading/analyzers/VSTHRD106.html) | Use `InvokeAsync` to raise async events | Warning |
| [VSTHRD107](https://microsoft.github.io/vs-threading/analyzers/VSTHRD107.html) | Await Task within using expression | Error |
| [VSTHRD108](https://microsoft.github.io/vs-threading/analyzers/VSTHRD108.html) | Assert thread affinity unconditionally | Warning |
| [VSTHRD109](https://microsoft.github.io/vs-threading/analyzers/VSTHRD109.html) | Switch instead of assert in async methods | Error |
| [VSTHRD110](https://microsoft.github.io/vs-threading/analyzers/VSTHRD110.html) | Observe result of async calls | Warning |
| [VSTHRD111](https://microsoft.github.io/vs-threading/analyzers/VSTHRD111.html) | Use `.ConfigureAwait(bool)` | Hidden |
| [VSTHRD112](https://microsoft.github.io/vs-threading/analyzers/VSTHRD112.html) | Implement `System.IAsyncDisposable` | Info |
| [VSTHRD113](https://microsoft.github.io/vs-threading/analyzers/VSTHRD113.html) | Check for `System.IAsyncDisposable` | Info |
| [VSTHRD114](https://microsoft.github.io/vs-threading/analyzers/VSTHRD114.html) | Avoid returning null from a `Task`-returning method | Warning |
| [VSTHRD115](https://microsoft.github.io/vs-threading/analyzers/VSTHRD115.html) | Avoid creating a JoinableTaskContext with an explicit `null` `SynchronizationContext` | Warning |
| [VSTHRD200](https://microsoft.github.io/vs-threading/analyzers/VSTHRD200.html) | Use `Async` naming convention | Warning |
| [RS0030](https://github.com/dotnet/roslyn-analyzers/blob/main/src/Microsoft.CodeAnalysis.BannedApiAnalyzers/BannedApiAnalyzers.Help.md) | Do not use banned APIs | Warning |
| [RS0031](https://github.com/dotnet/roslyn-analyzers/blob/main/src/Microsoft.CodeAnalysis.BannedApiAnalyzers/BannedApiAnalyzers.Help.md) | The list of banned symbols contains a duplicate | Warning |
