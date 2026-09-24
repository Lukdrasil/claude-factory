using System.Text.RegularExpressions;

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
}
