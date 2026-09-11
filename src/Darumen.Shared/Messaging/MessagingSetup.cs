using Confluent.SchemaRegistry;
using Darumen.Contracts.V1;
using Darumen.Shared.Data;
using JasperFx.Resources;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Wolverine;
using Wolverine.EntityFrameworkCore;
using Wolverine.ErrorHandling;
using Wolverine.Kafka;
using Wolverine.Postgresql;

namespace Darumen.Shared.Messaging;

public sealed class MessagingOptions
{
    public const string Section = "Messaging";
    public const string KafkaMode = "kafka";
    public const string StubMode = "stub";

    /// <summary>Outbox и inbox в Postgres, но без Kafka: один сервер без брокера (публичный стенд).</summary>
    public const string LocalMode = "local";

    /// <summary>kafka: Postgres outbox/inbox и Kafka; stub: без внешних транспортов (тесты, разработка без compose).</summary>
    public string Mode { get; set; } = KafkaMode;

    public string BootstrapServers { get; set; } = "localhost:29092";

    public string SchemaRegistry { get; set; } = "http://localhost:8081";

    public string Schema { get; set; } = "wolverine";

    public string ConsumerGroup { get; set; } = "darumen-api";
}

public static class MessagingSetup
{
    public const string ServiceName = "darumen-api";

    /// <summary>Wolverine: durable outbox и inbox в Postgres, Kafka с Protobuf через Schema Registry,
    /// повторы с задержкой и dead letter. Топики создаются при старте.</summary>
    public static IHostBuilder AddDarumenMessaging(this IHostBuilder host, IConfiguration configuration, Action<WolverineOptions>? configure = null)
    {
        var options = configuration.GetSection(MessagingOptions.Section).Get<MessagingOptions>() ?? new MessagingOptions();
        var stub = string.Equals(options.Mode, MessagingOptions.StubMode, StringComparison.OrdinalIgnoreCase);
        return host.UseWolverine(opts =>
        {
            opts.ServiceName = ServiceName;
            opts.OnException<Exception>()
                .RetryWithCooldown(TimeSpan.FromMilliseconds(200), TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(5));
            configure?.Invoke(opts);

            if (stub)
            {
                opts.StubAllExternalTransports();
                opts.Durability.Mode = DurabilityMode.MediatorOnly;
                return;
            }

            opts.PersistMessagesWithPostgresql(configuration.PostgresConnection(), options.Schema);
            opts.UseEntityFrameworkCoreTransactions();
            opts.Policies.AutoApplyTransactions();

            if (string.Equals(options.Mode, MessagingOptions.LocalMode, StringComparison.OrdinalIgnoreCase))
            {
                // IDbContextOutbox требует персистентность, поэтому Postgres остаётся; внешние транспорты заглушены,
                // события без маршрута Wolverine отбрасывает с предупреждением
                opts.StubAllExternalTransports();
                opts.Services.AddResourceSetupOnStartup();
                return;
            }
            opts.Policies.UseDurableOutboxOnAllSendingEndpoints();
            opts.Policies.UseDurableInboxOnAllListeners();

            var registry = new CachedSchemaRegistryClient(new SchemaRegistryConfig { Url = options.SchemaRegistry });
            opts.UseKafka(options.BootstrapServers)
                .AutoProvision()
                .ConfigureConsumers(consumer =>
                {
                    consumer.GroupId = options.ConsumerGroup;
                    consumer.AutoOffsetReset = Confluent.Kafka.AutoOffsetReset.Earliest; // события, пришедшие пока API лежал, не теряются
                });

            opts.PublishMessage<DecisionRecorded>()
                .ToKafkaTopic(Topics.DecisionRecorded)
                .UseInterop(new ProtobufKafkaMapper<DecisionRecorded>())
                .DefaultSerializer(new ProtobufRegistrySerializer<DecisionRecorded>(registry, Topics.DecisionRecorded));

            // сообщения от Python не несут заголовков Wolverine: тип задаётся топиком через маппер
            opts.ListenToKafkaTopic(Topics.BatchLoaded)
                .UseInterop(new ProtobufKafkaMapper<BatchLoaded>())
                .DefaultIncomingMessage<BatchLoaded>()
                .DefaultSerializer(new ProtobufRegistrySerializer<BatchLoaded>(registry, Topics.BatchLoaded))
                .EnableNativeDeadLetterQueue();

            opts.Services.AddResourceSetupOnStartup();
        });
    }

    /// <summary>DbContext с интеграцией outbox: IDbContextOutbox&lt;T&gt; сохраняет сущности и события одной транзакцией.</summary>
    public static IServiceCollection AddDarumenDbContext<TContext>(this IServiceCollection services, IConfiguration configuration, Action<Microsoft.EntityFrameworkCore.DbContextOptionsBuilder> configureDb)
        where TContext : Microsoft.EntityFrameworkCore.DbContext
    {
        services.AddDbContextWithWolverineIntegration<TContext>(configureDb);
        return services;
    }
}
