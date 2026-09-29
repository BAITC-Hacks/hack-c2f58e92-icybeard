using Darumen.Contracts.V1;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Darumen.Shared.Messaging;
using static Darumen.Shared.Auth.RegionAccess;

namespace Darumen.Modules.Analytics;

public static class AnalyticsEndpoints
{
    public const string AllProfiles = "all";
    private const string LosMethod =
        "Медиана длительности лечения по пролеченным случаям ЭРСБ за последние 12 месяцев; p50 модели — LightGBM-квантиль по профилю, региону, " +
        "диагнозу и типу помощи. Ячейки меньше 100 случаев подавлены. Одна койка ≈ 1/LOS госпитализаций в день.";

    private const string IndexMethod =
        "Индекс = 100 − среднее перцентильных рангов региона по доле ожидавших дольше 30 дней и по 90-му перцентилю ожидания внутри месяца и профиля; " +
        "100 у самого доступного региона. Строки с числом госпитализаций меньше 5 подавлены.";

    private const string StaffingMethod =
        "Занимаемые ставки медперсонала (сумма staffing.position_rate на дату снапшота) на 10 тыс. населения (refdata.regions) " +
        "и на 1 000 госпитализаций за последние 12 месяцев (gold.admissions_monthly); регионы отсортированы по возрастанию первого " +
        "показателя, наименее укомплектованные — первыми.";

    private const string VacRefusalsMethod =
        "Отказы от вакцинации и противопоказания (gold.vac_refusals_by_reason / _by_contraindication). В исходных данных нет " +
        "колонки региона и нет организации, из которой регион можно было бы вывести, поэтому разбивка только общенациональная, " +
        "по причине и отдельно по противопоказанию (это разные измерения одной строки, не вложенные друг в друга).";

    private const string OncoLateMethod =
        "Доля запущенных случаев (III и IV стадии) среди выявленных ЗН по локализациям (gold.onco_late) за последнюю дату " +
        "загрузки. Источник — ЭРОБ, уже общенациональный агрегат по локализации, региона в нём нет и быть не может.";

    private const string EquipmentMethod =
        "Число единиц активной медицинской техники по регионам (gold.equipment_by_region): сумма quantity (пустое значение " +
        "считается за одну единицу) по строкам без даты списания. Регионы отсортированы по убыванию числа единиц.";

    private static readonly string[] AnomalyPermissions = [Permissions.GovMap, Permissions.OrgCabinet];

