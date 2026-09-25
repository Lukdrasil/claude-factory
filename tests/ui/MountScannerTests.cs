using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.Versioning;
using Xunit;

[SupportedOSPlatform("linux")]
public sealed class MountScannerTests : IAsyncDisposable
{
    static readonly TimeSpan Interval = TimeSpan.FromMilliseconds(250);
    static readonly TimeSpan Baseline = TimeSpan.FromMilliseconds(900);

    readonly string _root = Directory.CreateTempSubdirectory("mount-scanner-").FullName;
    readonly CancellationTokenSource _cts = new();
    readonly ConcurrentQueue<string> _seen = new();
    readonly List<string> _locked = [];
    Task? _reader;

    async Task StartAsync()
    {
        var scanner = new MountScanner(_root, Interval);
        _reader = Task.Run(async () =>
        {
            await foreach (var path in scanner.ChangesAsync(_cts.Token))
            {
                _seen.Enqueue(path);
            }
        });
        await Task.Delay(Baseline, TestContext.Current.CancellationToken);
    }

    string At(params string[] parts) => Path.Combine([_root, .. parts]);

    string Write(string content, params string[] parts)
    {
        var path = At(parts);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
        return path;
    }

    string Lock(string name)
    {
        var path = At(name);
        Directory.CreateDirectory(path);
        File.WriteAllText(Path.Combine(path, "inside.md"), "x");
        File.SetUnixFileMode(path, UnixFileMode.None);
        _locked.Add(path);
        return path;
    }

    int Count(string path) => _seen.Count(p => p == path);

