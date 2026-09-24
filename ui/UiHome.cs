using System.Text.RegularExpressions;

public sealed record AskInfo(string Ask, string Task, string Flow, string Step, string Status, DateTime Modified, string Body, bool Sent, string? Held);

public sealed record SessionInfo(string Sid, string Pane, string Flow, string Task, string Step, List<AskInfo> Asks);

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

    /// <summary>
    /// Writes <c>sessions/&lt;sid&gt;/answers/&lt;seq&gt;-&lt;ask&gt;.txt</c> with the next seq of the session
    /// through a rename, only while the ask's status is open.
    /// </summary>
    public (AnswerStatus Status, string? File) WriteAnswer(string sid, string? ask, string? text)
    {
        if (!Id().IsMatch(sid) || ask is null || !Id().IsMatch(ask) || text is null)
        {
            return (AnswerStatus.Invalid, null);
        }
        var session = Path.Combine(root, "sessions", sid);
        var askFile = Path.Combine(session, "asks", ask + ".md");
        if (!File.Exists(askFile))
        {
            return (AnswerStatus.Unknown, null);
        }
        if (Frontmatter.Read(askFile).GetValueOrDefault("status") != "open")
        {
            return (AnswerStatus.NotOpen, null);
        }
        var answers = Directory.CreateDirectory(Path.Combine(session, "answers")).FullName;
        lock (_answers)
        {
            var name = $"{NextSeq(answers)}-{ask}.txt";
            var temp = Path.Combine(answers, $".{name}.tmp");
            File.WriteAllText(temp, text);
            File.Move(temp, Path.Combine(answers, name));
            return (AnswerStatus.Written, name);
        }
    }

    /// <summary>
    /// Every session under <c>sessions/</c> with its asks. An ask is sent once an answer file names it, and held with the
    /// reason of <c>relay</c> while the relay holds one of its answers. An unreadable session is skipped.
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
        var asks = Path.Combine(dir, "asks");
        return new SessionInfo(
            Path.GetFileName(dir),
            fields.GetValueOrDefault("pane", ""),
            fields.GetValueOrDefault("flow", ""),
            fields.GetValueOrDefault("task", ""),
            fields.GetValueOrDefault("step", ""),
            Directory.Exists(asks)
                ? Directory.EnumerateFiles(asks, "*.md")
                    .Where(f => !Path.GetFileName(f).StartsWith('.'))
                    .Order(StringComparer.Ordinal)
                    .Select(f => ReadAsk(f, answers, held))
                    .ToList()
                : []);
    }

    static List<(string Seq, string Ask)> AnswerFiles(string answers) =>
        Directory.Exists(answers)
            ? Directory.EnumerateFiles(answers, "*.txt")
                .Select(f => Answer().Match(Path.GetFileName(f)))
                .Where(m => m.Success)
                .Select(m => (m.Groups[1].Value, m.Groups[2].Value))
                .ToList()
            : [];

    static AskInfo ReadAsk(string file, List<(string Seq, string Ask)> answers, string[] held)
    {
        var text = File.ReadAllText(file);
        var fields = Frontmatter.Parse(text);
        var id = fields.GetValueOrDefault("ask", Path.GetFileNameWithoutExtension(file));
        var sent = answers.Where(a => a.Ask == id).Select(a => a.Seq).ToList();
        return new AskInfo(
            id,
            fields.GetValueOrDefault("task", ""),
            fields.GetValueOrDefault("flow", ""),
            fields.GetValueOrDefault("step", ""),
            fields.GetValueOrDefault("status", ""),
            File.GetLastWriteTimeUtc(file),
            Frontmatter.Body(text),
            sent.Count > 0,
            held is [var seq, var reason] && sent.Contains(seq) ? reason : null);
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
}
