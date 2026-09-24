using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Channels;
using Microsoft.AspNetCore.Mvc;

var builder = WebApplication.CreateSlimBuilder(args);
builder.Services.ConfigureHttpJsonOptions(o => o.SerializerOptions.TypeInfoResolverChain.Insert(0, UiJson.Default));
builder.Services.AddSingleton(new StateReader("/state"));
builder.Services.AddSingleton(new UiHome("/ui"));
builder.Services.AddSingleton<MountScanner[]>(
    [new MountScanner("/state", TimeSpan.FromMilliseconds(250)), new MountScanner("/ui", TimeSpan.FromMilliseconds(250))]);

var app = builder.Build();
app.Use(Api.RequireLocalHost);
app.Use(Api.RequireToken);
app.Use(Api.PagePolicy);
app.UseDefaultFiles();
app.UseStaticFiles();
app.MapGet("/api/stream", (HttpContext ctx, [FromServices] MountScanner[] scanners, CancellationToken ct) => Api.Stream(ctx, scanners, ct));
app.MapGet("/api/board", (StateReader state) => Api.Board(state));
app.MapGet("/api/tasks/{id}", (string id, StateReader state) => Api.TaskDetail(id, state));
app.MapGet("/api/sessions", (UiHome home) => Results.Ok(home.Sessions()));
app.MapGet("/api/setup", (StateReader state, UiHome home) => Api.Setup(state, home));
app.MapGet("/api/requests", (StateReader state) => Results.Ok(state.Requests()));
app.MapGet("/api/requests/{id}", (string id, StateReader state) => Api.RequestDetail(id, state));
app.MapGet("/api/org", (StateReader state, UiHome home) => Results.Ok(state.Org(home)));
app.MapPost("/api/answers/{sid}", (string sid, AnswerRequest req, UiHome home) => Api.PostAnswer(sid, req, home));
app.MapGet("/visual", (HttpContext ctx, UiHome home) => Api.Visual(ctx, home));
app.Run();

/// <summary>The page's composed shorthand for one ask, exactly as the relay will type it.</summary>
public sealed record AnswerRequest(string Ask, string Text);

public sealed record AnswerWritten(string File);

static class Api
{
    public static async Task Stream(HttpContext ctx, MountScanner[] scanners, CancellationToken ct)
    {
        ctx.Response.ContentType = "text/event-stream";
        ctx.Response.Headers.CacheControl = "no-cache";
        await ctx.Response.StartAsync(ct);
        await ctx.Response.Body.FlushAsync(ct);
        var changes = Channel.CreateUnbounded<string>();
        var pumps = Task.WhenAll(scanners.Select(scanner => Pump(scanner, changes.Writer, ct)));
        try
        {
            await foreach (var path in changes.Reader.ReadAllAsync(ct))
            {
                await ctx.Response.WriteAsync($"data: {path}\n\n", ct);
                await ctx.Response.Body.FlushAsync(ct);
            }
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
        }
        await pumps;
    }

    static async Task Pump(MountScanner scanner, ChannelWriter<string> changes, CancellationToken ct)
    {
        try
        {
            await foreach (var path in scanner.ChangesAsync(ct))
            {
                await changes.WriteAsync(path, ct);
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

    public static IResult RequestDetail(string id, StateReader state) =>
        state.Request(id) is { } request ? Results.Ok(request) : Results.NotFound();

    public static IResult PostAnswer(string sid, AnswerRequest req, UiHome home) =>
        home.WriteAnswer(sid, req.Ask, req.Text) switch
        {
            (AnswerStatus.Written, var file) => Results.Created($"/api/answers/{sid}/{file}", new AnswerWritten(file!)),
            (AnswerStatus.Unknown, _) => Results.NotFound(),
            (AnswerStatus.NotOpen, _) => Results.Conflict(),
            _ => Results.BadRequest(),
        };

    /// <summary>
    /// The visual of one session, with the token as the query parameter <c>token</c>: 401 before anything else,
    /// 400 for a sid outside <c>[A-Za-z0-9-]+</c>, 404 without <c>visual.html</c>.
    /// </summary>
    public static IResult Visual(HttpContext ctx, UiHome home)
    {
        ctx.Response.Headers.ContentSecurityPolicy =
            "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:";
        ctx.Response.Headers.CacheControl = "no-store";
        if (!Authorized(home, ctx.Request.Query["token"].ToString()))
        {
            return Results.Unauthorized();
        }
        var sid = ctx.Request.Query["sid"].ToString();
        if (!UiHome.IsId(sid))
        {
            return Results.BadRequest();
        }
        return home.VisualFile(sid) is { } file ? Results.File(file, "text/html; charset=utf-8") : Results.NotFound();
    }

    /// <summary>403 for any Host other than 127.0.0.1 or localhost on the port in <c>/ui/port</c>, read per request.</summary>
    public static Task RequireLocalHost(HttpContext ctx, RequestDelegate next)
    {
        var host = ctx.Request.Host;
        if (host.Host is not ("127.0.0.1" or "localhost") || host.Port is null
            || host.Port != ctx.RequestServices.GetRequiredService<UiHome>().Port())
        {
            ctx.Response.StatusCode = StatusCodes.Status403Forbidden;
            return Task.CompletedTask;
        }
        return next(ctx);
    }

    /// <summary>The page's own origin for everything and data images besides; <c>/visual</c> sets its own policy.</summary>
    public static Task PagePolicy(HttpContext ctx, RequestDelegate next)
    {
        ctx.Response.Headers.ContentSecurityPolicy = "default-src 'self'; img-src 'self' data:";
        return next(ctx);
    }

    public static Task RequireToken(HttpContext ctx, RequestDelegate next)
    {
        if (!ctx.Request.Path.StartsWithSegments("/api"))
        {
            return next(ctx);
        }
        if (!Authorized(ctx.RequestServices.GetRequiredService<UiHome>(), ctx.Request.Headers["X-Factory-Token"].ToString()))
        {
            ctx.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return Task.CompletedTask;
        }
        return next(ctx);
    }

    static bool Authorized(UiHome home, string given) =>
        home.Token() is { Length: > 0 } token
        && CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(given), Encoding.UTF8.GetBytes(token));
}

[JsonSerializable(typeof(AnswerRequest))]
[JsonSerializable(typeof(AnswerWritten))]
[JsonSerializable(typeof(List<TaskRow>))]
[JsonSerializable(typeof(TaskDetail))]
[JsonSerializable(typeof(SetupInfo))]
[JsonSerializable(typeof(List<SessionInfo>))]
[JsonSerializable(typeof(List<RequestRow>))]
[JsonSerializable(typeof(RequestDetail))]
[JsonSerializable(typeof(OrgInfo))]
[JsonSerializable(typeof(DoctorFile))]
[JsonSourceGenerationOptions(JsonSerializerDefaults.Web)]
partial class UiJson : JsonSerializerContext;
