using Darumen.Modules.Analytics;
using Darumen.Modules.Intake;
using Darumen.Modules.Journal;
using Darumen.Modules.Medicines;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;

namespace Darumen.Tests.Fakes;

public sealed class InMemoryQueueStates : IQueueStateRepository
{
    public Task<QueueSnapshotDto?> SnapshotAsync(string moCode, string profileCode, CancellationToken cancellationToken) =>
        Task.FromResult<QueueSnapshotDto?>(moCode == "028B" ? new QueueSnapshotDto(1784, 21, 6.1) : null);

    public Task<OrganizationSeriesDto?> SeriesAsync(string moCode, string profileCode, int days, CancellationToken cancellationToken) =>
        Task.FromResult<OrganizationSeriesDto?>(moCode == "028B"
            ? new OrganizationSeriesDto(moCode, profileCode, [new QueueDayDto("2025-03-31", 3, 2, 0, 1784, 21)], new ThroughputDto("2025-03-31", 6.1, 0.03, 90, 130))
            : null);

    public Task<IReadOnlyList<OverloadedOrganizationDto>> OverloadedAsync(string? regionKato, string? profileCode, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<OverloadedOrganizationDto>>(new List<OverloadedOrganizationDto>
        {
            new("028B", "Казахский ордена институт глазных болезней", "75", "381", 3.5, 1784, 130, 0.32),
            new("22GN", "Городская больница №2", "75", "381", null, 12, 8, 0.02), // throughput_per_day = 0 при живом потоке
            new("11XY", "Больница региона 10", "10", "381", 2.0, 40, 20, 0.05), // 5.3: другой регион — для проверки, что главврач его не видит
        }.Where(o => (regionKato is null || o.RegionKato == regionKato) && (profileCode is null || o.ProfileCode == profileCode)).Take(limit).ToList());
}

public sealed class InMemoryAnalytics : IAnalyticsRepository
{
    private readonly Dictionary<string, (string Status, string? Comment)> _acks = new();

    public List<AnomalyDto> Anomalies { get; } =
    [
        new("a1", "er_visits_daily", new Dictionary<string, string> { ["region_kato"] = "75", ["mo_key"] = "org a" }, "2025-03-15", 120, 40, 6.1, 5.0, "critical", "entity", "open", "75", null, "028B"),
        new("a2", "admissions_monthly", new Dictionary<string, string> { ["region_kato"] = "10", ["profile_code"] = "381" }, "2025-02", 50, 80, -3.4, -1.0, "warning", "shared", "open", "10", null),
        // 3.3: региональная волна очереди — различающие ключи (mo_code) уже свёрнуты в модели, Affected = сколько организаций затронуто
        new("a3", "queue_daily", new Dictionary<string, string> { ["region_kato"] = "10", ["profile_code"] = "381" }, "2025-03-20", 340, 90, 5.2, 5.2, "critical", "shared", "open", "10", null, null, 6),
    ];

