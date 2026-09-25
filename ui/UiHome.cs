using System.Text.Json;
using System.Text.RegularExpressions;

/// <summary><c>setup/doctor.json</c> as read; every field may be missing.</summary>
public sealed record DoctorFile(string? At, string? Root, List<DoctorFileStep>? Steps);

public sealed record DoctorFileStep(string? Id, string? State, string? Detail, string? Fix);

public sealed record AskInfo(string Ask, string Task, string Flow, string Step, string Status, DateTime Modified, string Body, bool Sent, string? Held, AskView View);

public sealed record VisualInfo(string Row, string Version, string Status);

public sealed record SessionInfo(string Sid, string Pane, string Flow, string Task, string Step, string Agent, List<AskInfo> Asks, VisualInfo? Visual);

public enum AnswerStatus
{
    Written,
    Invalid,
    Unknown,
    NotOpen,
}

/// <summary>
/// The UI home mounted at /ui: sessions, their asks and answer files. The only writer of answer files.
/// </summary>
public sealed partial class UiHome(string root)
{
    readonly Lock _answers = new();

    public string? Token()
    {
        var path = Path.Combine(root, "token");
        return File.Exists(path) ? File.ReadAllText(path).Trim() : null;
    }

    public int? Port()
    {
        var path = Path.Combine(root, "port");
        return File.Exists(path) && int.TryParse(File.ReadAllText(path).Trim(), out var port) ? port : null;
    }

    /// <summary>
    /// Writes <c>sessions/&lt;sid&gt;/answers/&lt;seq&gt;-&lt;ask&gt;.txt</c> with the next seq of the session
    /// through a rename, only while the ask's status is open. An empty ask is a free message to a registered
    /// session (the Memory tab's start button to the CEO): it needs text and is written under the ask id
    /// <c>msg</c>, so the relay types it into the pane like any answer.
    /// </summary>
    public (AnswerStatus Status, string? File) WriteAnswer(string sid, string? ask, string? text)
    {
        if (!Id().IsMatch(sid) || ask is null || text is null)
        {
            return (AnswerStatus.Invalid, null);
        }
        var session = Path.Combine(root, "sessions", sid);
        if (ask == "")
        {
            if (string.IsNullOrWhiteSpace(text))
            {
                return (AnswerStatus.Invalid, null);
            }
            if (!File.Exists(Path.Combine(session, "session.md")))
            {
                return (AnswerStatus.Unknown, null);
            }
            return (AnswerStatus.Written, Write(session, "msg", text));
        }
        if (!Id().IsMatch(ask))
        {
            return (AnswerStatus.Invalid, null);
        }
        var askFile = Path.Combine(session, "asks", ask + ".md");
        if (!File.Exists(askFile))
        {
            return (AnswerStatus.Unknown, null);
        }
        if (Frontmatter.Read(askFile).GetValueOrDefault("status") != "open")
        {
            return (AnswerStatus.NotOpen, null);
        }
        return (AnswerStatus.Written, Write(session, ask, text));
    }

    string Write(string session, string ask, string text)
    {
        var answers = Directory.CreateDirectory(Path.Combine(session, "answers")).FullName;
        lock (_answers)
        {
            var name = $"{NextSeq(answers)}-{ask}.txt";
            var temp = Path.Combine(answers, $".{name}.tmp");
            File.WriteAllText(temp, text);
            File.Move(temp, Path.Combine(answers, name));
            return name;
        }
    }

