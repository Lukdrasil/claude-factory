using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text.RegularExpressions;

public sealed record TaskRow(
    string Id, string Status, string Archetype, string Tier, string Repo, string Owner, string Goal, string Request, string Priority,
    List<string> Steps);

public sealed record TaskDetail(
    TaskRow Task,
    Dictionary<string, string> Fields,
    string Body,
    List<TaskRow> Blocks,
    string? Plan,
    string? Grill,
    string? Verdicts,
    string? Progress,
    List<string> Timeline,
    TaskHtml Html,
    string Request,
    string Priority);

public sealed record TaskHtml(string Body, string? Plan, string? Grill, string? Verdicts, string? Progress);

public sealed record Toolset(string Repo, string Text);

public sealed record SetupInfo(
    string Root,
    string? ReposYml,
    List<Toolset> Toolsets,
    string? DoctorNotice,
    List<DoctorStep> Steps,
    string DoctorAt,
    CapacityInfo Capacity,
    List<PassInfo> Passes);

/// <summary>
/// The state repo mounted read-only at /state: task frontmatter, plans, grill files, verdicts, progress and the
/// git log of a task file. A task that is not live is read from <c>repos/&lt;key&gt;/archive/&lt;YYYY-MM&gt;/tasks/</c>, the
/// order of <c>task_of</c>.
/// </summary>
public sealed partial class StateReader(string root)
{
    /// <summary>One task file with its cached frontmatter; archived when it sits under <c>repos/&lt;key&gt;/archive/</c>.</summary>
    sealed record Entry(string File, Dictionary<string, string> Fields, string Text, bool Archived)
    {
        public string Id => Fields.GetValueOrDefault("id", "");
    }

    public List<TaskRow> Tasks()
    {
        var live = Entries(archive: false);
        var byId = ById(live);
        var maps = MapStatuses();
        return live.Select(e => Row(e, byId, maps)).ToList();
    }

    public TaskDetail? Task(string id)
    {
        var all = Entries(archive: true);
        var byId = ById(all);
        if (!byId.TryGetValue(id, out var entry))
        {
            return null;
        }
        var file = entry.File;
        var body = Frontmatter.Body(entry.Text);
        var (repoDir, dirs) = Dirs(entry);
        var slug = PlanSlug().Match(body) is { Success: true } m ? m.Groups[1].Value : null;
        var plan = slug is null ? null : ReadOrNull(repoDir, "plans", $"{slug}-plan-ready.md");
        var grill = (slug is null ? null : ReadOrNull(repoDir, "plans", $"{slug}-grill.md")) ?? GrillOf(repoDir, id);
        var verdicts = slug is null ? null : FirstOrNull(dirs, "verdicts", $"{slug}.md");
        var progress = FirstOrNull(dirs, "progress", $"{id}.md");
        var maps = MapStatuses();
        var row = Row(entry, byId, maps);
        return new TaskDetail(
            row,
            entry.Fields,
            body,
            byId.Values.Where(e => e.Id.StartsWith(id + "-", StringComparison.Ordinal)).Select(e => Row(e, byId, maps)).ToList(),
            plan,
            grill,
            verdicts,
            progress,
            Timeline(Path.GetRelativePath(root, file)),
            new TaskHtml(Md.ToHtml(body), plan is null ? null : Md.ToHtml(plan), grill is null ? null : Md.ToHtml(grill),
                verdicts is null ? null : Md.ToHtml(verdicts), progress is null ? null : Md.ToHtml(progress)),
            row.Request,
            row.Priority);
    }

    public SetupInfo Setup(UiHome home)
    {
        var (steps, at) = home.Doctor();
        return new(
            Environment.GetEnvironmentVariable("FACTORY_ROOT") ?? Path.GetDirectoryName(root) ?? root,
            ReadOrNull(root, "repos.yml"),
            Directory.Exists(Path.Combine(root, "repos"))
                ? Directory.EnumerateDirectories(Path.Combine(root, "repos"))
                    .Where(d => File.Exists(Path.Combine(d, "toolset.md")))
                    .Select(d => new Toolset(Path.GetFileName(d), File.ReadAllText(Path.Combine(d, "toolset.md"))))
                    .ToList()
                : [],
            home.LastDoctorNotice(),
            steps,
            at,
            CapacityInUse(Leases()),
            Passes());
    }

