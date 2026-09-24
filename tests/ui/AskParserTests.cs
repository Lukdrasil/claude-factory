using Xunit;

public sealed class AskParserTests
{
    const string Round = """
        Round 2 of the grill, two questions.

        ❓ **Q1** - **Which store?** (after Q0): the drawer reads one store.
          **A** the state repo
          **B** the UI home

        ➡️ **A**: the state repo is the record.

        ❓ **Q2** - **Which renderer?**: the server renders.
          **A** Markdig
          **B** a JS library
        """;

    [Fact]
    public void A_round_reads_every_question_with_its_header_options_and_recommendation()
    {
        var view = AskParser.Parse(Round);

        Assert.Equal("round", view.Kind);
        Assert.Equal(["Q1", "Q2"], view.Questions.Select(q => q.Q));
        var q1 = view.Questions[0];
        Assert.Equal("Which store?", q1.Title);
        Assert.Equal("after Q0", q1.After);
        Assert.Equal(["A", "B"], q1.Options.Select(o => o.Key));
        Assert.Equal(["the state repo", "the UI home"], q1.Options.Select(o => o.Html));
        Assert.Equal("<strong>A</strong>: the state repo is the record.", q1.Rec);
        Assert.Equal("A", q1.RecKey);
        Assert.Null(view.Questions[1].After);
        Assert.Null(view.Questions[1].Rec);
        Assert.Null(view.Questions[1].RecKey);
    }

    [Fact]
    public void The_text_before_the_first_question_is_the_rendered_preamble()
    {
        var view = AskParser.Parse(Round);

        Assert.Contains("<p>Round 2 of the grill, two questions.</p>", view.Preamble);
        Assert.DoesNotContain("Which store?", view.Preamble);
    }

    [Fact]
    public void A_questions_html_holds_the_header_text_but_not_its_header_option_or_recommendation_lines()
    {
        var q1 = AskParser.Parse(Round).Questions[0];

        Assert.Contains("<p>the drawer reads one store.</p>", q1.Html);
        Assert.DoesNotContain("Which store?", q1.Html);
        Assert.DoesNotContain("the UI home", q1.Html);
        Assert.DoesNotContain("the state repo is the record", q1.Html);
    }

    [Fact]
    public void A_paragraph_under_a_question_is_kept()
    {
        var q = AskParser.Parse("""
            ❓ **Q1** - **Which store?**: the drawer reads one store.

            A second paragraph with what hangs on it.
              **A** the state repo
              **B** the UI home
            """).Questions[0];

        Assert.Contains("<p>the drawer reads one store.</p>", q.Html);
        Assert.Contains("<p>A second paragraph with what hangs on it.</p>", q.Html);
    }

    [Fact]
    public void A_pipe_table_in_a_question_renders_as_a_table()
    {
        var q = AskParser.Parse("""
            ❓ **Q1** - **Explore Q3**: the options side by side.

            | option | cost |
            |---|---|
            | A | one package |
            | B | a parser we own |
              **A** take A
              **B** take B
            """).Questions[0];

        Assert.Contains("<table>", q.Html);
        Assert.Contains("<td>a parser we own</td>", q.Html);
        Assert.Equal(["A", "B"], q.Options.Select(o => o.Key));
    }

    [Fact]
    public void A_heading_section_in_a_question_renders_as_a_heading()
    {
        var q = AskParser.Parse("""
            ❓ **Q1** - **Approve the design?**: the sketch follows.

            ### Design
            One parser on the server.
              **A** yes
              **B** no
            """).Questions[0];

        Assert.Matches("<h3[^>]*>Design</h3>", q.Html);
        Assert.Contains("One parser on the server.", q.Html);
    }

    [Fact]
    public void An_option_label_with_two_inline_code_spans_renders_both_without_a_paragraph()
    {
        var q = AskParser.Parse("""
            ❓ **Q1** - **Which helper?**:
              **A** keep `parseAsk` beside `AskParser`
              **B** drop `parseAsk`
            """).Questions[0];

        Assert.Equal("keep <code>parseAsk</code> beside <code>AskParser</code>", q.Options[0].Html);
    }

