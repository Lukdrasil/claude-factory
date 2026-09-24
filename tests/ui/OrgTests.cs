using Xunit;

public sealed class OrgTests
{
    [Fact]
    public void Caps_read_sessions_and_the_flow_spelling_of_roles_in_file_order()
    {
        var caps = Capacity.Caps("""
            ui: docker
            capacity:
              sessions: 10
              roles: {repo-lead: 3, scout: 8, implementer: 4}   # a comment
            spawn: herdr
            other: 5
            """);

        Assert.Equal([("sessions", 10), ("repo-lead", 3), ("scout", 8), ("implementer", 4)], caps);
    }

    [Fact]
    public void Caps_read_the_block_spelling_of_roles()
    {
        var caps = Capacity.Caps("capacity:\n  roles:\n    researcher: 4\n    code-reviewer: 2\n  sessions: 6\n");

        Assert.Equal([("researcher", 4), ("code-reviewer", 2), ("sessions", 6)], caps);
    }

    [Fact]
    public void No_capacity_block_means_no_caps()
    {
        Assert.Empty(Capacity.Caps("ui: docker\nui_port: 7777\n"));
    }

    [Fact]
    public void A_lease_reads_its_session_unit_and_at_and_takes_role_and_key_from_its_path()
    {
        var lease = Capacity.ParseLease("repo-lead", "T-ECS-1", "role=repo-lead\nsession=\nunit=T-ECS-1-lead\nat=1790000000\n");

        Assert.Equal(new Lease("repo-lead", "T-ECS-1", "", "T-ECS-1-lead", "1790000000"), lease);
    }

    [Fact]
    public void A_subagent_lease_carries_its_session()
    {
        var lease = Capacity.ParseLease("scout", "agent-1", "role=scout\nsession=sess-1\nunit=\nat=17\n");

        Assert.Equal("sess-1", lease.Session);
        Assert.Equal("", lease.Unit);
    }

    [Fact]
    public void Passes_read_both_stamps_and_never_when_a_line_is_missing()
    {
        Assert.Equal(new PassInfo("global", "2026-09-25T06:00:00Z", "never"), Passes.Parse("global", "daily: 2026-09-25T06:00:00Z\nweekly: never\n"));
        Assert.Equal(new PassInfo("repo:ecs", "never", "2026-09-20T07:00:00Z"), Passes.Parse("repo:ecs", "weekly: 2026-09-20T07:00:00Z\n"));
    }

    [Theory]
    [InlineData("memory/global/passes.yml", "global")]
    [InlineData("repos/ecs/memory/passes.yml", "repo:ecs")]
    [InlineData("agents/scout/memory/passes.yml", "agent:scout")]
    [InlineData("repos/ecs/agents/implementer/passes.yml", "repo-agent:ecs/implementer")]
    [InlineData("repos/ecs/passes.yml", null)]
    [InlineData("memory/passes.yml", null)]
    public void A_passes_file_is_scoped_by_its_path(string path, string? scope)
    {
        Assert.Equal(scope, Passes.ScopeOf(path));
    }
}
