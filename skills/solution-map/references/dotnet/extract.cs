#!/usr/bin/env dotnet
#:package Microsoft.CodeAnalysis.CSharp@4.14.0

// Solution map extractor - deterministic, syntax only.
//
// Usage: dotnet run extract.cs -- <path to .sln|.slnx|directory> --out <map.json>
//
// Every *.cs file under each project directory is parsed with CSharpSyntaxTree (obj/, bin/, *.g.cs and
// *.Designer.cs are skipped). There is NO MSBuildWorkspace, NO compilation and NO semantic model, so
// nothing here is resolved: base types, constructor dependency types, DI registrations and method callers
// are matched by *name* on the syntax tree alone. That makes the output cheap, build-free and stable, and
// it makes it a heuristic by design:
//   - a caller edge means "a type in another component invoked a member with this name and mentions the
//     declaring type (or one of its interface names) somewhere in its file" - not a resolved call;
//   - two distinct types with the same simple name in different namespaces are conflated;
//   - a registration is attributed to every type argument whose simple name is declared in the solution.
// Read the map as a navigation aid, never as ground truth.

using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Xml.Linq;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

static class Program
{
    static int Main(string[] argv)
    {
        string? target = null;
        string? outPath = null;
        for (int i = 0; i < argv.Length; i++)
        {
            if (argv[i] == "--out" && i + 1 < argv.Length) { outPath = argv[++i]; }
            else if (target is null) { target = argv[i]; }
        }
        if (target is null || outPath is null)
        {
            Console.Error.WriteLine("usage: dotnet run extract.cs -- <path to .sln|.slnx|directory> --out <map.json>");
            return 1;
        }

        string root;
        List<string> projectFiles = new();
        if (Directory.Exists(target))
        {
            root = Path.GetFullPath(target);
            projectFiles.AddRange(Directory.EnumerateFiles(root, "*.csproj", SearchOption.AllDirectories)
                .Where(p => !IsIgnoredPath(p, root)));
        }
        else if (File.Exists(target))
        {
            string full = Path.GetFullPath(target);
            root = Path.GetDirectoryName(full)!;
            string ext = Path.GetExtension(full).ToLowerInvariant();
            if (ext == ".slnx") projectFiles.AddRange(ProjectsFromSlnx(full, root));
            else if (ext == ".sln") projectFiles.AddRange(ProjectsFromSln(full, root));
            else
            {
                Console.Error.WriteLine($"not a solution or directory: {target}");
                return 1;
            }
        }
        else
        {
            Console.Error.WriteLine($"no such path: {target}");
            return 1;
        }

        projectFiles = projectFiles.Where(File.Exists).Distinct().OrderBy(p => p, StringComparer.Ordinal).ToList();
        if (projectFiles.Count == 0)
        {
            Console.Error.WriteLine($"no project found under {target}");
            return 1;
        }

        var projects = projectFiles.Select(p => new ProjectInfo(p, root)).ToList();

        // ---- pass 1: parse every file, collect the types, per-file identifiers and registrations --------
        var types = new List<TypeInfo>();
        var registrations = new Dictionary<string, SortedSet<string>>(StringComparer.Ordinal);
        var registrationCandidates = new List<(string Kind, List<string> TypeNames)>();

        foreach (var project in projects)
        {
            foreach (var file in project.SourceFiles)
            {
                var text = File.ReadAllText(file);
                var tree = CSharpSyntaxTree.ParseText(text, path: file);
                var rootNode = tree.GetRoot();

                var identifiers = new HashSet<string>(StringComparer.Ordinal);
                foreach (var token in rootNode.DescendantTokens())
                    if (token.IsKind(SyntaxKind.IdentifierToken))
                        identifiers.Add(token.ValueText);

                foreach (var inv in rootNode.DescendantNodes().OfType<InvocationExpressionSyntax>())
                {
                    var (name, typeArgs) = InvokedName(inv.Expression);
                    if (name is null) continue;
                    string? kind = RegistrationKind(name);
                    if (kind is null) continue;
                    var names = new List<string>(typeArgs);
                    foreach (var arg in inv.ArgumentList.Arguments)
                        if (arg.Expression is TypeOfExpressionSyntax t)
                            names.Add(SimpleName(t.Type));
                    if (names.Count > 0) registrationCandidates.Add((kind, names));
                }

                foreach (var decl in rootNode.DescendantNodes().OfType<BaseTypeDeclarationSyntax>())
                {
                    if (IsNested(decl)) continue;
                    types.Add(new TypeInfo(decl, project, file, root, identifiers));
                }
            }
        }

        var declared = new HashSet<string>(types.Select(t => t.Name), StringComparer.Ordinal);
        foreach (var (kind, names) in registrationCandidates)
            foreach (var n in names)
                if (declared.Contains(n))
                {
                    if (!registrations.TryGetValue(n, out var set))
                        registrations[n] = set = new SortedSet<string>(StringComparer.Ordinal);
                    set.Add(kind);
                }

        // interfaces with more than one implementing type in the solution
        var interfaceNames = new HashSet<string>(types.Where(t => t.Kind == "interface").Select(t => t.Name), StringComparer.Ordinal);
        var implCount = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var t in types)
            foreach (var b in t.BaseNames.Distinct())
                if (interfaceNames.Contains(b) && t.Kind != "interface")
                    implCount[b] = implCount.TryGetValue(b, out var c) ? c + 1 : 1;

