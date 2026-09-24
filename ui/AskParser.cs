using System.Text.RegularExpressions;

public sealed record OptionView(string Key, string Html);

public sealed record QuestionView(string Q, string Title, string? After, string Html, List<OptionView> Options, string? Rec, string? RecKey);

public sealed record AskView(string Kind, string Preamble, List<QuestionView> Questions);

/// <summary>
/// The one reader of the canonical ask format of <c>skills/grill/SKILL.md</c>: a notice has no question, a confirm is
/// one question with the options yes and no. Options inside a fenced block are never read. A <c>❓</c> segment without a
/// question header joins the previous question's markdown, or the preamble when no question precedes it.
/// </summary>
public static partial class AskParser
{
    public static AskView Parse(string body)
    {
        var parts = Split().Split(body);
        var preamble = parts[0];
        var segments = new List<string>();
        foreach (var part in parts.Skip(1))
        {
            if (Header().IsMatch(part))
            {
                segments.Add(part);
            }
            else if (segments.Count == 0)
            {
                preamble += "❓ " + part;
            }
            else
            {
                segments[^1] += "❓ " + part;
            }
        }
        if (segments.Count == 0)
        {
            return new AskView("notice", Md.ToHtml(body), []);
        }
        var questions = segments.Select(Question).ToList();
        var raw = Options(segments[0]);
        var kind = questions.Count == 1 && string.Join(",", raw.Select(o => o.Label.Trim().ToLowerInvariant())) == "yes,no" ? "confirm" : "round";
        return new AskView(kind, Md.ToHtml(preamble), questions);
    }

    static List<(string Key, string Label)> Options(string segment) =>
        OptionLine().Matches(Fence().Replace(segment, "")).Select(m => (m.Groups[1].Value, m.Groups[2].Value.TrimEnd('\r'))).ToList();

    static QuestionView Question(string segment)
    {
        var header = Header().Match(segment);
        var rest = segment[header.Length..];
        var fences = Fence().Matches(rest).Select(m => (m.Index, m.Length)).ToList();
        var lines = new List<string>();
        string? rec = null;
        var pos = 0;
        foreach (var line in rest.Split('\n'))
        {
            var inFence = fences.Any(f => pos >= f.Index && pos < f.Index + f.Length);
            pos += line.Length + 1;
            if (!inFence && OptionLine().IsMatch(line))
            {
                continue;
            }
            if (!inFence && line.StartsWith("➡️ ", StringComparison.Ordinal))
            {
                rec ??= line["➡️ ".Length..].TrimEnd('\r');
                continue;
            }
            lines.Add(line);
        }
        var after = header.Groups[3].Success ? header.Groups[3].Value : null;
        return new QuestionView(
            header.Groups[1].Value,
            Md.Inline(header.Groups[2].Value),
            after,
            Md.ToHtml(string.Join('\n', lines)),
            Options(rest).Select(o => new OptionView(o.Key, Md.Inline(o.Label))).ToList(),
            rec is null ? null : Md.Inline(rec),
            rec is not null && RecKey().Match(rec) is { Success: true } k ? k.Groups[1].Value : null);
    }

    [GeneratedRegex(@"^❓ ", RegexOptions.Multiline)]
    private static partial Regex Split();

    [GeneratedRegex(@"^\*\*(Q\d+)\*\* - \*\*(.+?)\*\*(?: \((after [^)]*)\))?:?")]
    private static partial Regex Header();

    [GeneratedRegex(@"^[ \t]+\*\*([A-Z])\*\* (.+)$", RegexOptions.Multiline)]
    private static partial Regex OptionLine();

    [GeneratedRegex(@"^```[^\n]*\n[\s\S]*?^```[ \t]*$", RegexOptions.Multiline)]
    private static partial Regex Fence();

    [GeneratedRegex(@"^\*\*([A-Z])\*\*")]
    private static partial Regex RecKey();
}
