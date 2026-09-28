using System.Net;
using System.Text.Json;
using Darumen.Modules.Access;
using Darumen.Modules.Access.Status;
using Darumen.Tests.Fakes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Tests.Access;

/// <summary>GET /public/service-status — контракт для веба и мобилки: анонимно, причины недоступности по конфигурации
/// и по пробе SMTP; проба не валит ответ и кэшируется.</summary>
public sealed class ServiceStatusTests
{
    private const string Url = "/api/v1/public/service-status";

    [Fact]
    public async Task Status_is_anonymous_and_reports_every_channel_as_unavailable_by_default()
    {
        using var app = new TestApp();
        using var host = app.WithWebHostBuilder(b => b.UseSetting("Mail:Smtp:Host", ""));
        using var response = await host.CreateClient().GetAsync(Url);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
        var root = json.RootElement;
        Assert.Matches(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", root.GetProperty("checkedAt").GetString());
        AssertChannel(root, "email", false, "smtp_not_configured");
        AssertChannel(root, "push", false, "not_ready");
        AssertChannel(root, "sms", false, "not_ready");
        AssertChannel(root, "egov", false, "endpoint_not_provided");
        Assert.Equal(0, app.SmtpProbe.Calls); // без хоста пробовать нечего
    }

    [Fact]
    public async Task Unreachable_smtp_is_reported_as_smtp_unreachable()
    {
        using var app = new TestApp();
        app.SmtpProbe.Reachable = false;
        var root = await StatusAsync(app.WithWebHostBuilder(b => b.UseSetting("Mail:Smtp:Host", " smtp.example.test ").UseSetting("Mail:Smtp:Port", "587")));
        AssertChannel(root, "email", false, "smtp_unreachable");
        Assert.Equal(("smtp.example.test", 587), app.SmtpProbe.Last);
    }

    [Fact]
    public async Task Failing_probe_never_turns_into_a_server_error()
    {
        using var app = new TestApp();
        app.SmtpProbe.Throws = true;
        var root = await StatusAsync(app.WithWebHostBuilder(b => b.UseSetting("Mail:Smtp:Host", "smtp.example.test")));
        AssertChannel(root, "email", false, "smtp_unreachable");
    }

    [Fact]
    public async Task Reachable_smtp_is_available_with_a_null_reason()
    {
        using var app = new TestApp();
        var root = await StatusAsync(app.WithWebHostBuilder(b => b.UseSetting("Mail:Smtp:Host", "smtp.example.test")));
        AssertChannel(root, "email", true, null);
    }

    [Fact]
    public async Task Ready_flags_and_egov_endpoint_make_channels_available()
    {
        using var app = new TestApp();
        var root = await StatusAsync(app.WithWebHostBuilder(b => b
            .UseSetting("Services:Push:Ready", "true")
            .UseSetting("Services:Sms:Ready", "true")
            .UseSetting("Services:Egov:Endpoint", "https://smartbridge.example.kz/egov-mobile")));
        AssertChannel(root, "push", true, null);
        AssertChannel(root, "sms", true, null);
        AssertChannel(root, "egov", true, null);
    }

    [Fact]
    public async Task Repeated_requests_do_not_probe_the_mail_server_again()
    {
        using var app = new TestApp();
        using var host = app.WithWebHostBuilder(b => b.UseSetting("Mail:Smtp:Host", "smtp.example.test"));
        var client = host.CreateClient();
        for (var i = 0; i < 3; i++)
        {
            Assert.Equal(HttpStatusCode.OK, (await client.GetAsync(Url)).StatusCode);
        }

        Assert.Equal(1, app.SmtpProbe.Calls);
    }

    [Fact]
    public async Task Mail_status_caches_the_probe_and_logs_only_state_changes_without_credentials()
    {
        var probe = new FakeSmtpProbe { Reachable = false };
        var clock = new ManualClock();
        var logger = new ListLogger<MailServerStatus>();
        var options = Options.Create(new MailOptions { Host = "smtp.example.test", Port = 587, User = "smtp-user", Password = "smtp-secret" });
        var status = new MailServerStatus(options, probe, clock, logger);

        var results = await Task.WhenAll(Enumerable.Range(0, 8).Select(_ => status.CheckAsync()));
        Assert.All(results, r => Assert.Equal(ServiceStatusReasons.SmtpUnreachable, r.Reason));
        Assert.Equal(1, probe.Calls); // одновременные запросы ждут одну пробу

        clock.Advance(MailServerStatus.CacheFor + TimeSpan.FromSeconds(1));
        Assert.False((await status.CheckAsync()).Available);
        Assert.Equal(2, probe.Calls);
        Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning); // состояние не менялось — второго Warning нет

        probe.Reachable = true;
        clock.Advance(MailServerStatus.CacheFor + TimeSpan.FromSeconds(1));
        Assert.True((await status.CheckAsync()).Available);
        Assert.Single(logger.Entries, e => e.Level == LogLevel.Warning);
        Assert.Single(logger.Entries, e => e.Level == LogLevel.Information);
        Assert.DoesNotContain(logger.Entries, e => e.Message.Contains("smtp-user") || e.Message.Contains("smtp-secret"));
    }

    private static async Task<JsonElement> StatusAsync(WebApplicationFactory<Program> host)
    {
        using (host)
        {
            using var response = await host.CreateClient().GetAsync(Url);
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            return json.RootElement.Clone();
        }
    }

    private static void AssertChannel(JsonElement root, string name, bool available, string? reason)
    {
        var channel = root.GetProperty(name);
        Assert.Equal(available, channel.GetProperty("available").GetBoolean());
        var actual = channel.GetProperty("reason"); // поле есть всегда, при available: true — null
        Assert.Equal(reason, actual.ValueKind == JsonValueKind.Null ? null : actual.GetString());
    }

    private sealed class ManualClock : TimeProvider
    {
        private DateTimeOffset _now = new(2026, 9, 28, 10, 15, 0, TimeSpan.Zero);

        public override DateTimeOffset GetUtcNow() => _now;

        public void Advance(TimeSpan by) => _now += by;
    }

    private sealed class ListLogger<T> : ILogger<T>
    {
        private readonly List<(LogLevel Level, string Message)> _entries = [];

        public IReadOnlyList<(LogLevel Level, string Message)> Entries
        {
            get
            {
                lock (_entries)
                {
                    return [.. _entries];
                }
            }
        }

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            lock (_entries)
            {
                _entries.Add((logLevel, formatter(state, exception)));
            }
        }
    }
}
