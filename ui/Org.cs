using System.Globalization;
using System.Text.RegularExpressions;

public sealed record SlotUse(int Used, int? Cap);

public sealed record RoleUse(string Role, int Used, int? Cap);

public sealed record CapacityInfo(SlotUse Sessions, List<RoleUse> Roles);

public sealed record Lease(string Role, string Key, string Session, string Unit, string At);

public sealed record Lead(string Task, string Repo, string Request, string Priority, string Status, string Unit);

public sealed record CeoInfo(string Sid, string Pane);

public sealed record OrgInfo(CapacityInfo Capacity, List<Lease> Leases, List<Lead> Leads, CeoInfo? Ceo);

public sealed record PassInfo(string Scope, string Daily, string Weekly, string Due = "none");

public sealed record DoctorStep(string Id, string State, string Detail, string Fix);

/// <summary>The caps of factory.yml <c>capacity:</c> and the lease files of capacity.sh, read the way <c>capacity.sh count</c> reads them.</summary>
public static partial class Capacity
{
    /// <summary>
    /// Every <c>&lt;name&gt;: &lt;number&gt;</c> pair of the <c>capacity:</c> block in file order, <c>sessions</c> among
    /// them, in the flow or the block spelling; the block ends at the next top-level key.
    /// </summary>
    public static List<(string Name, int Cap)> Caps(string factoryYml)
    {
        var caps = new List<(string, int)>();
        var on = false;
        foreach (var raw in factoryYml.Split('\n'))
        {
            var line = raw.TrimEnd('\r');
            if (on && line.Length > 0 && line[0] is not (' ' or '\t' or '#'))
            {
                break;
            }
            if (line.StartsWith("capacity:", StringComparison.Ordinal))
            {
                on = true;
                line = line["capacity:".Length..];
            }
            if (!on)
            {
                continue;
            }
            var hash = line.IndexOf('#');
            foreach (Match m in Pair().Matches(hash >= 0 ? line[..hash] : line))
            {
                if (int.TryParse(m.Groups[2].Value, out var cap))
                {
                    caps.Add((m.Groups[1].Value, cap));
                }
            }
        }
        return caps;
    }

    /// <summary>One lease file, <c>&lt;state&gt;/.capacity/&lt;role&gt;/&lt;key&gt;</c>, of <c>role=</c>, <c>session=</c>, <c>unit=</c> and <c>at=</c> lines.</summary>
    public static Lease ParseLease(string role, string key, string text)
    {
        var lines = text.Split('\n').Select(l => l.TrimEnd('\r')).ToList();
        string Value(string name) =>
            lines.FirstOrDefault(l => l.StartsWith(name + "=", StringComparison.Ordinal)) is { } l ? l[(name.Length + 1)..] : "";
        return new Lease(role, key, Value("session"), Value("unit"), Value("at"));
    }

    /// <summary>The sessions slot, then every capped role in file order, then every role holding leases without a cap.</summary>
    public static CapacityInfo Of(List<(string Name, int Cap)> caps, List<Lease> leases)
    {
        int Used(string role) => leases.Count(l => l.Role == role);
        var first = caps.DistinctBy(c => c.Name).ToList();
        int? sessions = first.Where(c => c.Name == "sessions").Select(c => (int?)c.Cap).FirstOrDefault();
        var roles = first.Where(c => c.Name != "sessions").Select(c => new RoleUse(c.Name, Used(c.Name), c.Cap)).ToList();
        roles.AddRange(leases
            .Select(l => l.Role)
            .Where(r => r != "sessions" && first.All(c => c.Name != r))
            .Distinct()
            .Order(StringComparer.Ordinal)
            .Select(r => new RoleUse(r, Used(r), null)));
        return new CapacityInfo(new SlotUse(Used("sessions"), sessions), roles);
    }

    [GeneratedRegex(@"([A-Za-z0-9_-]+)[ \t]*:[ \t]*([0-9]+)")]
    private static partial Regex Pair();
}

/// <summary>The dates of the memory passes, one passes.yml per scope as pass-stamp.sh writes it.</summary>
public static class Passes
{
    public static PassInfo Parse(string scope, string text)
    {
        var lines = text.Split('\n').Select(l => l.TrimEnd('\r')).ToList();
        string Stamp(string kind)
        {
            var line = lines.FirstOrDefault(l => l.StartsWith(kind + ":", StringComparison.Ordinal));
            if (line is null)
            {
                return "never";
            }
            var value = line[(kind.Length + 1)..];
            var hash = value.IndexOf('#');
            value = (hash >= 0 ? value[..hash] : value).Trim();
            return value == "" ? "never" : value;
        }
        return new PassInfo(scope, Stamp("daily"), Stamp("weekly"));
    }