        foreach (var t in types)
        {
            t.Registrations = registrations.TryGetValue(t.Name, out var r) ? r.ToList() : new List<string>();
            bool hosted = t.BaseNames.Any(b => b == "BackgroundService" || b == "IHostedService");
            bool multiImpl = t.Kind == "interface" && implCount.TryGetValue(t.Name, out var c) && c > 1;
            bool endpoints = t.IsStatic && t.Name.EndsWith("Endpoints", StringComparison.Ordinal);
            t.IsService = t.Registrations.Count > 0 || hosted || multiImpl || endpoints;
        }

        // ---- callers: syntax-only heuristic, see the header comment ------------------------------------
        foreach (var t in types)
            foreach (var m in t.Methods)
            {
                var callers = new SortedSet<string>(StringComparer.Ordinal);
                foreach (var other in types)
                {
                    if (ReferenceEquals(other, t) || other.Name == t.Name) continue;
                    if (other.Project == t.Project && other.Component == t.Component) continue;
                    if (!other.InvokedNames.Contains(m.Name)) continue;
                    if (!other.FileIdentifiers.Contains(t.Name) &&
                        !t.BaseNames.Any(b => interfaceNames.Contains(b) && other.FileIdentifiers.Contains(b)))
                        continue;
                    callers.Add(other.Name);
                }
                m.Callers = callers.ToList();
            }

