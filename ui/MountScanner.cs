using System.IO.Enumeration;
using System.Runtime.CompilerServices;

/// <summary>
/// Reports each file under <paramref name="root"/> that appeared, vanished, or changed its length or mtime since
/// the previous scan, by its full path. The first scan is the baseline and reports nothing; a folder it cannot
/// read is skipped.
/// </summary>
public sealed class MountScanner(string root, TimeSpan interval)
{
    static readonly EnumerationOptions Options = new() { RecurseSubdirectories = true, IgnoreInaccessible = true };

    public async IAsyncEnumerable<string> ChangesAsync([EnumeratorCancellation] CancellationToken ct)
    {
        var last = Snapshot() ?? [];
        using var timer = new PeriodicTimer(interval);
        while (await timer.WaitForNextTickAsync(ct))
        {
            if (Snapshot() is not { } next)
            {
                continue;
            }
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
            last = next;
        }
    }

    Dictionary<string, (long Length, DateTimeOffset Mtime)>? Snapshot()
    {
        var files = new FileSystemEnumerable<(string, long, DateTimeOffset)>(
            root,
            (ref entry) => (entry.ToFullPath(), entry.Length, entry.LastWriteTimeUtc),
            Options)
        {
            ShouldIncludePredicate = (ref entry) => !entry.IsDirectory,
        };
        try
        {
            return files.ToDictionary(f => f.Item1, f => (f.Item2, f.Item3), StringComparer.Ordinal);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