    /// <summary>
    /// Which pass of a scope is due, <c>daily</c>, <c>weekly</c>, <c>both</c> or <c>none</c>, by the rule of
    /// <c>pass-stamp.sh --due</c>: a pass with work whose stamp is never, unreadable, or 24 h (daily) or 7 d (weekly) old or more.
    /// </summary>
    public static string Due(PassInfo pass, bool dailyWork, bool weeklyWork, DateTimeOffset now)
    {
        bool Old(string stamp, TimeSpan max) =>
            !DateTimeOffset.TryParseExact(stamp, "yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var at)
            || now - at >= max;
        return (dailyWork && Old(pass.Daily, TimeSpan.FromHours(24)), weeklyWork && Old(pass.Weekly, TimeSpan.FromDays(7))) switch
        {
            (true, true) => "both",
            (true, false) => "daily",
            (false, true) => "weekly",
            _ => "none",
        };
    }

    /// <summary>The scope of a passes.yml by its path in the state repo, null for a path no scope owns.</summary>
    public static string? ScopeOf(string relative) =>
        relative.Split('/') switch
        {
            ["memory", "global", "passes.yml"] => "global",
            ["repos", var k, "memory", "passes.yml"] => $"repo:{k}",
            ["agents", var a, "memory", "passes.yml"] => $"agent:{a}",
            ["repos", var k, "agents", var a, "passes.yml"] => $"repo-agent:{k}/{a}",
            _ => null,
        };
}

/// <summary>The org: capacity in use, the leases, a lead per repo-lead lease and the CEO session; read only, a lease is never swept here.</summary>
public sealed partial class StateReader
{
    public OrgInfo Org(UiHome home)
    {
        var leases = Leases();
        var byId = ById(Entries(archive: true));
        var leads = leases
            .Where(l => l.Role == "repo-lead")
            .Select(l => byId.TryGetValue(l.Key, out var e)
                ? new Lead(l.Key, e.Fields.GetValueOrDefault("repo", ""), RequestOf(e.Fields), PriorityOf(e, byId), e.Fields.GetValueOrDefault("status", ""), l.Unit)
                : new Lead(l.Key, "", "", "", "", l.Unit))
            .ToList();
        return new OrgInfo(CapacityInUse(leases), leases, leads, home.Ceo());
    }

    /// <summary>Every <c>.capacity/&lt;role&gt;/&lt;key&gt;</c> in role and key order; dot files are the lock and temp files, a lease gone meanwhile is skipped.</summary>
    List<Lease> Leases()
    {
        var dir = Path.Combine(root, ".capacity");
        if (!Directory.Exists(dir))
        {
            return [];
        }
        var leases = new List<Lease>();
        foreach (var roleDir in Directory.EnumerateDirectories(dir).Where(d => !Path.GetFileName(d).StartsWith('.')).Order(StringComparer.Ordinal))
        {
            foreach (var file in Directory.EnumerateFiles(roleDir).Where(f => !Path.GetFileName(f).StartsWith('.')).Order(StringComparer.Ordinal))
            {
                try
                {
                    leases.Add(Capacity.ParseLease(Path.GetFileName(roleDir), Path.GetFileName(file), File.ReadAllText(file)));
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException)
                {
                }
            }
        }
        return leases;
    }

    CapacityInfo CapacityInUse(List<Lease> leases) =>
        Capacity.Of(Capacity.Caps(ReadOrNull(root, "factory.yml") ?? ""), leases);

    /// <summary>
    /// Every scope with a passes.yml or with work for a pass, global, then per repo, per agent, per repo agent, the folders
    /// <c>pass-stamp.sh --due</c> walks; one without a passes.yml reads never twice. Each carries the pass it is due for.
    /// </summary>
    List<PassInfo> Passes()
    {
        IEnumerable<string> Dirs(string folder) =>
            Directory.Exists(folder)
                ? Directory.EnumerateDirectories(folder).Where(d => !Path.GetFileName(d).StartsWith('.')).Order(StringComparer.Ordinal)
                : [];
        var folders = new[] { Path.Combine(root, "memory", "global") }
            .Concat(Dirs(Path.Combine(root, "repos")).Select(r => Path.Combine(r, "memory")))
            .Concat(Dirs(Path.Combine(root, "agents")).Select(a => Path.Combine(a, "memory")))
            .Concat(Dirs(Path.Combine(root, "repos")).SelectMany(r => Dirs(Path.Combine(r, "agents"))));
        var now = DateTimeOffset.UtcNow;
        var list = new List<PassInfo>();
        foreach (var folder in folders.Where(Directory.Exists))
        {
            var file = Path.Combine(folder, "passes.yml");
            if (global::Passes.ScopeOf(Path.GetRelativePath(root, file).Replace(Path.DirectorySeparatorChar, '/')) is not { } scope)
            {
                continue;
            }
            var proposals = Path.Combine(scope.StartsWith("repo-agent:", StringComparison.Ordinal) ? Path.Combine(folder, "memory") : folder, "proposals");
            var drafts = AnyMd(Path.Combine(folder, "drafts"));
            var daily = drafts || AnyMd(proposals);
            var weekly = drafts || (scope.StartsWith("repo-agent:", StringComparison.Ordinal)
                ? AnyMd(proposals, text => text.Split('\n').Any(l => l.StartsWith("Replaces:", StringComparison.Ordinal)))
                : daily);
            var pass = File.Exists(file) ? global::Passes.Parse(scope, File.ReadAllText(file))
                : daily || weekly ? new PassInfo(scope, "never", "never")
                : null;
            if (pass is not null)
            {
                list.Add(pass with { Due = global::Passes.Due(pass, daily, weekly, now) });
            }
        }
        return list;
    }

    /// <summary>Whether <paramref name="dir"/> holds a top-level <c>*.md</c>, a dot file aside as the shell glob leaves it, whose text passes <paramref name="text"/> when given.</summary>
    static bool AnyMd(string dir, Func<string, bool>? text = null) =>
        Directory.Exists(dir)
        && Directory.EnumerateFiles(dir, "*.md").Any(f => !Path.GetFileName(f).StartsWith('.') && (text is null || text(File.ReadAllText(f))));
}