    async Task<TimeSpan?> WaitForAsync(string path, TimeSpan timeout)
    {
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed < timeout)
        {
            if (Count(path) > 0)
            {
                return clock.Elapsed;
            }
            await Task.Delay(20, TestContext.Current.CancellationToken);
        }
        return null;
    }

    async Task AssertReportedWithinASecondAsync(string path)
    {
        var took = await WaitForAsync(path, TimeSpan.FromSeconds(1));
        Assert.True(took is not null, $"{path} was not reported within 1 s; reported: [{string.Join(", ", _seen)}]");
    }

    [Fact]
    public async Task Files_present_before_the_first_scan_are_not_reported()
    {
        Write("before", "old.md");
        Write("before", "tasks", "T-001.md");

        await StartAsync();
        await Task.Delay(TimeSpan.FromSeconds(1), TestContext.Current.CancellationToken);

        Assert.Empty(_seen);
    }

    [Fact]
    public async Task A_new_file_is_reported_by_its_full_path_within_one_second()
    {
        await StartAsync();

        var path = Write("new", "new.md");

        await AssertReportedWithinASecondAsync(path);
    }

    [Fact]
    public async Task A_new_file_in_a_nested_folder_is_reported_by_its_full_path()
    {
        await StartAsync();

        var path = Write("new", "repos", "claude-factory", "tasks", "T-204-04.md");

        await AssertReportedWithinASecondAsync(path);
    }

    [Fact]
    public async Task A_file_whose_length_changes_is_reported()
    {
        var path = Write("short", "task.md");
        await StartAsync();

        File.AppendAllText(path, " and longer");

        await AssertReportedWithinASecondAsync(path);
    }

    [Fact]
    public async Task A_file_whose_mtime_alone_changes_is_reported()
    {
        var path = Write("same", "task.md");
        await StartAsync();

        File.SetLastWriteTimeUtc(path, File.GetLastWriteTimeUtc(path).AddMinutes(5));

        await AssertReportedWithinASecondAsync(path);
    }

    [Fact]
    public async Task A_deleted_file_is_reported()
    {
        var path = Write("doomed", "asks", "q1.md");
        await StartAsync();

        File.Delete(path);

        await AssertReportedWithinASecondAsync(path);
    }

    [Fact]
    public async Task An_unchanged_file_is_not_reported_again_on_later_scans()
    {
        await StartAsync();

        var path = Write("once", "once.md");
        await AssertReportedWithinASecondAsync(path);
        await Task.Delay(Interval * 5, TestContext.Current.CancellationToken);

        Assert.Equal(1, Count(path));
    }

    [Fact]
    public async Task A_file_changed_again_in_a_later_scan_is_reported_again()
    {
        await StartAsync();

        var path = Write("one", "twice.md");
        await AssertReportedWithinASecondAsync(path);
        await Task.Delay(Interval * 3, TestContext.Current.CancellationToken);
        File.AppendAllText(path, " two");
        await Task.Delay(TimeSpan.FromSeconds(1), TestContext.Current.CancellationToken);

        Assert.Equal(2, Count(path));
    }

    [Fact]
    public async Task An_unreadable_folder_present_at_the_first_scan_is_skipped_and_the_scan_goes_on()
    {
        var locked = Lock("locked");
        Assert.Throws<UnauthorizedAccessException>(() => Directory.EnumerateFileSystemEntries(locked).ToList());

        await StartAsync();
        var path = Write("after", "after.md");

        await AssertReportedWithinASecondAsync(path);
        Assert.False(_reader!.IsCompleted, $"the scan stopped: {_reader.Exception}");
    }

    [Fact]
    public async Task A_folder_that_becomes_unreadable_is_skipped_and_the_scan_goes_on()
    {
        await StartAsync();

        var locked = Lock("late");
        Assert.Throws<UnauthorizedAccessException>(() => Directory.EnumerateFileSystemEntries(locked).ToList());
        await Task.Delay(Interval * 3, TestContext.Current.CancellationToken);
        var path = Write("after", "after.md");

        await AssertReportedWithinASecondAsync(path);
        Assert.False(_reader!.IsCompleted, $"the scan stopped: {_reader.Exception}");
    }

    [Fact]
    public async Task Nothing_under_git_is_reported_but_its_logs_HEAD_stands_for_a_commit()
    {
        Write("ref: refs/heads/main\n", ".git", "HEAD");
        var head = Write("0 1 t <t@t> 1 +0000\tcommit: one\n", ".git", "logs", "HEAD");
        await StartAsync();

        Write("blob", ".git", "objects", "ab", "cdef");
        Write("idx", ".git", "index");
        File.AppendAllText(head, "1 2 t <t@t> 2 +0000\tcommit: two\n");
        var marker = Write("after", "after.md");

        await AssertReportedWithinASecondAsync(marker);
        await AssertReportedWithinASecondAsync(head);
        Assert.DoesNotContain(_seen, p => p.Contains($"{Path.DirectorySeparatorChar}.git{Path.DirectorySeparatorChar}", StringComparison.Ordinal) && p != head);
    }

    [Fact]
    public async Task Nothing_under_capacity_is_reported()
    {
        await StartAsync();

        Write("role=scout\nsession=s\nunit=\nat=1\n", ".capacity", "scout", "s.u");
        Write("", ".capacity", ".lock");
        var marker = Write("after", "after.md");

        await AssertReportedWithinASecondAsync(marker);
        await Task.Delay(Interval * 2, TestContext.Current.CancellationToken);
        Assert.DoesNotContain(_seen, p => p.Contains(".capacity", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Two_clients_share_one_scan_and_both_see_a_change()
    {
        var scanner = new MountScanner(_root, Interval);
        var first = new ConcurrentQueue<string>();
        var second = new ConcurrentQueue<string>();
        async Task Read(ConcurrentQueue<string> into)
        {
            await foreach (var path in scanner.ChangesAsync(_cts.Token))
            {
                into.Enqueue(path);
            }
        }
        var ct = TestContext.Current.CancellationToken;
        var readers = new[] { Task.Run(() => Read(first), ct), Task.Run(() => Read(second), ct) };
        await Task.Delay(Baseline, TestContext.Current.CancellationToken);
        var before = scanner.Scans;

        var path = Write("new", "shared.md");
        await Task.Delay(TimeSpan.FromSeconds(1.5), TestContext.Current.CancellationToken);

        Assert.Contains(path, first);
        Assert.Contains(path, second);
        var scans = scanner.Scans - before;
        Assert.True(scans <= 8, $"{scans} scans in 1.5 s at one per {Interval.TotalMilliseconds} ms: each client scans on its own");
        await _cts.CancelAsync();
        await Task.WhenAll(readers.Select(r => r.ContinueWith(_ => { }, TaskScheduler.Default)));
    }

    [Fact]
    public async Task A_burst_of_rewrites_is_debounced_into_at_most_two_reports()
    {
        await StartAsync();

        var path = Write("0", "burst.md");
        for (var i = 1; i <= 12; i++)
        {
            await Task.Delay(100, TestContext.Current.CancellationToken);
            File.AppendAllText(path, i.ToString());
        }
        await Task.Delay(TimeSpan.FromSeconds(1), TestContext.Current.CancellationToken);

        Assert.InRange(Count(path), 1, 2);
    }

    public async ValueTask DisposeAsync()
    {
        await _cts.CancelAsync();
        if (_reader is not null)
        {
            try
            {
                await _reader;
            }
            catch (OperationCanceledException)
            {
            }
        }
        foreach (var path in _locked)
        {
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
        Directory.Delete(_root, recursive: true);
        _cts.Dispose();
    }
}