    /// <summary>Live task files in path order, then with <paramref name="archive"/> the archived ones in path order.</summary>
    IEnumerable<string> TaskFiles(bool archive)
    {
        var repos = Path.Combine(root, "repos");
        if (!Directory.Exists(repos))
        {
            return [];
        }
        var keys = Directory.EnumerateDirectories(repos).ToList();
        var live = keys
            .Select(d => Path.Combine(d, "tasks"))
            .Where(Directory.Exists)
            .SelectMany(d => Directory.EnumerateFiles(d, "*.md"))
            .Order(StringComparer.Ordinal);
        if (!archive)
        {
            return live;
        }
        var archived = keys
            .Select(d => Path.Combine(d, "archive"))
            .Where(Directory.Exists)
            .SelectMany(Directory.EnumerateDirectories)
            .Select(d => Path.Combine(d, "tasks"))
            .Where(Directory.Exists)
            .SelectMany(d => Directory.EnumerateFiles(d, "*.md"))
            .Order(StringComparer.Ordinal);
        return live.Concat(archived);
    }

    /// <summary>The task files that can be read, a file that vanished between the listing and the read skipped.</summary>
    List<Entry> Entries(bool archive)
    {
        var list = new List<Entry>();
        foreach (var file in TaskFiles(archive))
        {
            try
            {
                var (text, fields) = Frontmatter.Load(file);
                var parts = Path.GetRelativePath(root, file).Split(Path.DirectorySeparatorChar);
                list.Add(new Entry(file, fields, text, parts.Length > 3 && parts[2] == "archive"));
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
            }
        }
        return list;
    }

    /// <summary>Entries by id, the first file of an id winning, so a live task hides an archived one of the same id.</summary>
    static Dictionary<string, Entry> ById(List<Entry> entries)
    {
        var byId = new Dictionary<string, Entry>(StringComparer.Ordinal);
        foreach (var e in entries)
        {
            byId.TryAdd(e.Id, e);
        }
        return byId;
    }

    static TaskRow Row(Entry e, Dictionary<string, Entry> byId, Dictionary<string, string> maps)
    {
        var f = e.Fields;
        var owner = f.GetValueOrDefault("owner", "");
        return new TaskRow(
            e.Id,
            f.GetValueOrDefault("status", ""),
            f.GetValueOrDefault("archetype", ""),
            f.GetValueOrDefault("tier", ""),
            f.GetValueOrDefault("repo", ""),
            owner is "" or "null" ? "-" : owner,
            Goal(Frontmatter.Body(e.Text)),
            RequestOf(f),
            PriorityOf(e, byId),
            Steps(e, byId, maps));
    }

    /// <summary>The repo folder of a task file and the folders its progress and verdicts are read from: an archived
    /// task's month first, then the repo.</summary>
    static (string RepoDir, string[] Dirs) Dirs(Entry e)
    {
        var home = Path.GetDirectoryName(Path.GetDirectoryName(e.File))!;
        var repoDir = e.Archived ? Path.GetDirectoryName(Path.GetDirectoryName(home))! : home;
        return (repoDir, e.Archived ? [home, repoDir] : [repoDir]);
    }

    /// <summary>The <c>Status:</c> of every request map, live or archived, by request id.</summary>
    Dictionary<string, string> MapStatuses() =>
        RequestDirs().ToDictionary(r => r.Id, r => RequestMap.Parse(Frontmatter.Load(Path.Combine(r.Dir, "map.md")).Text).Status,
            StringComparer.Ordinal);

    /// <summary>
    /// The solve steps of a parent that its state records as done, each read off the state bin/solve-next.sh decides it
    /// by: 3 a tier and archetype that are not the draft's placeholders and a <c>## Related issues</c>, 3b its request
    /// map planned or later, 4 its plan-ready file, 5 that plan's verdict or the blocks decompose wrote once it was
    /// spent, 6 blocks, 8 a wave plan in the progress file, 9 a plan_hash or a status of ready or later, 10 a block past
    /// ready, 11 every block done, 12 <c>## Evidence</c>, 13 <c>## Review</c>, 14 an mr_url, 15 review or done, 16 done.
    /// The step a session reports ticks none of them. A block records none.
    /// </summary>
    static List<string> Steps(Entry e, Dictionary<string, Entry> byId, Dictionary<string, string> maps)
    {
        if (!ParentId().IsMatch(e.Id))
        {
            return [];
        }
        var f = e.Fields;
        var status = f.GetValueOrDefault("status", "");
        var body = Frontmatter.Body(e.Text);
        var (repoDir, dirs) = Dirs(e);
        var slug = PlanReady(repoDir, e.Id, body);
        var progress = FirstOrNull(dirs, "progress", $"{e.Id}.md") ?? "";
        var blocks = byId.Values
            .Where(b => BlockId().Match(b.Id) is { Success: true } m && m.Groups[1].Value == e.Id)
            .Select(b => b.Fields.GetValueOrDefault("status", ""))
            .ToList();
        (string Step, bool Done)[] steps =
        [
            ("3", Set(f, "tier") && Set(f, "archetype") && Heading(body, "Related issues")),
            ("3b", maps.TryGetValue(RequestOf(f), out var map) && map is "planned" or "queued" or "running" or "done"),
            ("4", slug is not null),
            ("5", slug is not null && (blocks.Count > 0 || FirstOrNull(dirs, "verdicts", $"{slug}.md") is not null)),
            ("6", blocks.Count > 0),
            ("8", Wave().IsMatch(progress)),
            ("9", Set(f, "plan_hash") || status is "ready" or "claimed" or "in_progress" or "review" or "done"),
            ("10", blocks.Any(b => b is not ("" or "draft" or "triaged" or "ready"))),
            ("11", blocks.Count > 0 && blocks.All(b => b is "done" or "closed")),
            ("12", Heading(progress, "Evidence")),
            ("13", Heading(progress, "Review")),
            ("14", Set(f, "mr_url")),
            ("15", status is "review" or "done"),
            ("16", status == "done"),
        ];
        return steps.Where(s => s.Done).Select(s => s.Step).ToList();
    }

