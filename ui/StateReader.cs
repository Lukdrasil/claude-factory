using System.Diagnostics;
using System.Text.RegularExpressions;
using Markdig;

public sealed record TaskRow(string Id, string Status, string Archetype, string Tier, string Repo, string Owner, string Goal);

public sealed record TaskDetail(
    TaskRow Task,
    Dictionary<string, string> Fields,
    string Body,
    string Html,
    List<TaskRow> Blocks,
    string? Plan,
    string? Grill,
    string? Verdicts,
    string? Progress,
    List<string> Timeline);

public sealed record Toolset(string Repo, string Text);

public sealed record SetupInfo(string Root, string? ReposYml, List<Toolset> Toolsets, string? DoctorNotice);

/// <summary>
/// The state repo mounted read-only at /state: task frontmatter, plans, grill files, verdicts, progress and the
/// git log of a task file.
/// </summary>
public sealed partial class StateReader(string root)
{
    public List<TaskRow> Tasks() => TaskFiles().Select(File.ReadAllText).Select(Row).ToList();

    public TaskDetail? Task(string id)
    {
        var file = TaskFiles().FirstOrDefault(f => Frontmatter.Read(f).GetValueOrDefault("id") == id);
        if (file is null)
        {
            return null;
        }
        var text = File.ReadAllText(file);
        var fields = Frontmatter.Parse(text);
        var body = Frontmatter.Body(text);
        var repoDir = Path.GetDirectoryName(Path.GetDirectoryName(file))!;
        var slug = PlanSlug().Match(body) is { Success: true } m ? m.Groups[1].Value : null;
        return new TaskDetail(
            Row(text),
            fields,
            body,
            Markdown.ToHtml(body),
            Tasks().Where(t => t.Id.StartsWith(id + "-", StringComparison.Ordinal)).ToList(),
            slug is null ? null : ReadOrNull(repoDir, "plans", $"{slug}-plan-ready.md"),
            slug is null ? null : ReadOrNull(repoDir, "plans", $"{slug}-grill.md"),
            slug is null ? null : ReadOrNull(repoDir, "verdicts", $"{slug}.md"),
            ReadOrNull(repoDir, "progress", $"{id}.md"),
            Timeline(Path.GetRelativePath(root, file)));
    }

    public SetupInfo Setup(UiHome home) => new(
        Environment.GetEnvironmentVariable("FACTORY_ROOT") ?? Path.GetDirectoryName(root) ?? root,
        ReadOrNull(root, "repos.yml"),
        Directory.Exists(Path.Combine(root, "repos"))
            ? Directory.EnumerateDirectories(Path.Combine(root, "repos"))
                .Where(d => File.Exists(Path.Combine(d, "toolset.md")))
                .Select(d => new Toolset(Path.GetFileName(d), File.ReadAllText(Path.Combine(d, "toolset.md"))))
                .ToList()
            : [],
        home.LastDoctorNotice());

    IEnumerable<string> TaskFiles()
    {
        var repos = Path.Combine(root, "repos");
        return Directory.Exists(repos)
            ? Directory.EnumerateDirectories(repos)
                .Select(d => Path.Combine(d, "tasks"))
                .Where(Directory.Exists)
                .SelectMany(d => Directory.EnumerateFiles(d, "*.md"))
                .Order(StringComparer.Ordinal)
            : [];
    }

    static TaskRow Row(string text)
    {
        var f = Frontmatter.Parse(text);
        var owner = f.GetValueOrDefault("owner", "");
        return new TaskRow(
            f.GetValueOrDefault("id", ""),
            f.GetValueOrDefault("status", ""),
            f.GetValueOrDefault("archetype", ""),
            f.GetValueOrDefault("tier", ""),
            f.GetValueOrDefault("repo", ""),
            owner is "" or "null" ? "-" : owner,
            Goal(Frontmatter.Body(text)));
    }

    static string Goal(string body) =>
        body.Split('\n')
            .SkipWhile(l => !l.StartsWith('#'))
            .Skip(1)
            .FirstOrDefault(l => !string.IsNullOrWhiteSpace(l))?.TrimEnd('\r') ?? "";

    static string? ReadOrNull(params string[] parts)
    {
        var path = Path.Combine(parts);
        return File.Exists(path) ? File.ReadAllText(path) : null;
    }

    List<string> Timeline(string relative)
    {
        var git = new ProcessStartInfo("git") { RedirectStandardOutput = true };
        foreach (var arg in new[] { "-C", root, "log", "--format=%h%x09%aI%x09%s", "--", relative })
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

    [GeneratedRegex(@"plans/([A-Za-z0-9._-]+)-plan-ready\.md")]
    private static partial Regex PlanSlug();
}

public static class Frontmatter
{
    public static Dictionary<string, string> Read(string path) => Parse(File.ReadAllText(path));

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
