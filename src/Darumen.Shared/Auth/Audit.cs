using System.Diagnostics;
using System.Threading.Channels;
using Dapper;
using Darumen.Shared.Api;
using Darumen.Shared.Data;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Darumen.Shared.Auth;

public sealed record AuditEntry(DateTime At, string Actor, string Role, string Method, string Path, string? Query, int Status, int DurationMs, string TraceId);

/// <summary>Очередь записей аудита: middleware кладёт, фоновый писатель сбрасывает пачками в journal.audit.</summary>
public sealed class AuditQueue
{
    public const int Capacity = 10_000;

    private readonly Channel<AuditEntry> _channel = Channel.CreateBounded<AuditEntry>(new BoundedChannelOptions(Capacity) { FullMode = BoundedChannelFullMode.DropOldest });

    public ChannelReader<AuditEntry> Reader => _channel.Reader;

    public bool TryEnqueue(AuditEntry entry) => _channel.Writer.TryWrite(entry);
}

public sealed class AuditMiddleware(RequestDelegate next, AuditQueue queue)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            await next(context);
        }
        finally
        {
            var user = CurrentUser.From(context);
            if (Roles.Audited.Contains(user.Role))
            {
                queue.TryEnqueue(new AuditEntry(DateTime.UtcNow, user.Actor, user.Role, context.Request.Method, context.Request.Path.Value ?? string.Empty,
                    context.Request.QueryString.HasValue ? context.Request.QueryString.Value : null, context.Response.StatusCode,
                    (int)stopwatch.ElapsedMilliseconds, Activity.Current?.TraceId.ToString() ?? context.TraceIdentifier));
            }
        }
    }
}

public sealed class AuditWriter(AuditQueue queue, IDbConnectionFactory db, ILogger<AuditWriter> logger) : BackgroundService
{
    public const int BatchSize = 200;
    private static readonly TimeSpan FlushEvery = TimeSpan.FromSeconds(2);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var batch = new List<AuditEntry>(BatchSize);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var window = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
                window.CancelAfter(FlushEvery);
                while (batch.Count < BatchSize && await queue.Reader.WaitToReadAsync(window.Token))
                {
                    while (batch.Count < BatchSize && queue.Reader.TryRead(out var entry))
                    {
                        batch.Add(entry);
                    }
                }
            }
            catch (OperationCanceledException) when (!stoppingToken.IsCancellationRequested)
            {
                // окно сброса истекло
            }

            if (batch.Count > 0)
            {
                await FlushAsync(batch, stoppingToken);
                batch.Clear();
            }
        }
    }

    private async Task FlushAsync(List<AuditEntry> batch, CancellationToken cancellationToken)
    {
        try
        {
            await using var connection = await db.OpenAsync(cancellationToken);
            await connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO journal.audit (at, actor, role, method, path, query, status, duration_ms, trace_id)
                VALUES (@At, @Actor, @Role, @Method, @Path, @Query, @Status, @DurationMs, @TraceId)
                """,
                batch, cancellationToken: cancellationToken));
        }
        catch (Exception exception) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning(exception, "Audit batch of {Count} entries was not written", batch.Count);
        }
    }
}
