using Markdig;
using Markdig.Extensions.GenericAttributes;
using Markdig.Extensions.MediaLinks;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;

/// <summary>
/// Markdig with the advanced extensions but no generic attributes or media links, and raw HTML escaped. A link whose URL is not http, https, relative or a
/// fragment keeps its text and loses its href.
/// </summary>
public static class Md
{
    static readonly MarkdownPipeline Pipeline = BuildPipeline();

    static MarkdownPipeline BuildPipeline()
    {
        var builder = new MarkdownPipelineBuilder().UseAdvancedExtensions().DisableHtml();
        builder.Extensions.RemoveAll(e => e is GenericAttributesExtension or MediaLinkExtension);
        return builder.Build();
    }

    public static string ToHtml(string markdown)
    {
        var doc = Markdown.Parse(markdown, Pipeline);
        foreach (var link in doc.Descendants<LinkInline>().Where(l => !Safe(l.Url)).ToList())
        {
            var children = link.ToList();
            foreach (var child in children)
            {
                child.Remove();
                link.InsertBefore(child);
            }
            link.Remove();
        }
        foreach (var link in doc.Descendants<AutolinkInline>().Where(l => !Safe(l.Url)).ToList())
        {
            link.ReplaceBy(new LiteralInline(link.Url));
        }
        return doc.ToHtml(Pipeline);
    }

    public static string Inline(string markdown)
    {
        var html = ToHtml(markdown).Trim();
        return html.StartsWith("<p>", StringComparison.Ordinal) && html.EndsWith("</p>", StringComparison.Ordinal) ? html[3..^4] : html;
    }

    static bool Safe(string? url)
    {
        if (string.IsNullOrEmpty(url))
        {
            return true;
        }
        var colon = url.IndexOf(':');
        var slash = url.IndexOfAny(['/', '?', '#']);
        return colon < 0 || (slash >= 0 && slash < colon)
            || url.StartsWith("http:", StringComparison.OrdinalIgnoreCase)
            || url.StartsWith("https:", StringComparison.OrdinalIgnoreCase);
    }
}
