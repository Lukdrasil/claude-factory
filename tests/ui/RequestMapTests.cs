using Xunit;

public sealed class RequestMapTests
{
    const string Map = """
        ---
        request: R-20260925-1
        created: 2026-09-25
        ---

        Status: grilling

        ## Destination

        Invoices reach the ledger every night,
        from ecs and bff alike.

        A second paragraph that is not the destination.

        ## Notes

        Both repos post through the ledger's REST API; the human prefers one job per repo.

        ## Decisions so far

        - [Which ledger API](issues/01-which-ledger-api.md): The REST API, v2.
        - [Pick the store](issues/02-pick-the-store.md): Postgres.

        ## Not yet specified

        How the two exports are ordered once both run.

        ## Out of scope

        - [Get ledger access](issues/03-get-ledger-access.md): Access is the other team's rollout, not this request.
        - Anything about refunds.

        ## Terms

        - **Ledger**: the accounting system of record. Avoid: books

        """;

    const string Ticket = """
        # Pick the store

        Type: grilling
        Status: resolved
        Blocked by: 01, 3
        Repo: all
        Claimed by: chart_ecs-12

        ## Question

        Where the export keeps its cursor: Postgres or the ledger's file store?

        ## Answer

        Postgres.
        The export already talks to the ecs database; the file store would be a second credential.

        """;

    [Fact]
    public void The_status_is_the_first_Status_line_under_the_frontmatter()
    {
        Assert.Equal("grilling", RequestMap.Parse(Map).Status);
    }

    [Fact]
    public void The_destination_is_the_first_paragraph_of_its_section()
    {
        Assert.Equal("Invoices reach the ledger every night,\nfrom ecs and bff alike.", RequestMap.Parse(Map).Destination);
    }

    [Fact]
    public void Notes_terms_and_fog_are_their_section_text()
    {
        var map = RequestMap.Parse(Map);

        Assert.Equal("Both repos post through the ledger's REST API; the human prefers one job per repo.", map.Notes);
        Assert.Equal("- **Ledger**: the accounting system of record. Avoid: books", map.Terms);
        Assert.Equal("How the two exports are ordered once both run.", map.Fog);
    }

    [Fact]
    public void Decisions_read_title_file_and_gist_of_each_line()
    {
        var map = RequestMap.Parse(Map);

        Assert.Equal(
            [new MapLink("Which ledger API", "01-which-ledger-api.md", "The REST API, v2."), new MapLink("Pick the store", "02-pick-the-store.md", "Postgres.")],
            map.Decisions);
    }

    [Fact]
    public void Out_of_scope_reads_the_ticket_lines_and_keeps_a_boundary_without_a_ticket_as_a_title()
    {
        var map = RequestMap.Parse(Map);

        Assert.Equal(
            [
                new MapLink("Get ledger access", "03-get-ledger-access.md", "Access is the other team's rollout, not this request."),
                new MapLink("Anything about refunds.", "", ""),
            ],
            map.OutOfScope);
    }

    [Fact]
    public void An_empty_map_reads_empty_strings_and_lists()
    {
        var map = RequestMap.Parse("---\nrequest: R-20260925-2\n---\n\nStatus: charting\n\n## Destination\n\nX\n\n## Notes\n\n## Decisions so far\n\n## Not yet specified\n\n## Out of scope\n\n## Terms\n");

        Assert.Equal("charting", map.Status);
        Assert.Equal("X", map.Destination);
        Assert.Equal("", map.Notes);
        Assert.Equal("", map.Fog);
        Assert.Equal("", map.Terms);
        Assert.Empty(map.Decisions);
        Assert.Empty(map.OutOfScope);
    }

    [Fact]
    public void A_ticket_reads_its_number_from_the_file_name_and_its_fields_and_sections()
    {
        var t = Tickets.Parse("02-pick-the-store.md", Ticket);

        Assert.Equal("02", t.Nn);
        Assert.Equal("Pick the store", t.Title);
        Assert.Equal("grilling", t.Type);
        Assert.Equal("resolved", t.Status);
        Assert.Equal(["01", "03"], t.BlockedBy);
        Assert.Equal("all", t.Repo);
        Assert.Equal("chart_ecs-12", t.ClaimedBy);
        Assert.Equal("Where the export keeps its cursor: Postgres or the ledger's file store?", t.Question);
        Assert.Equal("Postgres.\nThe export already talks to the ecs database; the file store would be a second credential.", t.Answer);
    }

    [Fact]
    public void Blocked_by_none_and_claimed_by_none_read_empty()
    {
        var t = Tickets.Parse("01-which-ledger-api.md", "# Which ledger API\n\nType: research\nStatus: open\nBlocked by: none\nRepo: ecs\nClaimed by: none\n\n## Question\n\nWhich ledger API\n\n## Answer\n\n");

        Assert.Empty(t.BlockedBy);
        Assert.Equal("", t.ClaimedBy);
        Assert.Equal("", t.Answer);
        Assert.Equal("ecs", t.Repo);
    }

    static Ticket T(string nn, string status, params string[] blockedBy) =>
        new(nn, "t" + nn, "grilling", status, [.. blockedBy], "all", "", "", "");

    [Fact]
    public void The_frontier_is_the_open_tickets_whose_blockers_are_all_resolved_or_dropped_in_number_order()
    {
        var tickets = new List<Ticket>
        {
            T("01", "resolved"),
            T("02", "open", "01"),
            T("03", "dropped"),
            T("04", "open", "02"),
            T("05", "claimed"),
            T("06", "open", "01", "03"),
            T("07", "open", "05"),
            T("08", "open", "99"),
            T("10", "open"),
        };

        Assert.Equal(["02", "06", "10"], Tickets.Frontier(tickets));
    }
}
