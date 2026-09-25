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