        // ---- emit -------------------------------------------------------------------------------------
        var map = new JsonObject
        {
            ["commit"] = GitCommit(root),
            ["generatedAt"] = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture),
            ["projects"] = new JsonArray(projects.OrderBy(p => p.Name, StringComparer.Ordinal)
                .Select(p => ProjectNode(p, types)).ToArray()),
        };

        var json = map.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
        var outDir = Path.GetDirectoryName(Path.GetFullPath(outPath));
        if (!string.IsNullOrEmpty(outDir)) Directory.CreateDirectory(outDir);
        File.WriteAllText(outPath, json + "\n");
        Console.WriteLine($"{projects.Count} projects, {types.Count} types -> {outPath}");
        return 0;
    }

    static JsonNode ProjectNode(ProjectInfo p, List<TypeInfo> allTypes)
    {
        var mine = allTypes.Where(t => t.Project == p.Name).ToList();
        var components = mine.GroupBy(t => t.Component, StringComparer.Ordinal)
            .OrderBy(g => g.Key, StringComparer.Ordinal)
            .Select(g =>
            {
                var folders = g.Select(t => t.FirstDir).Distinct(StringComparer.Ordinal).ToList();
                string folder = g.Key.Length == 0 ? "" : (folders.Count == 1 ? folders[0] : "");
                return (JsonNode)new JsonObject
                {
                    ["namespace"] = g.Key.Length == 0 ? p.RootNamespace : p.RootNamespace + "." + g.Key,
                    ["folder"] = folder,
                    ["types"] = new JsonArray(g.OrderBy(t => t.Name, StringComparer.Ordinal)
                        .Select(TypeNode).ToArray()),
                };
            }).ToArray();

        return new JsonObject
        {
            ["name"] = p.Name,
            ["path"] = p.RelativePath,
            ["references"] = new JsonArray(p.References.OrderBy(r => r, StringComparer.Ordinal)
                .Select(r => (JsonNode)JsonValue.Create(r)!).ToArray()),
            ["components"] = new JsonArray(components),
        };
    }

    static JsonNode TypeNode(TypeInfo t) => new JsonObject
    {
        ["name"] = t.Name,
        ["kind"] = t.Kind,
        ["file"] = t.RelativeFile,
        ["visibility"] = t.Visibility,
        ["isService"] = t.IsService,
        ["registrations"] = new JsonArray(t.Registrations.Select(r => (JsonNode)JsonValue.Create(r)!).ToArray()),
        ["ctorDeps"] = new JsonArray(t.CtorDeps.Select(d => (JsonNode)JsonValue.Create(d)!).ToArray()),
        ["methods"] = new JsonArray(t.Methods.OrderBy(m => m.Signature, StringComparer.Ordinal)
            .Select(m => (JsonNode)new JsonObject
            {
                ["signature"] = m.Signature,
                ["callers"] = new JsonArray(m.Callers.Select(c => (JsonNode)JsonValue.Create(c)!).ToArray()),
            }).ToArray()),
    };

    // ---- solution parsing -----------------------------------------------------------------------------

    static IEnumerable<string> ProjectsFromSlnx(string slnx, string root)
    {
        XDocument doc;
        try { doc = XDocument.Load(slnx); }
        catch (Exception ex) { Console.Error.WriteLine($"cannot read {slnx}: {ex.Message}"); return Array.Empty<string>(); }
        return doc.Descendants()
            .Where(e => e.Name.LocalName == "Project")
            .Select(e => (string?)e.Attribute("Path"))
            .Where(v => !string.IsNullOrWhiteSpace(v))
            .Select(v => Path.GetFullPath(Path.Combine(root, v!.Replace('\\', '/'))))
            .Where(p => p.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
            .ToList();
    }

    static IEnumerable<string> ProjectsFromSln(string sln, string root)
    {
        var result = new List<string>();
        foreach (var line in File.ReadAllLines(sln))
        {
            if (!line.TrimStart().StartsWith("Project(", StringComparison.Ordinal)) continue;
            int eq = line.IndexOf('=');
            if (eq < 0) continue;
            var parts = line.Substring(eq + 1).Split(',');
            if (parts.Length < 2) continue;
            var path = parts[1].Trim().Trim('"').Replace('\\', '/');
            if (!path.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase)) continue;
            result.Add(Path.GetFullPath(Path.Combine(root, path)));
        }
        return result;
    }

    static bool IsIgnoredPath(string path, string root)
    {
        var rel = Path.GetRelativePath(root, path).Replace('\\', '/');
        return rel.Split('/').Any(seg => seg is "obj" or "bin");
    }

    static string GitCommit(string dir)
    {
        try
        {
            var psi = new ProcessStartInfo("git", "rev-parse --short HEAD")
            {
                WorkingDirectory = dir,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            using var proc = Process.Start(psi);
            if (proc is null) return "unknown";
            string outp = proc.StandardOutput.ReadToEnd().Trim();
            proc.WaitForExit();
            return proc.ExitCode == 0 && outp.Length > 0 ? outp : "unknown";
        }
        catch { return "unknown"; }
    }

    // ---- syntax helpers -------------------------------------------------------------------------------

    static bool IsNested(SyntaxNode decl) =>
        decl.Parent is BaseTypeDeclarationSyntax;

    internal static string SimpleName(TypeSyntax type) => type switch
    {
        IdentifierNameSyntax id => id.Identifier.ValueText,
        GenericNameSyntax g => g.Identifier.ValueText,
        QualifiedNameSyntax q => SimpleName(q.Right),
        AliasQualifiedNameSyntax a => SimpleName(a.Name),
        NullableTypeSyntax n => SimpleName(n.ElementType),
        ArrayTypeSyntax a => SimpleName(a.ElementType) + "[]",
        PredefinedTypeSyntax p => p.Keyword.ValueText,
        _ => type.ToString(),
    };

    static (string? Name, List<string> TypeArgs) InvokedName(ExpressionSyntax expr)
    {
        SimpleNameSyntax? simple = expr switch
        {
            MemberAccessExpressionSyntax m => m.Name,
            MemberBindingExpressionSyntax b => b.Name,
            SimpleNameSyntax s => s,
            _ => null,
        };
        if (simple is null) return (null, new List<string>());
        var args = simple is GenericNameSyntax g
            ? g.TypeArgumentList.Arguments.Select(SimpleName).ToList()
            : new List<string>();
        return (simple.Identifier.ValueText, args);
    }

    static string? RegistrationKind(string member) => member switch
    {
        "AddSingleton" => "Singleton",
        "AddScoped" => "Scoped",
        "AddTransient" => "Transient",
        "AddHostedService" => "HostedService",
        _ => null,
    };

    // ---- models ---------------------------------------------------------------------------------------

    internal sealed class ProjectInfo
    {
        public ProjectInfo(string csproj, string root)
        {
            Path_ = csproj;
            Directory_ = System.IO.Path.GetDirectoryName(csproj)!;
            Name = System.IO.Path.GetFileNameWithoutExtension(csproj);
            RelativePath = System.IO.Path.GetRelativePath(root, csproj).Replace('\\', '/');

            string? rootNs = null;
            var refs = new List<string>();
            try
            {
                var doc = XDocument.Load(csproj);
                rootNs = doc.Descendants().FirstOrDefault(e => e.Name.LocalName == "RootNamespace")?.Value.Trim();
                foreach (var pr in doc.Descendants().Where(e => e.Name.LocalName == "ProjectReference"))
                {
                    var include = (string?)pr.Attribute("Include");
                    if (string.IsNullOrWhiteSpace(include)) continue;
                    refs.Add(System.IO.Path.GetFileNameWithoutExtension(include!.Replace('\\', '/')));
                }
            }
            catch { }
            RootNamespace = string.IsNullOrWhiteSpace(rootNs) ? Name : rootNs!;
            References = refs.Distinct().ToList();

            SourceFiles = System.IO.Directory
                .EnumerateFiles(Directory_, "*.cs", SearchOption.AllDirectories)
                .Where(f => !IsIgnoredPath(f, Directory_))
                .Where(f => !f.EndsWith(".g.cs", StringComparison.OrdinalIgnoreCase))
                .Where(f => !f.EndsWith(".Designer.cs", StringComparison.OrdinalIgnoreCase))
                .OrderBy(f => f, StringComparer.Ordinal)
                .ToList();
        }

        public string Path_ { get; }
        public string Directory_ { get; }
        public string Name { get; }
        public string RelativePath { get; }
        public string RootNamespace { get; }
        public List<string> References { get; }
        public List<string> SourceFiles { get; }
    }

    internal sealed class MethodInfo
    {
        public MethodInfo(string name, string signature) { Name = name; Signature = signature; }
        public string Name { get; }
        public string Signature { get; }
        public List<string> Callers { get; set; } = new();
    }

    internal sealed class TypeInfo
    {
        public TypeInfo(BaseTypeDeclarationSyntax decl, ProjectInfo project, string file, string root,
                        HashSet<string> fileIdentifiers)
        {
            Name = decl.Identifier.ValueText;
            Kind = decl switch
            {
                RecordDeclarationSyntax => "record",
                InterfaceDeclarationSyntax => "interface",
                EnumDeclarationSyntax => "enum",
                StructDeclarationSyntax => "struct",
                _ => "class",
            };
            Project = project.Name;
            RelativeFile = Path.GetRelativePath(root, file).Replace('\\', '/');
            FileIdentifiers = fileIdentifiers;
            IsStatic = decl.Modifiers.Any(m => m.IsKind(SyntaxKind.StaticKeyword));
            Visibility = Vis(decl.Modifiers);

            var ns = Namespaces(decl);
            Namespace = ns;
            Component = ComponentOf(ns, project.RootNamespace);

            var relDir = Path.GetRelativePath(project.Directory_, Path.GetDirectoryName(file)!).Replace('\\', '/');
            FirstDir = relDir is "." or "" ? "" : relDir.Split('/')[0];

            BaseNames = decl.BaseList is null
                ? new List<string>()
                : decl.BaseList.Types.Select(b => SimpleName(b.Type)).ToList();

            // constructor dependencies: declared constructors plus the primary constructor
            var deps = new List<string>();
            if (decl is TypeDeclarationSyntax td)
            {
                if (td.ParameterList is not null)
                    foreach (var p in td.ParameterList.Parameters)
                        if (p.Type is not null) deps.Add(SimpleName(p.Type));
                foreach (var ctor in td.Members.OfType<ConstructorDeclarationSyntax>())
                    foreach (var p in ctor.ParameterList.Parameters)
                        if (p.Type is not null) deps.Add(SimpleName(p.Type));

                bool isInterface = decl is InterfaceDeclarationSyntax;
                foreach (var m in td.Members.OfType<MethodDeclarationSyntax>())
                {
                    string v = Vis(m.Modifiers, isInterface ? "public" : "private");
                    if (v != "public" && v != "internal") continue;
                    var ps = m.ParameterList.Parameters
                        .Select(p => (p.Type is null ? "?" : SimpleName(p.Type)) + " " + p.Identifier.ValueText);
                    Methods.Add(new MethodInfo(m.Identifier.ValueText,
                        m.Identifier.ValueText + "(" + string.Join(", ", ps) + ")"));
                }
            }
            CtorDeps = deps.Distinct(StringComparer.Ordinal).ToList();

            foreach (var inv in decl.DescendantNodes().OfType<InvocationExpressionSyntax>())
            {
                var (n, _) = InvokedName(inv.Expression);
                if (n is not null) InvokedNames.Add(n);
            }
        }

        public string Name { get; }
        public string Kind { get; }
        public string Project { get; }
        public string Namespace { get; }
        public string Component { get; }
        public string FirstDir { get; }
        public string RelativeFile { get; }
        public string Visibility { get; }
        public bool IsStatic { get; }
        public List<string> BaseNames { get; }
        public List<string> CtorDeps { get; }
        public List<MethodInfo> Methods { get; } = new();
        public HashSet<string> InvokedNames { get; } = new(StringComparer.Ordinal);
        public HashSet<string> FileIdentifiers { get; }
        public List<string> Registrations { get; set; } = new();
        public bool IsService { get; set; }

        static string Vis(SyntaxTokenList mods, string fallback = "internal")
        {
            bool pub = mods.Any(m => m.IsKind(SyntaxKind.PublicKeyword));
            bool prot = mods.Any(m => m.IsKind(SyntaxKind.ProtectedKeyword));
            bool intl = mods.Any(m => m.IsKind(SyntaxKind.InternalKeyword));
            bool priv = mods.Any(m => m.IsKind(SyntaxKind.PrivateKeyword));
            if (pub) return "public";
            if (prot) return priv ? "private protected" : (intl ? "protected internal" : "protected");
            if (intl) return "internal";
            if (priv) return "private";
            return fallback;
        }

        static string Namespaces(SyntaxNode node)
        {
            var parts = new List<string>();
            for (var p = node.Parent; p is not null; p = p.Parent)
            {
                if (p is NamespaceDeclarationSyntax nd) parts.Insert(0, nd.Name.ToString());
                else if (p is FileScopedNamespaceDeclarationSyntax fd) parts.Insert(0, fd.Name.ToString());
            }
            return string.Join(".", parts);
        }

        // The component is the first namespace segment after the project's root namespace. A type directly
        // in the root namespace lands in the component "". A namespace outside the root namespace falls
        // back to its own first segment.
        static string ComponentOf(string ns, string rootNamespace)
        {
            if (ns.Length == 0) return "";
            if (string.Equals(ns, rootNamespace, StringComparison.Ordinal)) return "";
            if (ns.StartsWith(rootNamespace + ".", StringComparison.Ordinal))
                return ns.Substring(rootNamespace.Length + 1).Split('.')[0];
            return ns.Split('.')[0];
        }
    }
}
