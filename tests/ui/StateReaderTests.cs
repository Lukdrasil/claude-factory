using Xunit;

/// <summary>StateReader over a throwaway state layout and UI home, without git: the board, the archive, requests, the org and setup.</summary>
public sealed class StateReaderTests : IDisposable
{
    readonly string _state = Directory.CreateTempSubdirectory("state-reader-").FullName;
    readonly string _ui = Directory.CreateTempSubdirectory("ui-home-").FullName;

    StateReader State => new(_state);
    UiHome Home => new(_ui);

    void Write(string root, string relative, string content)
    {
        var path = Path.Combine(root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
    }

    void Task(string relative, string id, string status, string? request = null, string? priority = null, string acceptance = "")
    {
        var fields = $"id: {id}\nrepo: {relative.Split('/')[1]}\nstatus: {status}\ntier: green\narchetype: feature\n"
            + (request is null ? "" : $"request: {request}\n") + (priority is null ? "" : $"priority: {priority}\n");
        var body = $"# Goal\nfeat: {id}\n\n## Context\nSome context.\n" + (acceptance == "" ? "" : $"\n## Acceptance\n{acceptance}\n\n## Out of scope\nNothing.\n");
        Write(_state, relative, $"---\n{fields}---\n\n{body}");
    }

    void Fixture()
    {
        Task("repos/ecs/tasks/T-ECS-1-export.md", "T-ECS-1", "in_progress", "R-20260925-1", "P1", "`make test` passes.");
        Task("repos/ecs/tasks/T-ECS-1-01-cursor.md", "T-ECS-1-01", "ready", "R-20260925-1", acceptance: "The cursor test passes.");
        Task("repos/ecs/tasks/T-ECS-1-02-job.md", "T-ECS-1-02", "ready", "R-20260925-1", "P3");
        Task("repos/ecs/tasks/T-ECS-2-other.md", "T-ECS-2", "ready", "null");
        Task("repos/cf/tasks/T-CF-1-ui.md", "T-CF-1", "ready", "R-20260925-1");
        Task("repos/cf/archive/2026-09/tasks/T-CF-2-old.md", "T-CF-2", "done", "R-20260920-1", "P0", "It was done.");
        Task("repos/cf/archive/2026-09/tasks/T-CF-2-01-old.md", "T-CF-2-01", "done", "R-20260920-1");
        Write(_state, "repos/cf/archive/2026-09/progress/T-CF-2.md", "The archived progress.\n");

        Write(_state, "requests/R-20260925-1/map.md",
            "---\nrequest: R-20260925-1\ncreated: 2026-09-25\n---\n\nStatus: grilling\n\n## Destination\n\nInvoices reach the ledger.\n\n## Notes\n\n"
            + "## Decisions so far\n\n- [Which API](issues/01-which-api.md): REST.\n\n## Not yet specified\n\nThe order.\n\n## Out of scope\n\n"
            + "- [Access](issues/03-access.md): Not ours.\n\n## Terms\n\n");
        Write(_state, "requests/R-20260925-1/issues/01-which-api.md",
            "# Which API\n\nType: research\nStatus: resolved\nBlocked by: none\nRepo: all\nClaimed by: s1\n\n## Question\n\nWhich API?\n\n## Answer\n\nREST.\n");
        Write(_state, "requests/R-20260925-1/issues/02-store.md",
            "# Store\n\nType: grilling\nStatus: open\nBlocked by: 01\nRepo: ecs\nClaimed by: none\n\n## Question\n\nStore\n\n## Answer\n\n");
        Write(_state, "requests/R-20260925-1/issues/03-access.md",
            "# Access\n\nType: task\nStatus: dropped\nBlocked by: none\nRepo: all\nClaimed by: none\n\n## Question\n\nAccess\n\n## Answer\n\nNot ours.\n");
        Write(_state, "requests/R-20260925-1/issues/04-order.md",
            "# Order\n\nType: grilling\nStatus: open\nBlocked by: 02\nRepo: all\nClaimed by: none\n\n## Question\n\nOrder\n\n## Answer\n\n");
        Write(_state, "requests/R-20260925-2/map.md",
            "---\nrequest: R-20260925-2\n---\n\nStatus: charting\n\n## Destination\n\nA newer one.\n\n## Notes\n\n## Decisions so far\n\n## Not yet specified\n\n## Out of scope\n\n## Terms\n\n");
        Write(_state, "requests/R-20260925-10/map.md",
            "---\nrequest: R-20260925-10\n---\n\nStatus: charting\n\n## Destination\n\nThe tenth.\n\n## Notes\n\n## Decisions so far\n\n## Not yet specified\n\n## Out of scope\n\n## Terms\n\n");
        Write(_state, "requests/archive/2026-09/R-20260920-1/map.md",
            "---\nrequest: R-20260920-1\n---\n\nStatus: done\n\n## Destination\n\nThe old one.\n\n## Notes\n\n## Decisions so far\n\n## Not yet specified\n\n## Out of scope\n\n## Terms\n\n");

        Write(_state, "factory.yml", "ui: docker\ncapacity:\n  sessions: 10\n  roles: {repo-lead: 3, scout: 8}\n");
        Write(_state, ".capacity/.gitignore", "*\n");
        Write(_state, ".capacity/.lock", "");
        Write(_state, ".capacity/sessions/T-ECS-1-lead", "role=sessions\nsession=\nunit=T-ECS-1-lead\nat=100\n");
        Write(_state, ".capacity/repo-lead/T-ECS-1", "role=repo-lead\nsession=\nunit=T-ECS-1-lead\nat=101\n");
        Write(_state, ".capacity/scout/sess-1.use-1", "role=scout\nsession=sess-1\nunit=\nat=102\n");
        Write(_state, ".capacity/scout/.agent-2.tmp", "role=scout\nsession=sess-1\nunit=\nat=103\n");
        Write(_state, ".capacity/docs-architect/T-CF-1-docs", "role=docs-architect\nsession=\nunit=T-CF-1-docs\nat=104\n");

        Write(_state, "memory/global/passes.yml", "daily: 2026-09-25T06:00:00Z\nweekly: never\n");
        Write(_state, "repos/ecs/memory/passes.yml", "daily: never\nweekly: 2026-09-20T07:00:00Z\n");
        Write(_state, "repos/ecs/agents/implementer/passes.yml", "daily: 2026-09-24T05:00:00Z\nweekly: never\n");
        Write(_state, "agents/scout/memory/passes.yml", "daily: never\nweekly: never\n");

        Write(_ui, "sessions/s-ceo/session.md", "---\nsid: s-ceo\npane: w1:p9\nflow: ceo\ntask: ceo\nstep: \nupdated: 2026-09-25T08:00:00Z\n---\n");
        Write(_ui, "sessions/s1/session.md", "---\nsid: s1\npane: w1:p1\nflow: grill\ntask: T-ECS-1\nstep: round 1\nupdated: 2026-09-25T09:00:00Z\n---\n");
        Write(_ui, "setup/doctor.json",
            "{\n  \"at\": \"2026-09-25T10:00:00Z\",\n  \"root\": \"/f\",\n  \"steps\": [\n    {\"id\": \"git\", \"state\": \"done\", \"detail\": \"git 2.51\", \"fix\": \"\"},\n"
            + "    {\"id\": \"herdr\", \"state\": \"missing\", \"detail\": \"no herdr\", \"fix\": \"install herdr\"}\n  ]\n}\n");
    }

    [Fact]
    public void Board_rows_carry_request_and_priority_a_parent_without_one_is_P2_and_a_block_inherits()
    {
        Fixture();

        var rows = State.Tasks().ToDictionary(r => r.Id);

        Assert.Equal(["T-CF-1", "T-ECS-1", "T-ECS-1-01", "T-ECS-1-02", "T-ECS-2"], rows.Keys.Order(StringComparer.Ordinal));
        Assert.Equal(("R-20260925-1", "P1", "ecs"), (rows["T-ECS-1"].Request, rows["T-ECS-1"].Priority, rows["T-ECS-1"].Repo));
        Assert.Equal("P1", rows["T-ECS-1-01"].Priority);
        Assert.Equal("P3", rows["T-ECS-1-02"].Priority);
        Assert.Equal("P2", rows["T-CF-1"].Priority);
        Assert.Equal("", rows["T-ECS-2"].Request);
    }

    [Fact]
    public void A_task_not_live_is_read_from_the_archive_with_its_archived_blocks_and_progress()
    {
        Fixture();

        var task = State.Task("T-CF-2");

        Assert.NotNull(task);
        Assert.Equal("done", task.Task.Status);
        Assert.Equal("R-20260920-1", task.Request);
        Assert.Equal("P0", task.Priority);
        Assert.Equal(["T-CF-2-01"], task.Blocks.Select(b => b.Id));
        Assert.Equal("The archived progress.\n", task.Progress);
        Assert.Equal("P0", State.Task("T-CF-2-01")!.Priority);
    }

    [Fact]
    public void Requests_list_live_and_archived_newest_first_with_parents_and_the_best_priority()
    {
        Fixture();

        var list = State.Requests();

        Assert.Equal(["R-20260925-10", "R-20260925-2", "R-20260925-1", "R-20260920-1"], list.Select(r => r.Id));
        var r1 = list.Single(r => r.Id == "R-20260925-1");
        Assert.Equal(("grilling", "Invoices reach the ledger.", "P1", false), (r1.Status, r1.Destination, r1.Priority, r1.Archived));
        Assert.Equal(["T-CF-1", "T-ECS-1"], r1.Parents);
        var old = list.Single(r => r.Id == "R-20260920-1");
        Assert.True(old.Archived);
        Assert.Equal("done", old.Status);
        Assert.Equal(["T-CF-2"], old.Parents);
        Assert.Equal("P0", old.Priority);
        Assert.Equal("P2", list.Single(r => r.Id == "R-20260925-2").Priority);
    }

    [Fact]
    public void A_request_carries_its_map_tickets_frontier_and_parents_with_blocks_and_acceptance()
    {
        Fixture();

        var r = State.Request("R-20260925-1");

        Assert.NotNull(r);
        Assert.Equal("The order.", r.Fog);
        Assert.Equal([new MapLink("Which API", "01-which-api.md", "REST.")], r.Decisions);
        Assert.Equal([new MapLink("Access", "03-access.md", "Not ours.")], r.OutOfScope);
        Assert.Equal(["01", "02", "03", "04"], r.Tickets.Select(t => t.Nn));
        Assert.Equal(["02"], r.Frontier);
        var ecs = r.Parents.Single(p => p.Id == "T-ECS-1");
        Assert.Equal(("ecs", "P1", "in_progress", "feat: T-ECS-1", "`make test` passes."), (ecs.Repo, ecs.Priority, ecs.Status, ecs.Goal, ecs.Acceptance));
        Assert.Equal(["T-ECS-1-01", "T-ECS-1-02"], ecs.Blocks.Select(b => b.Id));
        Assert.Equal("The cursor test passes.", ecs.Blocks[0].Acceptance);
        Assert.Equal("", ecs.Blocks[1].Acceptance);
    }

    [Fact]
    public void An_archived_request_shows_its_archived_parent_and_blocks()
    {
        Fixture();

        var r = State.Request("R-20260920-1");

        Assert.NotNull(r);
        Assert.True(r.Archived);
        var p = Assert.Single(r.Parents);
        Assert.Equal("It was done.", p.Acceptance);
        Assert.Equal(["T-CF-2-01"], p.Blocks.Select(b => b.Id));
    }

    [Fact]
    public void An_unknown_or_malformed_request_is_null()
    {
        Fixture();

        Assert.Null(State.Request("R-20260101-1"));
        Assert.Null(State.Request("../requests"));
    }

    [Fact]
    public void The_org_counts_leases_per_role_in_file_order_then_uncapped_roles_and_lists_leads_and_the_ceo()
    {
        Fixture();

        var org = State.Org(Home);

        Assert.Equal(new SlotUse(1, 10), org.Capacity.Sessions);
        Assert.Equal([new RoleUse("repo-lead", 1, 3), new RoleUse("scout", 1, 8), new RoleUse("docs-architect", 1, null)], org.Capacity.Roles);
        Assert.Equal(4, org.Leases.Count);
        Assert.Contains(new Lease("scout", "sess-1.use-1", "sess-1", "", "102"), org.Leases);
        Assert.Equal([new Lead("T-ECS-1", "ecs", "R-20260925-1", "P1", "in_progress", "T-ECS-1-lead")], org.Leads);
        Assert.Equal(new CeoInfo("s-ceo", "w1:p9"), org.Ceo);
    }

    [Fact]
    public void Without_a_capacity_folder_or_a_ceo_the_org_is_empty()
    {
        Write(_state, "factory.yml", "ui: docker\n");

        var org = State.Org(Home);

        Assert.Equal(new SlotUse(0, null), org.Capacity.Sessions);
        Assert.Empty(org.Capacity.Roles);
        Assert.Empty(org.Leases);
        Assert.Empty(org.Leads);
        Assert.Null(org.Ceo);
    }

    [Fact]
    public void Setup_carries_the_doctor_steps_the_capacity_and_every_passes_file()
    {
        Fixture();

        var setup = State.Setup(Home);

        Assert.Equal([new DoctorStep("git", "done", "git 2.51", ""), new DoctorStep("herdr", "missing", "no herdr", "install herdr")], setup.Steps);
        Assert.Equal("2026-09-25T10:00:00Z", setup.DoctorAt);
        Assert.Equal(new SlotUse(1, 10), setup.Capacity.Sessions);
        Assert.Equal(
            [
                new PassInfo("global", "2026-09-25T06:00:00Z", "never"),
                new PassInfo("repo:ecs", "never", "2026-09-20T07:00:00Z"),
                new PassInfo("agent:scout", "never", "never"),
                new PassInfo("repo-agent:ecs/implementer", "2026-09-24T05:00:00Z", "never"),
            ],
            setup.Passes);
    }

    [Fact]
    public void Setup_without_a_state_or_a_doctor_file_is_empty_not_an_error()
    {
        var setup = new StateReader(Path.Combine(_state, "nowhere")).Setup(Home);

        Assert.Empty(setup.Steps);
        Assert.Equal("", setup.DoctorAt);
        Assert.Empty(setup.Passes);
        Assert.Equal(new SlotUse(0, null), setup.Capacity.Sessions);
    }

    void Parent(string id, string fields, string body = "") =>
        Write(_state, $"repos/cf/tasks/{id}-steps.md", $"---\nid: {id}\nrepo: cf\n{fields}---\n\n# Goal\nfeat: {id}\n{body}");

    [Fact]
    public void A_parent_row_carries_the_solve_steps_its_state_records_and_a_block_none()
    {
        Parent("T-CF-5", "status: in_progress\ntier: yellow\narchetype: feature\nrequest: R-20260925-5\nplan_hash: abc\nmr_url: null\n",
            "\n## Related issues\nnone\n");
        Parent("T-CF-5-01", "status: done\n");
        Parent("T-CF-5-02", "status: review\n");
        Write(_state, "repos/cf/plans/five-plan-ready.md", "---\ntask: T-CF-5\n---\n\n# Spec\n");
        Write(_state, "repos/cf/progress/T-CF-5.md", "# T-CF-5\n\n## Wave plan\n- wave 1: T-CF-5-01\n- wave 2: T-CF-5-02\n");
        Write(_state, "requests/R-20260925-5/map.md", "---\nrequest: R-20260925-5\n---\n\nStatus: planned\n\n## Destination\n\nFive.\n");
        Parent("T-CF-6", "status: draft\ntier: <green|yellow|red>\narchetype: <feature|bugfix|refactor|research|ops>\nrequest: R-20260925-6\n",
            "\n## Related issues\n<the related issues>\n");
        Write(_state, "requests/R-20260925-6/map.md", "---\nrequest: R-20260925-6\n---\n\nStatus: charting\n\n## Destination\n\nSix.\n");
        Parent("T-CF-7", "status: done\ntier: green\narchetype: bugfix\nmr_url: https://example.invalid/mr/7\n",
            "\n## Context\nFrom the plan `repos/cf/plans/seven-plan-ready.md`.\n\n## Related issues\nnone\n");
        Parent("T-CF-7-01", "status: done\n");
        Write(_state, "repos/cf/plans/seven-plan-ready.md", "---\nrepo: cf\n---\n\n# Spec\n");
        Write(_state, "repos/cf/progress/T-CF-7.md",
            "# T-CF-7\n\n## Wave plan\n- wave 1: T-CF-7-01\n\n## Evidence\ngreen\n\n## Duplication\nnone\n\n## Review\napproved\n");
        Parent("T-CF-8", "status: draft\ntier: red\narchetype: feature\n");
        Write(_state, "repos/cf/plans/eight-plan-ready.md", "---\ntask: T-CF-8\n---\n\n# Spec\n");
        Write(_state, "repos/cf/verdicts/eight.md", "---\nplan_hash: x\n---\n\n## plan-check\nok\n");

        var rows = State.Tasks().ToDictionary(r => r.Id);

        Assert.Equal(["3", "3b", "4", "5", "6", "8", "9", "10"], rows["T-CF-5"].Steps);
        Assert.Empty(rows["T-CF-5-01"].Steps);
        Assert.Empty(rows["T-CF-6"].Steps);
        Assert.Equal(["3", "4", "5", "6", "8", "9", "10", "11", "12", "13", "14", "15", "16"], rows["T-CF-7"].Steps);
        Assert.Equal(["4", "5"], rows["T-CF-8"].Steps);
        Assert.Equal(rows["T-CF-5"].Steps, State.Task("T-CF-5")!.Task.Steps);
    }

    public void Dispose()
    {
        Directory.Delete(_state, recursive: true);
        Directory.Delete(_ui, recursive: true);
    }
}
