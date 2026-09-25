using Xunit;

public sealed class UiHomeTests : IDisposable
{
    readonly string _ui = Directory.CreateTempSubdirectory("ui-home-").FullName;

    string Session(string sid)
    {
        var dir = Path.Combine(_ui, "sessions", sid);
        Directory.CreateDirectory(dir);
        File.WriteAllText(Path.Combine(dir, "session.md"), $"---\nsid: {sid}\npane: w1:p9\nflow: ceo\ntask: ceo\nstep: \n---\n");
        return dir;
    }

    [Fact]
    public void An_empty_ask_is_a_free_message_written_as_the_next_answer_under_the_ask_id_msg()
    {
        var dir = Session("s-ceo");
        Directory.CreateDirectory(Path.Combine(dir, "answers"));
        File.WriteAllText(Path.Combine(dir, "answers", "4-q1.txt"), "Q1 A");

        var (status, file) = new UiHome(_ui).WriteAnswer("s-ceo", "", "start the daily pass for global");

        Assert.Equal(AnswerStatus.Written, status);
        Assert.Equal("5-msg.txt", file);
        Assert.Equal("start the daily pass for global", File.ReadAllText(Path.Combine(dir, "answers", "5-msg.txt")));
    }

    [Fact]
    public void A_free_message_to_an_unknown_session_is_unknown()
    {
        Assert.Equal(AnswerStatus.Unknown, new UiHome(_ui).WriteAnswer("nosuch", "", "start the daily pass for global").Status);
    }

    [Theory]
    [InlineData("")]
    [InlineData("  \n")]
    public void A_free_message_without_text_is_invalid(string text)
    {
        Session("s-ceo");

        Assert.Equal(AnswerStatus.Invalid, new UiHome(_ui).WriteAnswer("s-ceo", "", text).Status);
        Assert.False(Directory.Exists(Path.Combine(_ui, "sessions", "s-ceo", "answers")) && Directory.EnumerateFiles(Path.Combine(_ui, "sessions", "s-ceo", "answers")).Any());
    }

    [Fact]
    public void An_ask_keeps_its_own_task_and_one_without_a_task_takes_its_session_s()
    {
        var dir = Path.Combine(_ui, "sessions", "s6");
        Directory.CreateDirectory(Path.Combine(dir, "asks"));
        File.WriteAllText(Path.Combine(dir, "session.md"), "---\nsid: s6\npane: w1:p6\nflow: grill\ntask: T-001\nstep: round 1\n---\n");
        File.WriteAllText(Path.Combine(dir, "asks", "k1.md"), "---\nask: k1\ntask: T-002\nflow: grill\nstep: round 1\nstatus: open\n---\n\nThe first.\n");
        File.WriteAllText(Path.Combine(dir, "asks", "k2.md"), "---\nask: k2\nflow: grill\nstep: round 1\nstatus: open\n---\n\nThe second.\n");

        var asks = new UiHome(_ui).Sessions().Single(s => s.Sid == "s6").Asks.ToDictionary(a => a.Ask, a => a.Task);

        Assert.Equal("T-002", asks["k1"]);
        Assert.Equal("T-001", asks["k2"]);
    }

    [Fact]
    public void A_sent_ask_carries_its_last_answer_a_closed_one_keeps_it_and_an_unanswered_one_has_none()
    {
        var dir = Session("s7");
        var asks = Directory.CreateDirectory(Path.Combine(dir, "asks")).FullName;
        var answers = Directory.CreateDirectory(Path.Combine(dir, "answers")).FullName;
        var t = DateTime.UtcNow.AddMinutes(-10);
        void At(string path, string text, int minute)
        {
            File.WriteAllText(path, text);
            File.SetLastWriteTimeUtc(path, t.AddMinutes(minute));
        }
        At(Path.Combine(answers, "1-a1.txt"), "Q1 A", 0);
        At(Path.Combine(asks, "a1.md"), "---\nask: a1\nstatus: open\n---\n\nRewritten.\n", 1);
        At(Path.Combine(answers, "2-a1.txt"), "Q1 B\nQ2 more", 2);
        At(Path.Combine(answers, "3-a1.txt"), "Q1 more", 3);
        At(Path.Combine(answers, "4-a2.txt"), "Q1 A", 0);
        At(Path.Combine(asks, "a2.md"), "---\nask: a2\nstatus: answered\n---\n\nClosed.\n", 1);
        At(Path.Combine(asks, "a3.md"), "---\nask: a3\nstatus: open\n---\n\nOpen.\n", 1);
        At(Path.Combine(answers, "5-a4.txt"), "Q1 A", 0);
        At(Path.Combine(asks, "a4.md"), "---\nask: a4\nstatus: open\n---\n\nRedrawn.\n", 1);

        var got = new UiHome(_ui).Sessions().Single(s => s.Sid == "s7").Asks.ToDictionary(a => a.Ask, a => a.Answer);

        Assert.Equal("Q1 B\nQ2 more", got["a1"]);
        Assert.Equal("Q1 A", got["a2"]);
        Assert.Null(got["a3"]);
        Assert.Null(got["a4"]);
    }

    [Fact]
    public void Frontmatter_is_cached_by_path_and_mtime_and_read_anew_once_the_mtime_moves()
    {
        var path = Path.Combine(_ui, "cached.md");
        File.WriteAllText(path, "---\nstatus: open\n---\n");
        var stamp = File.GetLastWriteTimeUtc(path);
        Assert.Equal("open", Frontmatter.Read(path)["status"]);

        File.WriteAllText(path, "---\nstatus: shut\n---\n");
        File.SetLastWriteTimeUtc(path, stamp);
        Assert.Equal("open", Frontmatter.Read(path)["status"]);

        File.SetLastWriteTimeUtc(path, stamp.AddSeconds(1));
        Assert.Equal("shut", Frontmatter.Read(path)["status"]);
    }

    public void Dispose() => Directory.Delete(_ui, recursive: true);
}
