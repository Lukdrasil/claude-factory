using System.Runtime.Versioning;
using Xunit;

[SupportedOSPlatform("linux")]
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

    const string Round = "❓ **Q1** - **Which store?**: where the rows live.\n  **A** SQLite\n  **B** Postgres\n\n➡️ **B**: one server.\n\n---\n\n"
        + "❓ **Q2** - **Which port?**: the port.\n  **A** 7171\n  **B** a random one\n\n➡️ **A**: one URL.\n";

    string Ask(string sid, string ask, string flow, string body, string pane = "w1:p2")
    {
        var dir = Path.Combine(_ui, "sessions", sid);
        Directory.CreateDirectory(Path.Combine(dir, "asks"));
        File.WriteAllText(Path.Combine(dir, "session.md"), $"---\nsid: {sid}\npane: {pane}\nflow: {flow}\ntask: T-001\nstep: x\n---\n");
        File.WriteAllText(Path.Combine(dir, "asks", ask + ".md"), $"---\nask: {ask}\ntask: T-001\nflow: {flow}\nstep: x\nstatus: open\n---\n\n{body}");
        return dir;
    }

    string[] Answers(string sid) => Directory.Exists(Path.Combine(_ui, "sessions", sid, "answers"))
        ? Directory.EnumerateFiles(Path.Combine(_ui, "sessions", sid, "answers")).Select(Path.GetFileName).Order().ToArray()!
        : [];

    [Fact]
    public void Auto_answer_is_off_until_switched_on_and_writes_nothing_while_off()
    {
        Ask("s1", "r1", "grill", Round);
        var home = new UiHome(_ui);

        Assert.False(home.AutoAnswer());
        Assert.Empty(home.AutoAnswerPass());
        Assert.Empty(Answers("s1"));
        home.SetAutoAnswer(true);
        Assert.True(home.AutoAnswer());
        home.SetAutoAnswer(false);
        Assert.False(home.AutoAnswer());
    }

    [Fact]
    public void Mute_sound_is_off_until_switched_on_and_is_the_file_notify_reads()
    {
        var home = new UiHome(_ui);

        Assert.False(home.MuteSound());
        home.SetMuteSound(true);
        Assert.True(File.Exists(Path.Combine(_ui, "mute-sound")));
        home.SetMuteSound(false);
        Assert.False(home.MuteSound());
    }

    [Fact]
    public void Auto_answer_sends_the_recommended_option_of_every_question_of_an_open_round_once()
    {
        var dir = Ask("s1", "r1", "grill", Round);
        var home = new UiHome(_ui);
        home.SetAutoAnswer(true);

        Assert.Equal(["s1/r1"], home.AutoAnswerPass());
        Assert.Equal("Q1 B\nQ2 A", File.ReadAllText(Path.Combine(dir, "answers", "1-r1.txt")));
        Assert.Empty(home.AutoAnswerPass());
        Assert.Equal(["1-r1.txt"], Answers("s1"));
    }

    [Theory]
    [InlineData("grill", "❓ **Q1** - **Approve T-001?**: the cut is checked.\n  **A** yes\n  **B** no\n\n➡️ **A**: it passed.\n", "a confirm")]
    [InlineData("doctor", "# Doctor\n\nDocker is running.\n", "a notice")]
    [InlineData("grill", "❓ **Q1** - **Which store?**: where.\n  **A** SQLite\n  **B** Postgres\n\n➡️ **B**: one server.\n\n---\n\n❓ **Q2** - **Which name?**: one per machine.\n\n➡️ claude-factory-ui.\n", "a question without a recommended option")]
    [InlineData("approve", Round, "the approve flow")]
    [InlineData("done", Round, "the done flow")]
    [InlineData("add-repo", Round, "the add-repo flow")]
    public void Auto_answer_leaves_to_the_human(string flow, string body, string what)
    {
        Ask("s1", "r1", flow, body);
        var home = new UiHome(_ui);
        home.SetAutoAnswer(true);

        Assert.True(home.AutoAnswerPass().Count == 0, what);
        Assert.Empty(Answers("s1"));
    }

    [Fact]
    public void An_open_ask_of_an_ended_session_reads_answered_once_a_later_session_asked_it_again()
    {
        var old = Ask("s1", "r1", "herd", Round);
        File.WriteAllText(Path.Combine(old, "agent"), "gone\n");
        File.SetLastWriteTimeUtc(Path.Combine(old, "asks", "r1.md"), DateTime.UtcNow.AddMinutes(-10));
        var lone = Ask("s3", "r3", "herd", Round);
        File.WriteAllText(Path.Combine(lone, "agent"), "gone\n");
        Ask("s2", "r1", "herd", Round);

        var asks = new UiHome(_ui).Sessions().ToDictionary(s => s.Sid, s => s.Asks.Single().Status);

        Assert.Equal("answered", asks["s1"]);
        Assert.Equal("open", asks["s2"]);
        Assert.Equal("open", asks["s3"]);
    }

    [Fact]
    public void Auto_answer_leaves_a_permission_dialog_to_the_human()
    {
        Ask("s1", "dialog-t-001-triage-1", "solve", "❓ **Q1** - **Allow the command?**\n  **A** allow\n  **B** deny\n\n➡️ **A**: read-only.\n");
        var home = new UiHome(_ui);
        home.SetAutoAnswer(true);

        Assert.Empty(home.AutoAnswerPass());
        Assert.Empty(Answers("s1"));
    }

    [Fact]
    public void Auto_answer_leaves_a_session_outside_herdr_and_one_whose_agent_is_gone()
    {
        Ask("s1", "r1", "grill", Round, pane: "");
        var gone = Ask("s2", "r2", "grill", Round);
        File.WriteAllText(Path.Combine(gone, "agent"), "gone\n");
        var home = new UiHome(_ui);
        home.SetAutoAnswer(true);

        Assert.Empty(home.AutoAnswerPass());
        Assert.Empty(Answers("s1"));
        Assert.Empty(Answers("s2"));
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

    void AddRepo(string name, string json)
    {
        var dir = Directory.CreateDirectory(Path.Combine(_ui, "setup", "add-repo")).FullName;
        File.WriteAllText(Path.Combine(dir, name), json);
    }

    [Fact]
    public void Add_repo_files_read_every_field_newest_first()
    {
        AddRepo("old.json", "{\"at\":\"2026-09-24T09:00:00Z\",\"key\":\"old\",\"url\":\"https://example.test/g/old.git\",\"path\":\"/c/old\",\"state\":\"failed\",\"detail\":\"cannot reach https://example.test/g/old.git: 404\"}");
        AddRepo("demo.json", "{\"at\":\"2026-09-25T10:00:00Z\",\"key\":\"demo\",\"url\":\"https://example.test/g/demo.git\",\"path\":\"/c/demo\",\"state\":\"cloning\",\"detail\":\"/c/demo\"}\n");
        AddRepo("mid.json", "{\"key\":\"mid\",\"state\":\"pending\",\"at\":\"2026-09-25T08:00:00Z\",\"detail\":\"/c/mid\",\"path\":\"/c/mid\",\"url\":\"ssh://git@example.test/g/mid.git\"}");

        Assert.Equal(
            [
                new AddRepoInfo("demo", "https://example.test/g/demo.git", "/c/demo", "cloning", "/c/demo", "2026-09-25T10:00:00Z"),
                new AddRepoInfo("mid", "ssh://git@example.test/g/mid.git", "/c/mid", "pending", "/c/mid", "2026-09-25T08:00:00Z"),
                new AddRepoInfo("old", "https://example.test/g/old.git", "/c/old", "failed", "cannot reach https://example.test/g/old.git: 404", "2026-09-24T09:00:00Z"),
            ],
            new UiHome(_ui).AddRepos());
    }

    [Fact]
    public void An_add_repo_file_with_missing_fields_reads_them_as_empty_strings()
    {
        AddRepo("demo.json", "{\"key\":\"demo\",\"state\":\"pending\"}");

        Assert.Equal([new AddRepoInfo("demo", "", "", "pending", "", "")], new UiHome(_ui).AddRepos());
    }

    [Fact]
    public void An_unreadable_or_broken_add_repo_file_a_temp_file_and_another_extension_are_skipped()
    {
        AddRepo("good.json", "{\"at\":\"2026-09-25T10:00:00Z\",\"key\":\"good\",\"url\":\"u\",\"path\":\"p\",\"state\":\"registered\",\"detail\":\"\"}");
        AddRepo("locked.json", "{\"key\":\"locked\",\"state\":\"pending\"}");
        File.SetUnixFileMode(Path.Combine(_ui, "setup", "add-repo", "locked.json"), UnixFileMode.None);
        AddRepo("broken.json", "{\"key\":\"broken\",");
        AddRepo("number.json", "{\"key\":5}");
        AddRepo("null.json", "null");
        AddRepo(".half.json", "{\"key\":\"half\",\"state\":\"cloning\"}");
        AddRepo("notes.txt", "{\"key\":\"notes\",\"state\":\"cloning\"}");

        Assert.Equal(["good"], new UiHome(_ui).AddRepos().Select(a => a.Key));
    }

    [Fact]
    public void Without_an_add_repo_folder_the_list_is_empty()
    {
        Assert.Empty(new UiHome(_ui).AddRepos());
    }

    public void Dispose()
    {
        foreach (var file in Directory.EnumerateFiles(_ui, "*", SearchOption.AllDirectories))
        {
            File.SetUnixFileMode(file, UnixFileMode.UserRead | UnixFileMode.UserWrite);
        }
        Directory.Delete(_ui, recursive: true);
    }
}