    /// <summary>A frontmatter value that is there: not empty, not <c>null</c> and not a template placeholder <c>&lt;...&gt;</c>.</summary>
    static bool Set(Dictionary<string, string> fields, string key) =>
        fields.GetValueOrDefault(key, "") is var v && v is not ("" or "null") && !v.StartsWith('<');

    static bool Heading(string text, string head) =>
        text.Split('\n').Any(l => l.StartsWith("## " + head, StringComparison.Ordinal));

    /// <summary>The slug of a parent's plan-ready file: the one whose frontmatter says <c>task: &lt;id&gt;</c>, else the one
    /// its body names, while that file exists.</summary>
    static string? PlanReady(string repoDir, string id, string body)
    {
        var plans = Path.Combine(repoDir, "plans");
        if (!Directory.Exists(plans))
        {
            return null;
        }
        var own = Directory.EnumerateFiles(plans, "*-plan-ready.md")
            .Order(StringComparer.Ordinal)
            .FirstOrDefault(f => Frontmatter.Read(f).GetValueOrDefault("task") == id);
        if (own is not null)
        {
            return Path.GetFileName(own)[..^"-plan-ready.md".Length];
        }
        return PlanSlug().Match(body) is { Success: true } m && File.Exists(Path.Combine(plans, $"{m.Groups[1].Value}-plan-ready.md"))
            ? m.Groups[1].Value
            : null;
    }

    static string RequestOf(Dictionary<string, string> fields) =>
        fields.GetValueOrDefault("request", "") is var r && r is not ("" or "null") ? r : "";

    /// <summary>The task's own <c>priority:</c>; a block without one shows its parent's; otherwise P2.</summary>
    static string PriorityOf(Entry e, Dictionary<string, Entry> byId)
    {
        var own = e.Fields.GetValueOrDefault("priority", "");
        if (Priority().IsMatch(own))
        {
            return own;
        }
        if (BlockId().Match(e.Id) is { Success: true } m && byId.TryGetValue(m.Groups[1].Value, out var parent)
            && parent.Fields.GetValueOrDefault("priority", "") is var p && Priority().IsMatch(p))
        {
            return p;
        }
        return "P2";
    }

    static string Goal(string body) =>
        body.Split('\n')
            .SkipWhile(l => !l.StartsWith('#'))
            .Skip(1)
            .FirstOrDefault(l => !string.IsNullOrWhiteSpace(l))?.TrimEnd('\r') ?? "";

    static string? GrillOf(string repoDir, string id)
    {
        var plans = Path.Combine(repoDir, "plans");
        var file = Directory.Exists(plans)
            ? Directory.EnumerateFiles(plans, "*-grill.md")
                .Order(StringComparer.Ordinal)
                .FirstOrDefault(f => Frontmatter.Read(f).GetValueOrDefault("task") == id)
            : null;
        return file is null ? null : File.ReadAllText(file);
    }

    static string? ReadOrNull(params string[] parts)
    {
        var path = Path.Combine(parts);
        return File.Exists(path) ? File.ReadAllText(path) : null;
    }

    static string? FirstOrNull(string[] dirs, string folder, string name) =>
        dirs.Select(d => ReadOrNull(d, folder, name)).FirstOrDefault(text => text is not null);