    public Task<IReadOnlyList<StreamDto>> StreamsAsync(CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<StreamDto>>(
    [
        new("admissions_monthly", "Госпитализации", "month", ["region_kato", "profile_code"], [1, 2, 3]),
        new("er_visits_daily", "Приёмный покой", "day", ["region_kato", "mo_key"], [7, 14, 30]),
    ]);

    public Task<IReadOnlyList<HistoryPointDto>> HistoryAsync(string streamId, string entityJson, int periods, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<HistoryPointDto>>(entityJson == "{\"region_kato\": \"75\", \"profile_code\": \"381\"}"
            ? [new("2025-11", 790), new("2025-12", 810)]
            : []);

    public Task<Paged<AnomalyDto>> AnomaliesAsync(AnomalyFilter filter, int page, int size, CancellationToken cancellationToken)
    {
        var items = Anomalies
            .Select(a => _acks.TryGetValue(a.Id, out var ack) ? a with { Status = ack.Status, Comment = ack.Comment } : a)
            .Where(a => (filter.RegionKato is null || a.RegionKato == filter.RegionKato) && (filter.Status is null || a.Status == filter.Status)
                        && (filter.MoCode is null || a.MoCode == filter.MoCode) && (filter.StreamId is null || a.StreamId == filter.StreamId))
            .ToList();
        return Task.FromResult(new Paged<AnomalyDto>(items.Skip((page - 1) * size).Take(size).ToList(), page, size, items.Count));
    }

    public List<object> Published { get; } = [];

    /// <summary>Команды, дошедшие до хранилища: проверка того, что актор, роль и регион передаются дальше.</summary>
    public List<AnomalyAckCommand> Commands { get; } = [];

    public Task<AckOutcome> AcknowledgeAsync(AnomalyAckCommand command, Func<object> outboxEvent, CancellationToken cancellationToken)
    {
        var anomaly = Anomalies.FirstOrDefault(a => a.Id == command.AnomalyId);
        if (anomaly is null)
        {
            return Task.FromResult(AckOutcome.NotFound);
        }

        if ((command.RegionScope is not null && anomaly.RegionKato != command.RegionScope) || (command.MoScope is not null && anomaly.MoCode != command.MoScope))
        {
            return Task.FromResult(AckOutcome.OutOfScope);
        }

        Commands.Add(command);
        _acks[command.AnomalyId] = (command.Status, command.Comment);
        Published.Add(outboxEvent());
        return Task.FromResult(AckOutcome.Acknowledged);
    }

    public Task<IReadOnlyList<string>> IndexMonthsAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<string>>(["2025-01", "2025-02", "2025-03"]);

    public Task<IReadOnlyList<IndexItemDto>> IndexAsync(string month, string profileCode, string lang, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<IndexItemDto>>(
        [
            new("62", lang == Locale.Kk ? "Павлодар облысы" : "Павлодарская область", 0.05, 12, 95.2, 1, 900),
            new("75", lang == Locale.Kk ? "Алматы қаласы" : "город Алматы", 0.6, 126, 2.4, 20, 5000),
        ]);

    public Task<IReadOnlyDictionary<string, int>> AnomalyAckStatsAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyDictionary<string, int>>(
            _acks.Values.GroupBy(a => a.Status).ToDictionary(g => g.Key, g => g.Count()));

    public Task<IReadOnlyList<LosItemDto>> LosAsync(string? regionKato, string? profileCode, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<LosItemDto>>(
        [
            new("75", "Кардиологические для взрослых", "031", 4200, 7.0, 6.8),
            new("10", "Терапевтические", "021", 1800, 8.5, 8.1),
        ]);

    public Task<IReadOnlyList<StaffingRegionDto>> StaffingByRegionAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<StaffingRegionDto>>(
        [
            new("10", "Область Абай", 12.5, 3.1, new DateOnly(2026, 5, 13)),
            new("75", "город Алматы", 18.2, null, new DateOnly(2026, 5, 13)), // регион без госпитализаций за 12 мес.
        ]);

    // 5.8: общенациональные разбивки — vac_refusals не содержит региона
    public Task<VacRefusalsDto> VaccinationRefusalsAsync(CancellationToken cancellationToken) =>
        Task.FromResult(new VacRefusalsDto(
            [
                new("родители отказались", 120),
                new("медотвод", 45),
            ],
            [
                new("аллергия", 20),
                new("unknown", 25),
            ]));

    public Task<IReadOnlyList<OncoLateItemDto>> OncologyLateStageAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<OncoLateItemDto>>(
        [
            new("C16", "Желудок", "C16", 400, 100, 0.25, 200, 0.5, 300, 0.75, new DateOnly(2026, 5, 1)),
            new("C50", "Молочная железа", "C50", 1000, 250, 0.25, 150, 0.15, 400, 0.4, new DateOnly(2026, 5, 1)),
        ]);

    // 5.10: gold.equipment_by_region / _by_organization - число единиц активной медтехники
    public Task<IReadOnlyList<EquipmentRegionDto>> EquipmentByRegionAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<EquipmentRegionDto>>(
        [
            new("75", "город Алматы", 340),
            new("10", "Область Абай", 120),
        ]);

    public Task<long> EquipmentForOrganizationAsync(string moCode, CancellationToken cancellationToken) =>
        Task.FromResult(moCode == "028B" ? 42L : 0L);
}

public sealed class InMemoryDecisions : IDecisionRepository
{
    private readonly List<(DecisionDto Decision, string? Key)> _rows = [];
    private readonly Dictionary<Guid, string?> _organizations = new();

    public List<object> Published { get; } = [];

    public Task<DecisionDto?> FindByIdempotencyKeyAsync(string key, CancellationToken cancellationToken) =>
        Task.FromResult<DecisionDto?>(_rows.FirstOrDefault(r => r.Key == key).Decision);

    public Task<(DecisionDto Decision, bool Created)> RecordAsync(NewDecision decision, Func<DecisionDto, object> outboxEvent, CancellationToken cancellationToken)
    {
        if (decision.IdempotencyKey is not null)
        {
            var existing = _rows.FirstOrDefault(r => r.Key == decision.IdempotencyKey);
            if (existing.Decision is not null)
            {
                return Task.FromResult((existing.Decision, false));
            }
        }

        var dto = new DecisionDto(Guid.NewGuid(), decision.Actor, decision.Role, decision.Subject, decision.SubjectId,
            ParseJson(decision.RecommendedJson), ParseJson(decision.ChosenJson), decision.Reason, DateTimeOffset.UtcNow);
        _rows.Add((dto, decision.IdempotencyKey));
        _organizations[dto.DecisionId] = decision.ActorMoCode;
        Published.Add(outboxEvent(dto));
        return Task.FromResult((dto, true));
    }

    public Task<Paged<DecisionDto>> ListAsync(string? actor, string? subject, string? subjectId, int page, int size, CancellationToken cancellationToken)
    {
        var items = _rows.Select(r => r.Decision)
            .Where(d => (actor is null || d.Actor == actor) && (subject is null || d.Subject == subject) && (subjectId is null || d.SubjectId == subjectId))
            .OrderByDescending(d => d.RecordedAt)
            .ToList();
        return Task.FromResult(new Paged<DecisionDto>(items, page, size, items.Count));
    }

    /// <summary>Как DecisionRepository: решения актёров организации или с организацией в recommended/chosen.</summary>
    public async Task<Paged<DecisionDto>> ListForOrganizationAsync(string moCode, string? actor, string? subject, string? subjectId, int page, int size,
        CancellationToken cancellationToken)
    {
        var all = await ListAsync(actor, subject, subjectId, 1, int.MaxValue, cancellationToken);
        var items = all.Items.Where(d => _organizations.GetValueOrDefault(d.DecisionId) == moCode || MoCode(d.Recommended) == moCode || MoCode(d.Chosen) == moCode).ToList();
        return new Paged<DecisionDto>(items, page, size, items.Count);
    }

    private static string? MoCode(System.Text.Json.JsonElement? element) =>
        element is { ValueKind: System.Text.Json.JsonValueKind.Object } value && value.TryGetProperty("moCode", out var mo) ? mo.GetString() : null;

    // как DecisionRepository: recommended/chosen хранятся JSON-текстом и отдаются JsonElement — маршрут читает из них moCode
    private static System.Text.Json.JsonElement? ParseJson(string? json) =>
        json is null ? null : System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(json);
}

public sealed class InMemoryRefData : IRefDataRepository
{
    public Task<IReadOnlyList<RegionDto>> RegionsAsync(string lang, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<RegionDto>>([new("10", lang == Locale.Kk ? "Абай облысы" : "Область Абай", "Семей", 50.41, 80.23, 606)]);

    public Task<IReadOnlyList<OrganizationItemDto>> OrganizationsAsync(string? regionKato, string? query, string? profileCode, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<OrganizationItemDto>>(new List<OrganizationItemDto>
        {
            new("028B", "Казахский ордена институт глазных болезней", "75", "center", "L", null, null, "институт глазных болезней"),
            new("22GN", "Городская больница №2", "75", "hospital", "M", null, null, "городская больница 2"),
        }.Where(o => (regionKato is null || o.RegionKato == regionKato)
                     && (query is null || o.Name.Contains(query, StringComparison.OrdinalIgnoreCase) || o.MoCode == query)).Take(limit).ToList());

    public Task<IReadOnlyList<ProfileDto>> ProfilesAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<ProfileDto>>([new("381", "Офтальмологические для взрослых", false, 12000), new("DH", "Дневной стационар", true, 300000)]);

    public Task<IReadOnlyList<SeasonalityDto>> SeasonalityAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<SeasonalityDto>>([new("rtt_waiting_list", 9, 1.0186, "Лист ожидания", "NHS England RTT", 2020, "2017-01..2019-12")]);

    public Task<IReadOnlyList<VaccinationBenchmarkDto>> VaccinationAsync(CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<VaccinationBenchmarkDto>>(
            [new("DTP3", "АКДС, третья доза", 2024, 54.0, "WHO GHO / WUENIC", "внешний ориентир, не факт")]);

    public Task<IReadOnlyList<string>> VaccinationPlansAsync(string? regionKato, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<string>>(regionKato is null or "75" ? ["Национальный календарь", "По эпидпоказаниям"] : []);

    /// <summary>Сокращённый Стандарт: те же коды стадий и типичные сроки давности приложения 5, что в refdata/route_standard.yaml.</summary>
    public Task<RouteStandardDto> RouteStandardAsync(string lang, CancellationToken cancellationToken)
    {
        var kk = lang == Locale.Kk;
        const string source = "Стандарт стационарной помощи, приказ МЗ РК № ҚР-ДСМ-27 (ред. 15.09.2025)";
        return Task.FromResult(new RouteStandardDto(
            new RouteStandardMetaDto(source, "https://adilet.zan.kz/rus/docs/V2200027218", "2025-09-15"),
            true,
            [
                new("referral_issued", 1, kk ? "Жолдама берілді" : "Направление выдано", "1 рабочий день", null, null, null),
                new("examination", 2, kk ? "Тексеру" : "Обследование", "приложение 5", null, null, null),
                new("waitlisted", 3, kk ? "Күту парағына енгізілді" : "Внесено в лист ожидания", "регистрация в Портале", null, null, null),
                new("date_assigned", 4, kk ? "Күні белгіленді" : "Дата назначена", "в течение 2 рабочих дней", 2, 2, null),
                new("hospitalized", 5, kk ? "Емдеуге жатқызу" : "Госпитализация", "приёмное отделение", null, null, null),
                new("refused", 5, kk ? "Бас тарту" : "Отказ", "неявка 2 дня", null, null, 2),
            ],
            [new("no_indications", "нет показаний"), new("contraindications", "противопоказания"), new("no_show_2_days", "неявка 2 дня"), new("non_core_profile", "непрофильная")],
            [
                new("cbc", kk ? "Жалпы қан талдауы" : "Общий анализ крови", 14, kk ? "14 күн" : "14 дней"),
                new("ecg", "ЭКГ", 14, kk ? "14 күн" : "14 дней"),
                new("hiv", kk ? "АИТВ" : "ВИЧ", 180, kk ? "6 ай" : "6 месяцев"),
                new("fluorography", kk ? "Флюорография" : "Флюорография", 365, kk ? "12 ай" : "12 месяцев"),
            ],
            [
                new("moh_avg_wait_days", 30, "days", kk ? "Орташа күту мерзімі" : "Средний срок ожидания", "МЗ РК, коллегия 19.02.2026", "2026-02-19"),
                new("moh_target_wait_days", 20, "days", kk ? "Мақсатты күту мерзімі" : "Целевой срок ожидания", "МЗ РК, коллегия 19.02.2026", "2026-02-19"),
            ]));
    }
}

public sealed class InMemoryWorklist : IWorklistRepository
{
    public static readonly DateOnly AsOf = new(2025, 3, 31);

    public Task<IReadOnlyList<QueueStateRow>> QueueStatesAsync(string regionKato, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<QueueStateRow>>(regionKato != "75" ? [] :
        [
            new(AsOf, "028B", "Институт глазных болезней", "381", "75", 1784, 47, 90, 11.4, 0.32, 55, 66),
            new(AsOf, "22GN", "Городская больница №2", "381", "75", 12, 3, 8, 4.0, 0.02, 9, 20),
            new(AsOf, "027O", "Городская больница №7", "021", "75", 40, 6, 14, 6.0, 0.05, 7, 15),
        ]);
}

public sealed class InMemoryNotificationReads : INotificationReadRepository
{
    private readonly HashSet<(string Actor, string Kind, Guid DecisionId)> _reads = [];

    public Task MarkReadAsync(string actor, string kind, Guid decisionId, CancellationToken cancellationToken)
    {
        _reads.Add((actor, kind, decisionId));
        return Task.CompletedTask;
    }

    public Task<HashSet<Guid>> ReadDecisionIdsAsync(string actor, string kind, IReadOnlyCollection<Guid> decisionIds, CancellationToken cancellationToken) =>
        Task.FromResult(_reads.Where(r => r.Actor == actor && r.Kind == kind && decisionIds.Contains(r.DecisionId)).Select(r => r.DecisionId).ToHashSet());
}

public sealed class InMemoryMedicines : IMedicinesRepository
{
    public static IReadOnlyList<RxWeek> Weeks(int fulfilledRecent) =>
        Enumerable.Range(0, 16).Select(i => new RxWeek(new DateOnly(2025, 1, 6).AddDays(7 * i), 100, i < 12 ? 90 : fulfilledRecent, i < 12 ? 70 : fulfilledRecent / 2, 3, 9)).ToList();

    public Task<IReadOnlyList<RxWeek>> WeeksAsync(string mnnId, int weeks, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<RxWeek>>(mnnId == "817" ? Weeks(40) : mnnId == "900" ? Weeks(88) : []);

    public Task<IReadOnlyList<RxMonth>> MonthsAsync(string nosologyId, int months, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<RxMonth>>(nosologyId == "109" ? [new(new DateOnly(2025, 3, 1), "63", 5000, 4800, 4000, 2, 8)] : []);

    public Task<IReadOnlyList<DrugProgram>> ProgramsAsync(string nosologyId, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<DrugProgram>>(nosologyId == "109" ? [new("90", "63", 120, 40, 2260)] : []);

    public Task<IReadOnlyList<NosologyDto>> NosologiesAsync(int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<NosologyDto>>([new("109", "63", 60000, 58000, 25)]);

    public Task<IReadOnlyList<MnnDto>> MnnAsync(string nosologyId, int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<MnnDto>>([new("817", nosologyId, "63", 30000, 29000, 3), new("900", nosologyId, "63", 10000, 9900, 2)]);

    // 5.7 C: тот же топ, но без фильтра по нозологии — здесь просто повторяет MnnAsync для двух известных тестам МНН
    public Task<IReadOnlyList<MnnDto>> TopMnnAsync(int limit, CancellationToken cancellationToken) =>
        Task.FromResult<IReadOnlyList<MnnDto>>([new("817", "109", "63", 30000, 29000, 3), new("900", "109", "63", 10000, 9900, 2)]);

    // 5.7 A: модель предсказывает p50 только для 817 — у 900 витрина как будто ещё не насчитала ячейку
    public Task<double?> FillDaysP50ModelAsync(string mnnId, CancellationToken cancellationToken) =>
        Task.FromResult<double?>(mnnId == "817" ? 3.2 : null);

    // 5.7 B: у категории 63 есть ровесники, обеспечены хуже, чем 817 в базовый период (0.9), но лучше текущего провала
    public Task<PeerFulfillmentDto?> PeerFulfillmentAsync(string mnnId, string categoryId, CancellationToken cancellationToken) =>
        Task.FromResult<PeerFulfillmentDto?>(categoryId == "63" ? new PeerFulfillmentDto(0.85, 4, 5000, 4250) : null);
}

public sealed class InMemoryIntake : IIntakeRepository
{
    public Task<Paged<BatchDto>> BatchesAsync(string? status, string? dataset, int page, int size, CancellationToken cancellationToken)
    {
        var items = new List<BatchDto>
        {
            new("b-1", "bg_referrals", "loaded", 767084, 46, ["region_kato=10/p_month=2025-01"], DateTimeOffset.UtcNow.AddMinutes(-5), DateTimeOffset.UtcNow),
        }.Where(b => (status is null || b.Status == status) && (dataset is null || b.Dataset == dataset)).ToList();
        return Task.FromResult(new Paged<BatchDto>(items, page, size, items.Count));
    }
}
