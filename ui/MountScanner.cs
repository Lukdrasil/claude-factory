using System.IO.Enumeration;
using System.Runtime.CompilerServices;
using System.Threading.Channels;

/// <summary>
/// Reports each file under <paramref name="root"/> that appeared, vanished, or changed its length or mtime since
/// the previous scan, by its full path. One scan loop serves every client: it starts with the first, takes its
/// baseline then (the baseline reports nothing), and stops with the last. A burst is debounced: the changes of
/// consecutive scans go out together once a scan finds nothing new, or after <see cref="MaxHold"/> scans at the
/// latest, each path once. <c>.git</c> and <c>.capacity</c> are never walked; <c>.git/logs/HEAD</c> alone stands
/// for a commit. A folder it cannot read is skipped.
/// </summary>
public sealed class MountScanner(string root, TimeSpan interval)
{
    const int MaxHold = 4;

    static readonly EnumerationOptions Options = new() { RecurseSubdirectories = true, IgnoreInaccessible = true };

    readonly Lock _gate = new();
    readonly List<Channel<string>> _clients = [];
    CancellationTokenSource? _loop;
    int _scans;

    /// <summary>The scans run so far, for every client together.</summary>
    public int Scans => Volatile.Read(ref _scans);

    public async IAsyncEnumerable<string> ChangesAsync([EnumeratorCancellation] CancellationToken ct)
    {
        var client = Channel.CreateUnbounded<string>(new UnboundedChannelOptions { SingleReader = true });
        Join(client);
        try
        {
            await foreach (var path in client.Reader.ReadAllAsync(ct))
            {
                yield return path;
            }
        }
        finally
        {
            Leave(client);
        }
    }

    void Join(Channel<string> client)
    {
        lock (_gate)
        {
            _clients.Add(client);
            if (_loop is null)
            {
                var loop = _loop = new CancellationTokenSource();
                _ = Task.Run(() => RunAsync(loop));
            }
        }
    }

    void Leave(Channel<string> client)
    {
        lock (_gate)
        {
            _clients.Remove(client);
            if (_clients.Count == 0 && _loop is { } loop)
            {
                _loop = null;
                loop.Cancel();
            }
        }
    }

    async Task RunAsync(CancellationTokenSource loop)
    {
        try
        {
            var last = Snapshot() ?? [];
            var batch = new List<string>();
            var inBatch = new HashSet<string>(StringComparer.Ordinal);
            var held = 0;
            using var timer = new PeriodicTimer(interval);
            while (await timer.WaitForNextTickAsync(loop.Token))
            {
                var changed = false;
                if (Snapshot() is { } next)
                {
                    foreach (var path in Changes(last, next))
                    {
                        changed = true;
                        if (inBatch.Add(path))
                        {
                            batch.Add(path);
                        }
                    }
                    last = next;
                }
                if (batch.Count == 0 || (changed && ++held < MaxHold))
                {
                    continue;
                }
                Publish(batch);
                batch = [];
                inBatch.Clear();
                held = 0;
            }
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            loop.Dispose();
        }
    }

    static IEnumerable<string> Changes(
        Dictionary<string, (long Length, DateTimeOffset Mtime)> last, Dictionary<string, (long Length, DateTimeOffset Mtime)> next)
    {
        foreach (var (path, stamp) in next)
        {
            if (!last.TryGetValue(path, out var was) || was != stamp)
            {
                yield return path;
            }
        }
        foreach (var path in last.Keys.Where(path => !next.ContainsKey(path)))
        {
            yield return path;
        }
    }

    void Publish(List<string> batch)
    {
        Channel<string>[] clients;
        lock (_gate)
        {
            clients = [.. _clients];
        }
        foreach (var client in clients)
        {
            foreach (var path in batch)
            {
                client.Writer.TryWrite(path);
            }
        }
    }

    Dictionary<string, (long Length, DateTimeOffset Mtime)>? Snapshot()
    {
        Interlocked.Increment(ref _scans);
        var files = new FileSystemEnumerable<(string, long, DateTimeOffset)>(
            root,
            (ref entry) => (entry.ToFullPath(), entry.Length, entry.LastWriteTimeUtc),
            Options)
        {
            ShouldIncludePredicate = (ref entry) => !entry.IsDirectory,
            ShouldRecursePredicate = (ref entry) => entry.FileName is not (".git" or ".capacity"),
        };
        try
        {
            var snapshot = files.ToDictionary(f => f.Item1, f => (f.Item2, f.Item3), StringComparer.Ordinal);
            var head = new FileInfo(Path.Combine(root, ".git", "logs", "HEAD"));
            if (head.Exists)
            {
                snapshot[head.FullName] = (head.Length, new DateTimeOffset(head.LastWriteTimeUtc));
            }
            return snapshot;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