    /// <summary>The git log of one file, followed across renames so an archived task keeps the history before its move.</summary>
    List<string> Timeline(string relative)
    {
        var git = new ProcessStartInfo("git") { RedirectStandardOutput = true };
        foreach (var arg in new[] { "-C", root, "log", "--follow", "--format=%h%x09%aI%x09%s", "--", relative })
        {
            git.ArgumentList.Add(arg);
        }
        try
        {
            using var process = Process.Start(git)!;
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            return process.ExitCode == 0 ? output.Split('\n', StringSplitOptions.RemoveEmptyEntries).ToList() : [];
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return [];
        }
    }

    /// <summary>
    /// Task and request ids in the order of <c>sort_ids</c>: segment by segment, digits by value and before letters,
    /// letters bytewise, a prefix first, so legacy ids come before alias ids and a parent before its blocks.
    /// </summary>
    public static int CompareIds(string? a, string? b)
    {
        var x = (a ?? "").Split('-');
        var y = (b ?? "").Split('-');
        for (var i = 0; i < Math.Min(x.Length, y.Length); i++)
        {
            var xd = x[i].Length > 0 && x[i].All(char.IsAsciiDigit);
            var yd = y[i].Length > 0 && y[i].All(char.IsAsciiDigit);
            var c = (xd, yd) switch
            {
                (true, true) => CompareNumbers(x[i], y[i]),
                (true, false) => -1,
                (false, true) => 1,
                _ => string.CompareOrdinal(x[i], y[i]),
            };
            if (c != 0)
            {
                return c;
            }
        }
        return x.Length.CompareTo(y.Length);
    }

    static int CompareNumbers(string a, string b)
    {
        a = a.TrimStart('0');
        b = b.TrimStart('0');
        return a.Length != b.Length ? a.Length.CompareTo(b.Length) : string.CompareOrdinal(a, b);
    }

    [GeneratedRegex(@"plans/([A-Za-z0-9._-]+)-plan-ready\.md")]
    private static partial Regex PlanSlug();

    [GeneratedRegex(@"wave[ \t]*[0-9]+[ \t]*:")]
    private static partial Regex Wave();

    [GeneratedRegex(@"^P[0-3]\z")]
    private static partial Regex Priority();

    [GeneratedRegex(@"^T-(?:[0-9]{3,}|[A-Z]{2,4}-[0-9]+)\z")]
    private static partial Regex ParentId();

    [GeneratedRegex(@"^(T-(?:[0-9]{3,}|[A-Z]{2,4}-[0-9]+))-[0-9]{2,}\z")]
    private static partial Regex BlockId();
}

public static class Frontmatter
{
    sealed record Parsed(DateTime Mtime, long Length, string Text, Dictionary<string, string> Fields);

    static readonly ConcurrentDictionary<string, Parsed> Cache = new(StringComparer.Ordinal);

    public static Dictionary<string, string> Read(string path) => Load(path).Fields;

    /// <summary>
    /// The text of a file and its parsed frontmatter, cached by path and read again once the file's mtime or
    /// length moves. The fields are shared between callers and never changed.
    /// </summary>
    public static (string Text, Dictionary<string, string> Fields) Load(string path)
    {
        var info = new FileInfo(path);
        var (mtime, length) = (info.LastWriteTimeUtc, info.Length);
        if (Cache.TryGetValue(path, out var hit) && hit.Mtime == mtime && hit.Length == length)
        {
            return (hit.Text, hit.Fields);
        }
        var text = File.ReadAllText(path);
        var parsed = new Parsed(mtime, length, text, Parse(text));
        Cache[path] = parsed;
        return (parsed.Text, parsed.Fields);
    }

    /// <summary>The flat <c>key: value</c> lines between the opening and closing <c>---</c>, a trailing <c> #</c> comment cut.</summary>
    public static Dictionary<string, string> Parse(string text)
    {
        var fields = new Dictionary<string, string>(StringComparer.Ordinal);
        var lines = text.Split('\n');
        if (lines[0].TrimEnd('\r') != "---")
        {
            return fields;
        }
        foreach (var raw in lines.Skip(1))
        {
            var line = raw.TrimEnd('\r');
            if (line == "---")
            {
                break;
            }
            var colon = line.IndexOf(':');
            if (colon <= 0 || char.IsWhiteSpace(line[0]))
            {
                continue;
            }
            var value = line[(colon + 1)..];
            var hash = value.IndexOf(" #", StringComparison.Ordinal);
            fields[line[..colon]] = (hash >= 0 ? value[..hash] : value).Trim();
        }
        return fields;
    }

    public static string Body(string text)
    {
        if (!text.StartsWith("---", StringComparison.Ordinal))
        {
            return text;
        }
        var close = text.IndexOf("\n---", 3, StringComparison.Ordinal);
        if (close < 0)
        {
            return text;
        }
        var end = text.IndexOf('\n', close + 4);
        return end < 0 ? "" : text[(end + 1)..];
    }
}
