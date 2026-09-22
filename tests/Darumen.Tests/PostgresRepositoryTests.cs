using Darumen.Modules.Analytics;
using Darumen.Modules.Journal;
using Darumen.Modules.Medicines;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Data;
using Npgsql;

namespace Darumen.Tests;

/// <summary>Репозитории Dapper против локального Postgres после make publish. Запуск: DARUMEN_PG_TEST=1 dotnet test.</summary>
public sealed class PostgresRepositoryTests
{
    private static readonly bool Enabled = Environment.GetEnvironmentVariable("DARUMEN_PG_TEST") == "1";

    private static IDbConnectionFactory Factory()
    {
        Dapper.DefaultTypeMap.MatchNamesWithUnderscores = true;
        var connection = Environment.GetEnvironmentVariable("POSTGRES_CONNECTION") ?? DataRegistration.DefaultConnection;
        return new NpgsqlConnectionFactory(NpgsqlDataSource.Create(connection));
    }

    [SkippableFact]
    public async Task Index_months_and_rows()
    {
        var repository = new AnalyticsRepository(Factory(), null!); // чтение не использует outbox
        var months = await repository.IndexMonthsAsync(CancellationToken.None);
        Assert.Contains("2025-03", months);
        var rows = await repository.IndexAsync(months[^1], AnalyticsEndpoints.AllProfiles, "ru", CancellationToken.None);
        Assert.True(rows.Count >= 20, $"rows: {rows.Count}");
        Assert.Equal(1, rows[0].Rank);
        Assert.False(string.IsNullOrEmpty(rows[0].Name));
    }

    [SkippableFact]
    public async Task Streams_history_and_anomalies()
    {
        var repository = new AnalyticsRepository(Factory(), null!);
        var streams = await repository.StreamsAsync(CancellationToken.None);
        Assert.Contains(streams, s => s.StreamId == "admissions_monthly" && s.EntityKeys.SequenceEqual(["region_kato", "profile_code"]));
        var history = await repository.HistoryAsync("admissions_monthly", "{\"region_kato\": \"75\", \"profile_code\": \"381\"}", 12, CancellationToken.None);
        Assert.Equal(12, history.Count);
        var anomalies = await repository.AnomaliesAsync(new AnomalyFilter("75", null, "critical", null), 1, 5, CancellationToken.None);
        Assert.True(anomalies.Total > 0);
        Assert.Equal(5, anomalies.Items.Count);
    }

    [SkippableFact]
    public async Task Queue_state_and_series()
    {
        var repository = new QueueStateRepository(Factory());
        var snapshot = await repository.SnapshotAsync("028B", "381", CancellationToken.None);
        Assert.NotNull(snapshot);
        Assert.True(snapshot.Len > 0);
        var series = await repository.SeriesAsync("028B", "381", 7, CancellationToken.None);
        Assert.Equal(7, series!.Days.Count);
        Assert.NotNull(series.Throughput);
    }

    [SkippableFact]
    public async Task RefData_and_decisions()
    {
        var refData = new RefDataRepository(Factory());
        Assert.Equal(20, (await refData.RegionsAsync("ru", CancellationToken.None)).Count);
        Assert.NotEmpty(await refData.OrganizationsAsync("75", "глазн", null, 10, CancellationToken.None));
        var withQueue = await refData.OrganizationsAsync("75", null, "381", 5, CancellationToken.None);
        Assert.Equal("028B", withQueue[0].MoCode);
        Assert.NotEmpty(await refData.ProfilesAsync(CancellationToken.None));

        // запись решений идёт через outbox и проверяется в KafkaIntegrationTests; здесь только чтение
        var decisions = new DecisionRepository(null!, Factory());
        var page = await decisions.ListAsync(null, "referral", null, 1, 5, CancellationToken.None);
        Assert.True(page.Total >= 0 && page.Items.Count <= 5);
    }

    /// <summary>Выпадающий список МНН: внутри нозологии каждый МНН один раз. МНН 286 при нозологии 110 лежит в витрине
    /// в трёх категориях (63, 64, 68); до правки MnnAsync возвращал его трижды и ронял выбор в мобильном клиенте.</summary>
    [SkippableFact]
    public async Task Mnn_ids_are_unique_within_nosology()
    {
        var repository = new MedicinesRepository(Factory());
        var rows = await repository.MnnAsync("110", 100, CancellationToken.None);
        Assert.NotEmpty(rows);
        Assert.Equal(rows.Count, rows.Select(r => r.MnnId).Distinct().Count());
        Assert.All(rows, r => Assert.Equal("110", r.NosologyId));
    }

    /// <summary>Пропускает тест без DARUMEN_PG_TEST=1, чтобы CI без Postgres оставался зелёным.</summary>
    public sealed class SkippableFactAttribute : FactAttribute
    {
        public SkippableFactAttribute()
        {
            if (!Enabled)
            {
                Skip = "set DARUMEN_PG_TEST=1 with a published local Postgres";
            }
        }
    }
}