    [Fact]
    public void An_option_like_line_inside_a_fenced_block_is_code_not_an_option()
    {
        var q = AskParser.Parse("""
            ❓ **Q1** - **Apply this diff?**: the change.

            ```
              **C** not an option
            ```
              **A** apply
              **B** skip
            """).Questions[0];

        Assert.Equal(["A", "B"], q.Options.Select(o => o.Key));
        Assert.Contains("<pre><code>", q.Html);
        Assert.Contains("**C** not an option", q.Html);
    }

    [Fact]
    public void The_walks_numbered_body_with_list_options_is_a_notice_whose_preamble_is_the_whole_body()
    {
        var view = AskParser.Parse("""
            Resumed after the break.

            ❓ **Q10.** Which store should the drawer read?
            - A) the state repo
            - B) the UI home

            Recommendation: A.
            """);

        Assert.Equal("notice", view.Kind);
        Assert.Empty(view.Questions);
        Assert.Contains("Resumed after the break.", view.Preamble);
        Assert.Contains("Which store should the drawer read?", view.Preamble);
        Assert.Contains("the state repo", view.Preamble);
        Assert.Contains("the UI home", view.Preamble);
        Assert.Contains("Recommendation: A.", view.Preamble);
    }

    [Fact]
    public void A_body_without_a_question_is_a_notice()
    {
        var view = AskParser.Parse("## Doctor\n\nAll checks passed.\n");

        Assert.Equal("notice", view.Kind);
        Assert.Empty(view.Questions);
        Assert.Contains("<p>All checks passed.</p>", view.Preamble);
    }

    [Fact]
    public void One_question_with_the_options_yes_and_no_is_a_confirm()
    {
        var view = AskParser.Parse("""
            ❓ **Q1** - **Approve T-247?**:
              **A** Yes
              **B** no
            """);

        Assert.Equal("confirm", view.Kind);
    }

    [Fact]
    public void One_question_with_other_options_is_a_round()
    {
        var view = AskParser.Parse("""
            ❓ **Q1** - **Approve T-247?**:
              **A** yes
              **B** no
              **C** later
            """);

        Assert.Equal("round", view.Kind);
    }

    [Fact]
    public void Raw_html_is_escaped_in_the_preamble_and_in_an_option_label()
    {
        var view = AskParser.Parse("""
            <script>alert(1)</script>

            ❓ **Q1** - **Which?**:
              **A** <script>alert(2)</script>
              **B** plain
            """);

        Assert.DoesNotContain("<script>", view.Preamble);
        Assert.Contains("&lt;script&gt;", view.Preamble);
        Assert.DoesNotContain("<script>", view.Questions[0].Options[0].Html);
        Assert.Contains("&lt;script&gt;", view.Questions[0].Options[0].Html);
    }

    [Theory]
    [InlineData("[run](javascript:alert(1))", "run")]
    [InlineData("[run](JavaScript:alert(1))", "run")]
    [InlineData("[run](data:text/html,x)", "run")]
    [InlineData("[run][r]\n\n[r]: javascript:alert(1)", "run")]
    [InlineData("<javascript:alert(1)>", "javascript:alert(1)")]
    public void A_link_whose_url_is_not_http_https_relative_or_a_fragment_has_no_href(string markdown, string text)
    {
        var html = Md.ToHtml(markdown);

        Assert.Contains(text, html);
        Assert.DoesNotContain("href", html);
    }

    [Theory]
    [InlineData("[run](https://example.test/a)", "https://example.test/a")]
    [InlineData("[run](http://example.test/a)", "http://example.test/a")]
    [InlineData("[run](docs/a.md)", "docs/a.md")]
    [InlineData("[run](#q1)", "#q1")]
    public void A_link_to_http_https_a_relative_path_or_a_fragment_keeps_its_href(string markdown, string href)
    {
        Assert.Contains($"href=\"{href}\"", Md.ToHtml(markdown));
    }

    [Fact]
    public void A_javascript_link_in_an_option_label_has_no_href()
    {
        var q = AskParser.Parse("""
            ❓ **Q1** - **Which?**:
              **A** [run](javascript:alert(1))
              **B** plain
            """).Questions[0];

        Assert.Contains("run", q.Options[0].Html);
        Assert.DoesNotContain("href", q.Options[0].Html);
    }

    [Fact]
    public void Inline_renders_one_line_without_its_wrapping_paragraph()
    {
        Assert.Equal("<strong>A</strong> and <code>b</code>", Md.Inline("**A** and `b`"));
    }
}
