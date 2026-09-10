using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Confluent.Kafka;
using Confluent.SchemaRegistry;
using Confluent.SchemaRegistry.Serdes;
using Darumen.Contracts.V1;
using Darumen.Modules.Intake;
using Darumen.Modules.Journal;
using Darumen.Shared.Api;
using Darumen.Shared.Messaging;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace Darumen.Tests;

/// <summary>Сквозной контур T0.11 против живых Postgres, Kafka и Schema Registry (make serve или сервисы CI).
/// Запуск: DARUMEN_KAFKA_TEST=1 dotnet test --filter KafkaIntegrationTests.</summary>
public sealed class KafkaIntegrationTests : IDisposable
{
    private static readonly bool Enabled = Environment.GetEnvironmentVariable("DARUMEN_KAFKA_TEST") == "1";
    private static readonly string Bootstrap = Environment.GetEnvironmentVariable("KAFKA_BOOTSTRAP") ?? "localhost:29092";
    private static readonly string Registry = Environment.GetEnvironmentVariable("SCHEMA_REGISTRY_URL") ?? "http://localhost:8081";
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(60);

    private readonly WebApplicationFactory<Program> _app = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
    {
        builder.UseSetting($"{MessagingOptions.Section}:Mode", MessagingOptions.KafkaMode);
        builder.UseSetting($"{MessagingOptions.Section}:BootstrapServers", Bootstrap);
        builder.UseSetting($"{MessagingOptions.Section}:SchemaRegistry", Registry);
        builder.UseSetting($"{MessagingOptions.Section}:ConsumerGroup", "darumen-api-test");
    });

    [KafkaFact]
    public async Task Decision_is_published_once_through_the_outbox_in_registry_wire_format()
    {
        var client = _app.CreateClient();
        client.DefaultRequestHeaders.Add("X-Actor", "doctor-kafka");
        client.DefaultRequestHeaders.Add("X-Role", "doctor");
        client.DefaultRequestHeaders.Add("Idempotency-Key", $"kafka-{Guid.NewGuid():N}");
        var request = new DecisionRequestDto("referral", "75.028B.381.10", JsonDocument.Parse("{\"moCode\":\"22GN\"}").RootElement, JsonDocument.Parse("{\"moCode\":\"028B\"}").RootElement, "ближе к дому");

        var first = await client.PostAsJsonAsync("/api/v1/journal/decisions", request);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        var created = (await first.Content.ReadFromJsonAsync<DecisionCreatedDto>())!;
        Assert.Equal(HttpStatusCode.OK, (await client.PostAsJsonAsync("/api/v1/journal/decisions", request)).StatusCode);

        using var registry = new CachedSchemaRegistryClient(new SchemaRegistryConfig { Url = Registry });
        var deserializer = new ProtobufDeserializer<DecisionRecorded>(registry, new ProtobufDeserializerConfig { UseDeprecatedFormat = false });
        using var consumer = new ConsumerBuilder<string, byte[]>(new ConsumerConfig
        {
            BootstrapServers = Bootstrap,
            GroupId = $"test-{Guid.NewGuid():N}",
            AutoOffsetReset = AutoOffsetReset.Earliest,
        }).Build();
        consumer.Subscribe(Topics.DecisionRecorded);
        var matches = new List<DecisionRecorded>();
        var stopwatch = Stopwatch.StartNew();
        var quietSince = (DateTime?)null;
        while (stopwatch.Elapsed < Timeout)
        {
            var result = consumer.Consume(TimeSpan.FromSeconds(1));
            if (result is null)
            {
                if (matches.Count > 0 && DateTime.UtcNow - (quietSince ??= DateTime.UtcNow) > TimeSpan.FromSeconds(5))
                {
                    break;
                }

                continue;
            }

            quietSince = null;
            var @event = await deserializer.DeserializeAsync(result.Message.Value, false, new SerializationContext(MessageComponentType.Value, Topics.DecisionRecorded));
            if (@event.DecisionId == created.DecisionId.ToString())
            {
                matches.Add(@event);
            }
        }

        var published = Assert.Single(matches);
        Assert.Equal("doctor", published.ActorRole);
        Assert.Equal("referral", published.Subject);
        Assert.Equal("{\"moCode\":\"028B\"}", published.Chosen);
        Assert.Equal(Events.Producer, published.Meta.Producer);
        Assert.Contains($"{Topics.DecisionRecorded}-value", await registry.GetAllSubjectsAsync());
    }

    [KafkaFact]
    public async Task Python_batch_loaded_event_is_consumed_into_intake_batches()
    {
        var client = _app.CreateClient();
        await Task.Delay(TimeSpan.FromSeconds(3)); // слушатель Wolverine подключается к группе
        var batchId = $"bg_referrals-test-{Guid.NewGuid():N}";
        var root = RepoRoot();
        var start = new ProcessStartInfo(Path.Combine(root, "ml", ".venv", "bin", "python"),
            $"-m darumen.intake.events emit --dataset bg_referrals --batch-id {batchId} --rows 10 --quarantined 1 --partitions region_kato=10/p_month=2025-01,region_kato=11/p_month=2025-01")
        {
            WorkingDirectory = root,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        start.Environment["KAFKA_BOOTSTRAP"] = Bootstrap;
        start.Environment["SCHEMA_REGISTRY_URL"] = Registry;
        using var process = Process.Start(start)!;
        var stderr = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();
        Assert.True(process.ExitCode == 0, stderr);

        var stopwatch = Stopwatch.StartNew();
        while (stopwatch.Elapsed < Timeout)
        {
            var page = await client.GetFromJsonAsync<Paged<BatchDto>>($"/api/v1/intake/batches?dataset=bg_referrals&size=200");
            var batch = page!.Items.FirstOrDefault(b => b.BatchId == batchId);
            if (batch is not null)
            {
                Assert.Equal(10, batch.RowsLoaded);
                Assert.Equal(1, batch.RowsQuarantined);
                Assert.Equal(2, batch.Partitions.Count);
                Assert.NotNull(batch.OccurredAt);
                return;
            }

            await Task.Delay(TimeSpan.FromSeconds(1));
        }

        Assert.Fail($"batch {batchId} did not arrive within {Timeout}");
    }

    public void Dispose() => _app.Dispose();

    private static string RepoRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !File.Exists(Path.Combine(directory.FullName, "Darumen.slnx")))
        {
            directory = directory.Parent;
        }

        return directory?.FullName ?? throw new InvalidOperationException("Darumen.slnx not found above " + AppContext.BaseDirectory);
    }

    public sealed class KafkaFactAttribute : FactAttribute
    {
        public KafkaFactAttribute()
        {
            if (!Enabled)
            {
                Skip = "set DARUMEN_KAFKA_TEST=1 with make serve running";
            }
        }
    }
}