    public static void Map(IEndpointRouteBuilder api)
    {
        api.MapGet("/streams", async (IAnalyticsRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.StreamsAsync(ct) }))
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap))
            .WithTags("Forecast").WithName("Streams").WithSummary("Каталог зарегистрированных потоков");

        api.MapGet("/forecast/{streamId}", async (string streamId, int? horizon, HttpRequest http, ForecastService service, CancellationToken ct) =>
            {
                // роль, привязанная к региону, прогнозирует только свой регион: клейм region_kato сильнее entity[regionKato] в запросе,
                // если сущность вообще ключуется по региону (у некоторых потоков ключ — localization/mo_key, не регион)
                var entity = new Dictionary<string, string>(ParseEntity(http.Query));
                var scope = RegionScope(CurrentUser.From(http.HttpContext));
                if (scope is not null && entity.ContainsKey("region_kato"))
                {
                    entity["region_kato"] = scope;
                }

                return await service.ForecastAsync(streamId, entity, horizon ?? 0, ct);
            })
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap))
            .WithTags("Forecast").WithName("Forecast").WithSummary("Прогноз потока для сущности: entity[regionKato]=75&entity[profileCode]=381")
            .Produces<ForecastResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity).ProducesProblem(StatusCodes.Status404NotFound);

        // карта (gov.map) видит все сигналы; кабинет организации (org.cabinet) при scope own — только сигналы своей организации
        var anomalies = api.MapGroup("/anomalies").WithTags("Anomalies").RequireAuthorization(Permissions.Policy(AnomalyPermissions));
        anomalies.MapGet("/", async (string? regionKato, string? streamId, string? severity, string? status, string? moCode, int? page, int? size,
                HttpContext http, IAnalyticsRepository repository, CancellationToken ct) =>
            {
                var scope = await OrgAccess.ResolveAsync(http, moCode, AnomalyPermissions);
                if (scope.Problem is not null)
                {
                    return scope.Problem;
                }

                // роль, привязанная к региону, видит сигналы только своего региона: клейм region_kato сильнее параметра запроса
                regionKato = RegionScope(CurrentUser.From(http)) ?? regionKato;
                var (p, s) = Paging.Normalize(page, size);
                return Results.Ok(await repository.AnomaliesAsync(new AnomalyFilter(regionKato, streamId, severity, status ?? "open", scope.MoCode), p, s, ct));
            })
            .WithName("Anomalies").WithSummary("Сигналы аномалий, по умолчанию открытые, отсортированы по силе")
            .Produces<Paged<AnomalyDto>>();

        anomalies.MapPost("/{id}/ack", async (string id, AckRequestDto? body, HttpContext http, IAnalyticsRepository repository, CancellationToken ct) =>
            {
                var status = string.IsNullOrWhiteSpace(body?.Status) ? AnomalyStatuses.Acknowledged : body.Status;
                if (!AnomalyStatuses.Closing.Contains(status))
                {
                    return new ValidationErrors().Add("status", $"допустимые значения: {string.Join(", ", AnomalyStatuses.Closing)}").Problem();
                }

                var scope = await OrgAccess.ResolveAsync(http, null, AnomalyPermissions);
                if (scope.Problem is not null)
                {
                    return scope.Problem;
                }

                var user = CurrentUser.From(http);
                // просматривать сигналы могут gov.map/org.cabinet, но закрывать (ack) — только регулятор (bug fix: раньше
                // мог закрыть любой с этими правами, включая org_admin своей организации).
                if (user.Role != Roles.Regulator)
                {
                    return Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Только регулятор",
                        detail: "закрыть сигнал аномалии может только регулятор");
                }

                var command = new AnomalyAckCommand(id, status, body?.Comment, user.Actor, user.Role, RegionScope(user), scope.IsOwn ? scope.MoCode : null);
                var outcome = await repository.AcknowledgeAsync(command,
                    () => new DecisionRecorded
                    {
                        Meta = Events.Meta(),
                        DecisionId = id,
                        ActorRole = user.Role,
                        Subject = DecisionSubjects.Anomaly,
                        Recommended = AnomalyStatuses.Open,
                        Chosen = status,
                        Reason = body?.Comment ?? string.Empty,
                    },
                    ct);
                return outcome switch
                {
                    AckOutcome.Acknowledged => Results.NoContent(),
                    AckOutcome.OutOfScope => AccessProblems.Forbidden(AccessProblems.OtherOrganization),
                    _ => Results.NotFound(),
                };
            })
            .WithName("AcknowledgeAnomaly").WithSummary("Подтвердить сигнал или отметить ложным; решение попадает в журнал")
            .Produces(StatusCodes.Status204NoContent).Produces(StatusCodes.Status404NotFound)
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        // качество моделей — на карте и в пояснении ассистента направления (качество модели ожидания)
        api.MapGet("/quality", async (QualityService quality, CancellationToken ct) => await quality.ReportAsync(ct))
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap, Permissions.ReferralAssist))
            .WithTags("Quality").WithName("ModelQuality")
            .WithSummary("Качество моделей: отчёты обучения против baseline, разбор по регионам и профилям, доля плоских прогнозов");

        api.MapGet("/los", async (string? regionKato, string? profileCode, IAnalyticsRepository repository, CancellationToken ct) =>
                Results.Ok(new LosResponseDto(await repository.LosAsync(regionKato, profileCode, ct), LosMethod)))
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap))
            .WithTags("Quality").WithName("LengthOfStay")
            .WithSummary("Длительность лечения по ячейкам регион×профиль: факт-медиана за 12 месяцев и p50 модели")
            .Produces<LosResponseDto>();

        api.MapGet("/staffing", async (IAnalyticsRepository repository, CancellationToken ct) =>
                Results.Ok(new StaffingResponseDto(await repository.StaffingByRegionAsync(ct), StaffingMethod)))
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap))
            .WithTags("Quality").WithName("StaffingByRegion")
            .WithSummary("Ставки медперсонала на 10 тыс. населения и на 1 000 госпитализаций по регионам")
            .Produces<StaffingResponseDto>();

        api.MapGet("/index", async (string? month, string? profileCode, HttpRequest http, IAnalyticsRepository repository, CancellationToken ct) =>
            {
                var months = await repository.IndexMonthsAsync(ct);
                if (months.Count == 0)
                {
                    return Results.Ok(new IndexResponseDto(month ?? string.Empty, profileCode ?? AllProfiles, [], [], IndexMethod));
                }

                var chosen = string.IsNullOrWhiteSpace(month) ? months[^1] : month;
                if (!months.Contains(chosen))
                {
                    return new ValidationErrors().Add("month", $"нет данных за {chosen}; доступны {string.Join(", ", months)}").Problem();
                }

                var profile = string.IsNullOrWhiteSpace(profileCode) ? AllProfiles : profileCode;
                var items = await repository.IndexAsync(chosen, profile, Locale.From(http), ct);
                return Results.Ok(new IndexResponseDto(chosen, profile, items, months, IndexMethod));
            })
            .WithTags("Index").WithName("AccessIndex").WithSummary("Индекс доступности плановой госпитализации по регионам")
            .Produces<IndexResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        api.MapGet("/vaccination-refusals", async (IAnalyticsRepository repository, CancellationToken ct) =>
            {
                var data = await repository.VaccinationRefusalsAsync(ct);
                return Results.Ok(new VaccinationRefusalsResponseDto(data.ByReason, data.ByContraindication, VacRefusalsMethod));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap))
            .WithTags("Quality").WithName("VaccinationRefusals")
            .WithSummary("Отказы от вакцинации по причине и по противопоказанию, общенационально")
            .Produces<VaccinationRefusalsResponseDto>();

        api.MapGet("/oncology-late-stage", async (IAnalyticsRepository repository, CancellationToken ct) =>
                Results.Ok(new OncologyLateStageResponseDto(await repository.OncologyLateStageAsync(ct), OncoLateMethod)))
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap))
            .WithTags("Quality").WithName("OncologyLateStage")
            .WithSummary("Доля запущенных случаев (III/IV стадии) по локализациям, общенационально")
            .Produces<OncologyLateStageResponseDto>();

        api.MapGet("/equipment", async (IAnalyticsRepository repository, CancellationToken ct) =>
                Results.Ok(new EquipmentResponseDto(await repository.EquipmentByRegionAsync(ct), EquipmentMethod)))
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap))
            .WithTags("Quality").WithName("EquipmentByRegion")
            .WithSummary("Число единиц активной медтехники по регионам, для сравнения на /gov")
            .Produces<EquipmentResponseDto>();

        api.MapGet("/equipment/organizations/{moCode}", async (string moCode, HttpContext http, IAnalyticsRepository repository, CancellationToken ct) =>
                await OrgAccess.CheckAsync(http, moCode, Permissions.OrgCabinet) is { } denied
                    ? denied
                    : Results.Ok(new EquipmentOrganizationDto(moCode, await repository.EquipmentForOrganizationAsync(moCode, ct))))
            .RequireAuthorization(Permissions.Policy(Permissions.OrgCabinet))
            .WithTags("Quality").WithName("EquipmentByOrganization")
            .WithSummary("Число единиц активной медтехники организации, для кабинета организации")
            .Produces<EquipmentOrganizationDto>();
    }

    /// <summary>entity[regionKato]=75 → region_kato: 75; ключи в snake_case тоже принимаются.</summary>
    internal static IReadOnlyDictionary<string, string> ParseEntity(IQueryCollection query)
    {
        var entity = new Dictionary<string, string>();
        foreach (var (key, value) in query)
        {
            if (key.StartsWith("entity[", StringComparison.Ordinal) && key.EndsWith(']'))
            {
                entity[EntityJson.ToSnake(key[7..^1])] = value.ToString();
            }
        }

        return entity;
    }
}
