using System.Text.RegularExpressions;

public sealed record RequestRow(string Id, string Status, string Destination, string Priority, List<string> Parents, bool Archived);

public sealed record MapLink(string Title, string File, string Gist);

public sealed record Ticket(
    string Nn, string Title, string Type, string Status, List<string> BlockedBy, string Repo, string ClaimedBy, string Question, string Answer);

public sealed record BlockInfo(string Id, string Status, string Goal, string Acceptance);

public sealed record ParentInfo(string Id, string Repo, string Priority, string Status, string Goal, string Acceptance, List<BlockInfo> Blocks);

public sealed record RequestDetail(
    string Id,
    string Status,
    string Destination,
    string Notes,
    string Terms,
    bool Archived,
    List<MapLink> Decisions,
    List<MapLink> OutOfScope,
    string Fog,
    List<Ticket> Tickets,
    List<string> Frontier,
    List<ParentInfo> Parents);

/// <summary>
/// One <c>requests/&lt;R-id&gt;/map.md</c> in the shape of skills/wayfinder/references/format.md: the <c>Status:</c>
/// line under the frontmatter and the six sections.
/// </summary>
public sealed partial record RequestMap(
    string Status, string Destination, string Notes, string Terms, string Fog, List<MapLink> Decisions, List<MapLink> OutOfScope)
{
    public static RequestMap Parse(string text)
    {
        var body = Frontmatter.Body(text);
        var status = body.Split('\n').Select(l => l.TrimEnd('\r')).FirstOrDefault(l => l.StartsWith("Status:", StringComparison.Ordinal));
        return new RequestMap(
            status is null ? "" : status["Status:".Length..].Trim(),
            string.Join('\n', Sections.Of(body, "Destination").Split('\n').TakeWhile(l => !string.IsNullOrWhiteSpace(l))),
            Sections.Of(body, "Notes"),
            Sections.Of(body, "Terms"),
            Sections.Of(body, "Not yet specified"),
            Links(Sections.Of(body, "Decisions so far")),
            Links(Sections.Of(body, "Out of scope")));
    }

    /// <summary><c>- [&lt;title&gt;](issues/&lt;file&gt;): &lt;gist&gt;</c> per line; any other line is a title without a ticket.</summary>
    static List<MapLink> Links(string section) =>
        section.Split('\n', StringSplitOptions.RemoveEmptyEntries)
            .Where(l => !string.IsNullOrWhiteSpace(l))
            .Select(l => Link().Match(l) is { Success: true } m
                ? new MapLink(m.Groups[1].Value, m.Groups[2].Value, m.Groups[3].Value.Trim())
                : new MapLink(l.TrimStart('-', ' ').Trim(), "", ""))
            .ToList();

    [GeneratedRegex(@"^- \[(.+?)\]\(issues/([^)\s]+)\):[ \t]*(.*)$")]
    private static partial Regex Link();
}

/// <summary>The decision tickets of a map, <c>requests/&lt;R-id&gt;/issues/NN-&lt;slug&gt;.md</c>.</summary>
public static partial class Tickets
{
    public static Ticket Parse(string fileName, string text)
    {
        var lines = text.Split('\n').Select(l => l.TrimEnd('\r')).ToList();
        var head = lines.TakeWhile(l => !l.StartsWith("## ", StringComparison.Ordinal)).ToList();
        string Field(string name) =>
            head.FirstOrDefault(l => l.StartsWith(name + ":", StringComparison.Ordinal)) is { } l ? l[(name.Length + 1)..].Trim() : "";
        var blocked = Field("Blocked by");
        var claimed = Field("Claimed by");
        return new Ticket(
            Number().Match(fileName) is { Success: true } m ? Nn(m.Groups[1].Value) : "",
            head.FirstOrDefault(l => l.StartsWith("# ", StringComparison.Ordinal))?[2..].Trim() ?? "",
            Field("Type"),
            Field("Status"),
            blocked is "" or "none"
                ? []
                : blocked.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries).Select(Nn).ToList(),
            Field("Repo"),
            claimed == "none" ? "" : claimed,
            Sections.Of(text, "Question"),
            Sections.Of(text, "Answer"));
    }

    /// <summary>The open tickets whose every blocker is a ticket resolved or dropped, in the order given.</summary>
    public static List<string> Frontier(IReadOnlyList<Ticket> tickets)
    {
        var closed = tickets.Where(t => t.Status is "resolved" or "dropped").Select(t => t.Nn).ToHashSet(StringComparer.Ordinal);
        return tickets.Where(t => t.Status == "open" && t.BlockedBy.All(closed.Contains)).Select(t => t.Nn).ToList();
    }

    /// <summary>A ticket number with two digits at least, so <c>1</c> and <c>01</c> read the same.</summary>
    static string Nn(string digits)
    {
        var n = digits.TrimStart('0');
        return (n == "" ? "0" : n).PadLeft(2, '0');
    }

    [GeneratedRegex(@"^([0-9]+)-")]
    private static partial Regex Number();
}

