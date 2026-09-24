using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

var builder = WebApplication.CreateSlimBuilder(args);
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.TypeInfoResolverChain.Insert(0, UiJson.Default));
builder.Services.AddSingleton(new StateReader("/state"));
builder.Services.AddSingleton(new UiHome("/ui"));
builder.Services.AddSingleton(new MountScanner("/state", TimeSpan.FromMilliseconds(250)));

var app = builder.Build();
app.Use(Api.RequireToken);
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapGet("/api/stream", (HttpContext ctx, MountScanner scanner, CancellationToken ct) => Api.Stream(ctx, scanner, ct));
app.MapGet("/api/board", (StateReader state) => Api.Board(state));
app.MapGet("/api/tasks/{id}", (string id, StateReader state) => Api.TaskDetail(id, state));
app.MapGet("/api/setup", (StateReader state, UiHome home) => Api.Setup(state, home));
app.MapPost("/api/answers/{sid}", (string sid, AnswerRequest req, UiHome home) => Api.PostAnswer(sid, req, home));
app.Run();

/// <summary>The page's composed shorthand for one ask, exactly as the relay will type it.</summary>
public sealed record AnswerRequest(string Ask, string Text);

public sealed record AnswerWritten(string File);

static class Api
{
    public static async Task Stream(HttpContext ctx, MountScanner scanner, CancellationToken ct)
    {
        ctx.Response.ContentType = "text/event-stream";
        ctx.Response.Headers.CacheControl = "no-cache";
        await ctx.Response.StartAsync(ct);
        await ctx.Response.Body.FlushAsync(ct);
        try
        {
            await foreach (var path in scanner.ChangesAsync(ct))
            {
                await ctx.Response.WriteAsync($"data: {path}\n\n", ct);
                await ctx.Response.Body.FlushAsync(ct);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
        }
    }

    public static IResult Board(StateReader state) => Results.Ok(state.Tasks());

    public static IResult TaskDetail(string id, StateReader state) =>
        state.Task(id) is { } task ? Results.Ok(task) : Results.NotFound();

    public static IResult Setup(StateReader state, UiHome home) => Results.Ok(state.Setup(home));

    public static IResult PostAnswer(string sid, AnswerRequest req, UiHome home) =>
        home.WriteAnswer(sid, req.Ask, req.Text) switch
        {
            (AnswerStatus.Written, var file) => Results.Created($"/api/answers/{sid}/{file}", new AnswerWritten(file!)),
            (AnswerStatus.Unknown, _) => Results.NotFound(),
            (AnswerStatus.NotOpen, _) => Results.Conflict(),
            _ => Results.BadRequest(),
        };

    public static Task RequireToken(HttpContext ctx, RequestDelegate next)
    {
        if (!ctx.Request.Path.StartsWithSegments("/api"))
        {
            return next(ctx);
        }
        var token = ctx.RequestServices.GetRequiredService<UiHome>().Token();
        var given = ctx.Request.Headers["X-Factory-Token"].ToString();
        if (string.IsNullOrEmpty(token)
            || !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(given), Encoding.UTF8.GetBytes(token)))
        {
            ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return Task.CompletedTask;
        }
        return next(ctx);
    }
}

[JsonSerializable(typeof(AnswerRequest))]
[JsonSerializable(typeof(AnswerWritten))]
[JsonSerializable(typeof(List<TaskRow>))]
[JsonSerializable(typeof(TaskDetail))]
[JsonSerializable(typeof(SetupInfo))]
[JsonSourceGenerationOptions(JsonSerializerDefaults.Web)]
partial class UiJson : JsonSerializerContext;
