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