public static class Sections
{
    /// <summary>The body of the <c>## &lt;heading&gt;</c> section up to the next <c>## </c> heading, blank lines at both ends dropped.</summary>
    public static string Of(string text, string heading)
    {
        var lines = new List<string>();
        var on = false;
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.TrimEnd('\r');
            if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                if (on)
                {
                    break;
                }
                on = line == "## " + heading;
                continue;
            }
            if (on)
            {
                lines.Add(line);
            }
        }
        var start = lines.FindIndex(l => !string.IsNullOrWhiteSpace(l));
        var end = lines.FindLastIndex(l => !string.IsNullOrWhiteSpace(l));
        return start < 0 ? "" : string.Join('\n', lines[start..(end + 1)]);
    }
}

/// <summary>The request maps of the state repo, live under <c>requests/</c> and archived under <c>requests/archive/&lt;YYYY-MM&gt;/</c>.</summary>
public sealed partial class StateReader
{
    /// <summary>Every request, newest id first, with the parents whose <c>request:</c> names it, live and archived.</summary>
    public List<RequestRow> Requests()
    {
        var byId = ById(Entries(archive: true));
        return RequestDirs()
            .OrderDescending(Comparer<(string Id, string Dir, bool Archived)>.Create((a, b) => CompareIds(a.Id, b.Id)))
            .Select(r =>
            {
                var map = RequestMap.Parse(Frontmatter.Load(Path.Combine(r.Dir, "map.md")).Text);
                var parents = ParentsOf(r.Id, byId);
                return new RequestRow(r.Id, map.Status, map.Destination, Best(parents.Select(p => PriorityOf(p, byId))),
                    parents.Select(p => p.Id).ToList(), r.Archived);
            })
            .ToList();
    }

    /// <summary>One request with its tickets, frontier and parents with their blocks; null when it is neither live nor archived.</summary>
    public RequestDetail? Request(string id)
    {
        var found = RequestId().IsMatch(id) ? RequestDirs().FirstOrDefault(r => r.Id == id) : default;
        if (found.Id is null)
        {
            return null;
        }
        var (_, dir, archived) = found;
        var map = RequestMap.Parse(Frontmatter.Load(Path.Combine(dir, "map.md")).Text);
        var issues = Path.Combine(dir, "issues");
        var tickets = Directory.Exists(issues)
            ? Directory.EnumerateFiles(issues, "*.md")
                .Select(f => Tickets.Parse(Path.GetFileName(f), Frontmatter.Load(f).Text))
                .Where(t => t.Nn != "")
                .Order(Comparer<Ticket>.Create((a, b) => CompareIds(a.Nn, b.Nn)))
                .ToList()
            : [];
        var byId = ById(Entries(archive: true));
        var parents = ParentsOf(id, byId)
            .Select(p => new ParentInfo(
                p.Id,
                p.Fields.GetValueOrDefault("repo", ""),
                PriorityOf(p, byId),
                p.Fields.GetValueOrDefault("status", ""),
                Goal(Frontmatter.Body(p.Text)),
                Sections.Of(Frontmatter.Body(p.Text), "Acceptance"),
                byId.Values
                    .Where(b => BlockId().Match(b.Id) is { Success: true } m && m.Groups[1].Value == p.Id)
                    .Order(Comparer<Entry>.Create((a, b) => CompareIds(a.Id, b.Id)))
                    .Select(b => new BlockInfo(b.Id, b.Fields.GetValueOrDefault("status", ""), Goal(Frontmatter.Body(b.Text)),
                        Sections.Of(Frontmatter.Body(b.Text), "Acceptance")))
                    .ToList()))
            .ToList();
        return new RequestDetail(id, map.Status, map.Destination, map.Notes, map.Terms, archived, map.Decisions, map.OutOfScope,
            map.Fog, tickets, Tickets.Frontier(tickets), parents);
    }

    /// <summary>Request folders holding a map.md, live first, an id archived and live at once read live.</summary>
    List<(string Id, string Dir, bool Archived)> RequestDirs()
    {
        var requests = Path.Combine(root, "requests");
        if (!Directory.Exists(requests))
        {
            return [];
        }
        var archive = Path.Combine(requests, "archive");
        var live = Directory.EnumerateDirectories(requests).Select(d => (Dir: d, Archived: false));
        var archived = Directory.Exists(archive)
            ? Directory.EnumerateDirectories(archive).SelectMany(Directory.EnumerateDirectories).Select(d => (Dir: d, Archived: true))
            : [];
        return live.Concat(archived)
            .Where(r => RequestId().IsMatch(Path.GetFileName(r.Dir)) && File.Exists(Path.Combine(r.Dir, "map.md")))
            .Select(r => (Id: Path.GetFileName(r.Dir), r.Dir, r.Archived))
            .DistinctBy(r => r.Id)
            .ToList();
    }

    static List<Entry> ParentsOf(string request, Dictionary<string, Entry> byId) =>
        byId.Values
            .Where(e => ParentId().IsMatch(e.Id) && RequestOf(e.Fields) == request)
            .Order(Comparer<Entry>.Create((a, b) => CompareIds(a.Id, b.Id)))
            .ToList();

    static string Best(IEnumerable<string> priorities) => priorities.Order(StringComparer.Ordinal).FirstOrDefault() ?? "P2";

    [GeneratedRegex(@"^R-[0-9]{8}-[0-9]+\z")]
    private static partial Regex RequestId();
}