    /// <summary>
    /// Every session under <c>sessions/</c> with its asks and the pane state the relay wrote to <c>agent</c>. An ask is sent once an answer file newer than the ask names it and is not a <c>Q&lt;n&gt; redraw</c> or <c>Q&lt;n&gt; more</c>, and held with the
    /// reason of <c>relay</c> while the relay holds any of its answers newer than the ask, a kept-open one included. An unreadable session is skipped.
    /// </summary>
    public List<SessionInfo> Sessions()
    {
        var sessions = Path.Combine(root, "sessions");
        if (!Directory.Exists(sessions))
        {
            return [];
        }
        var list = new List<SessionInfo>();
        foreach (var dir in Directory.EnumerateDirectories(sessions).Order(StringComparer.Ordinal))
        {
            try
            {
                if (ReadSession(dir) is { } session)
                {
                    list.Add(session);
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
            }
        }
        return list;
    }

    static SessionInfo? ReadSession(string dir)
    {
        var file = Path.Combine(dir, "session.md");
        if (!File.Exists(file))
        {
            return null;
        }
        var fields = Frontmatter.Read(file);
        var answers = AnswerFiles(Path.Combine(dir, "answers"));
        var relay = Path.Combine(dir, "relay");
        var held = File.Exists(relay) ? File.ReadAllText(relay).Trim().Split(' ', 2) : [];
        var agent = Path.Combine(dir, "agent");
        var asks = Path.Combine(dir, "asks");
        var task = fields.GetValueOrDefault("task", "");
        return new SessionInfo(
            Path.GetFileName(dir),
            fields.GetValueOrDefault("pane", ""),
            fields.GetValueOrDefault("flow", ""),
            task,
            fields.GetValueOrDefault("step", ""),
            File.Exists(agent) ? File.ReadAllText(agent).Trim() : "",
            Directory.Exists(asks)
                ? Directory.EnumerateFiles(asks, "*.md")
                    .Where(f => !Path.GetFileName(f).StartsWith('.'))
                    .Order(StringComparer.Ordinal)
                    .Select(f => ReadAsk(f, answers, held, task))
                    .ToList()
                : [],
            ReadVisual(dir));
    }

    static VisualInfo? ReadVisual(string dir)
    {
        var meta = Path.Combine(dir, "visual.md");
        if (!File.Exists(meta) || !File.Exists(Path.Combine(dir, "visual.html")))
        {
            return null;
        }
        var fields = Frontmatter.Read(meta);
        return new VisualInfo(
            fields.GetValueOrDefault("row", ""),
            fields.GetValueOrDefault("version", ""),
            fields.GetValueOrDefault("status", ""));
    }

    /// <summary>The path of <c>sessions/&lt;sid&gt;/visual.html</c> when it exists, otherwise null.</summary>
    public string? VisualFile(string sid)
    {
        var file = Path.Combine(root, "sessions", sid, "visual.html");
        return File.Exists(file) ? file : null;
    }

    public static bool IsId(string? value) => value is not null && Id().IsMatch(value);

    static List<(string Seq, string Ask, DateTime Modified, bool KeepsOpen)> AnswerFiles(string answers) =>
        Directory.Exists(answers)
            ? Directory.EnumerateFiles(answers, "*.txt")
                .Select(f => (File: f, Match: Answer().Match(Path.GetFileName(f))))
                .Where(a => a.Match.Success)
                .Select(a => (
                    a.Match.Groups[1].Value,
                    a.Match.Groups[2].Value,
                    File.GetLastWriteTimeUtc(a.File),
                    KeepsOpen().IsMatch(File.ReadAllText(a.File).Trim())))
                .ToList()
            : [];

    /// <summary>One ask of a session; its <c>task</c> is its own, or its session's <paramref name="task"/> when it names none,
    /// so the grid and the drawer count it under one task.</summary>
    static AskInfo ReadAsk(string file, List<(string Seq, string Ask, DateTime Modified, bool KeepsOpen)> answers, string[] held, string task)
    {
        var text = File.ReadAllText(file);
        var fields = Frontmatter.Parse(text);
        var id = fields.GetValueOrDefault("ask", Path.GetFileNameWithoutExtension(file));
        var modified = File.GetLastWriteTimeUtc(file);
        var mine = answers.Where(a => a.Ask == id && a.Modified > modified).ToList();
        return new AskInfo(
            id,
            fields.GetValueOrDefault("task", "") is { Length: > 0 } own ? own : task,
            fields.GetValueOrDefault("flow", ""),
            fields.GetValueOrDefault("step", ""),
            fields.GetValueOrDefault("status", ""),
            modified,
            Frontmatter.Body(text),
            mine.Any(a => !a.KeepsOpen),
            held is [var seq, var reason] && mine.Any(a => a.Seq == seq) ? reason : null,
            AskParser.Parse(Frontmatter.Body(text)));
    }

    /// <summary>The steps and date of <c>setup/doctor.json</c> as factory-doctor.sh --json writes it; none and <c>""</c> when absent or unreadable.</summary>
    public (List<DoctorStep> Steps, string At) Doctor()
    {
        var path = Path.Combine(root, "setup", "doctor.json");
        try
        {
            var doctor = File.Exists(path) ? JsonSerializer.Deserialize(File.ReadAllText(path), UiJson.Default.DoctorFile) : null;
            return doctor is null
                ? ([], "")
                : ((doctor.Steps ?? []).Select(s => new DoctorStep(s.Id ?? "", s.State ?? "", s.Detail ?? "", s.Fix ?? "")).ToList(), doctor.At ?? "");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            return ([], "");
        }
    }

    /// <summary>The session registered with flow <c>ceo</c>, the most recently updated one when there are several, or null.</summary>
    public CeoInfo? Ceo()
    {
        var sessions = Path.Combine(root, "sessions");
        if (!Directory.Exists(sessions))
        {
            return null;
        }
        return Directory.EnumerateDirectories(sessions)
            .Select(d => Path.Combine(d, "session.md"))
            .Where(File.Exists)
            .Select(f => (Dir: Path.GetFileName(Path.GetDirectoryName(f))!, Fields: Frontmatter.Read(f)))
            .Where(s => s.Fields.GetValueOrDefault("flow") == "ceo")
            .OrderByDescending(s => s.Fields.GetValueOrDefault("updated", ""), StringComparer.Ordinal)
            .ThenBy(s => s.Dir, StringComparer.Ordinal)
            .Select(s => new CeoInfo(s.Dir, s.Fields.GetValueOrDefault("pane", "")))
            .FirstOrDefault();
    }

    /// <summary>The body of the newest ask of flow doctor in any session, or null.</summary>
    public string? LastDoctorNotice()
    {
        var sessions = Path.Combine(root, "sessions");
        if (!Directory.Exists(sessions))
        {
            return null;
        }
        return Directory.EnumerateFiles(sessions, "*.md", SearchOption.AllDirectories)
            .Where(f => Path.GetFileName(Path.GetDirectoryName(f)) == "asks")
            .Where(f => Frontmatter.Read(f).GetValueOrDefault("flow") == "doctor")
            .OrderByDescending(File.GetLastWriteTimeUtc)
            .Select(f => Frontmatter.Body(File.ReadAllText(f)))
            .FirstOrDefault();
    }

    static int NextSeq(string answers) =>
        Directory.EnumerateFiles(answers, "*.txt")
            .Select(f => Seq().Match(Path.GetFileName(f)))
            .Where(m => m.Success)
            .Select(m => int.Parse(m.Groups[1].Value))
            .DefaultIfEmpty(0)
            .Max() + 1;

    [GeneratedRegex(@"^[A-Za-z0-9-]+\z")]
    private static partial Regex Id();

    [GeneratedRegex(@"^([0-9]+)-")]
    private static partial Regex Seq();

    [GeneratedRegex(@"^([0-9]+)-([A-Za-z0-9-]+)\.txt\z")]
    private static partial Regex Answer();

    [GeneratedRegex(@"^Q[0-9]+ (redraw|more)\z")]
    private static partial Regex KeepsOpen();
}
