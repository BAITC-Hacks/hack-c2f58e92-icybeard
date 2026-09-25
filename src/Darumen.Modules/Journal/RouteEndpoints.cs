using System.Text.Json;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Journal;

/// <summary>Маршрут пациента: /route/me — гражданин видит свой (синтетический) маршрут; /route/{patientRef} — врач видит
/// маршрут пациента из рабочего списка своего региона и перенаправляет его с причиной (запись в журнал решений).
/// Без output cache: ответ зависит от пользователя. Сервис моделей недоступен — маршрут строится по агрегатам витрины
/// (Forecast.FromModel = false), как рабочий список, а не падает 503 через UpstreamExceptionHandler.</summary>
public static class RouteEndpoints
{
    /// <summary>Регион гражданина без клейма region_kato и без параметра — г. Алматы, как у демо-пользователей.</summary>
    public const string DefaultRegion = "75";
    private const int AlternativesLimit = 3;
    private const int DecisionsLimit = 20;

    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/route").WithTags("Route");

        group.MapGet("/me", async (string? regionKato, HttpContext http, IWorklistRepository worklist, IRefDataRepository refData,
                IDecisionRepository decisions, QueueService queueService, QueuePredictions predictions, CancellationToken ct) =>
            {
                var (parsed, states, problem) = await ResolveCitizenAsync(regionKato, http, worklist, refData, predictions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                return await BuildAsync(parsed!, states!, RouteAudience.Citizen, Locale.From(http.Request), refData, decisions, queueService, ct);
            })
            .RequireAuthorization(Policies.Citizen)
            .WithName("MyRoute")
            .WithSummary("Мой маршрут: синтетический пациент на реальных очередях региона — стадии Стандарта, прогноз ожидания, чек-лист обследований, где быстрее, решения врача, история")
            .Produces<RouteDto>().ProducesProblem(StatusCodes.Status404NotFound).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/me/signals", async (RouteSignalRequestDto body, string? regionKato, HttpContext http, IWorklistRepository worklist,
                IRefDataRepository refData, IDecisionRepository decisions, QueuePredictions predictions, CancellationToken ct) =>
            {
                var (parsed, _, problem) = await ResolveCitizenAsync(regionKato, http, worklist, refData, predictions, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var errors = new ValidationErrors().Require("kind", body.Kind);
                if (!errors.Any && !RouteSignals.Kinds.Contains(body.Kind!))
                {
                    errors.Add("kind", $"ожидается один из: {string.Join(", ", RouteSignals.Kinds)}");
                }

                var request = !errors.Any && body.Kind == RouteSignals.RequestRedirect;
                if (request)
                {
                    errors.Require("toMoCode", body.ToMoCode);
                    if (!errors.Any && body.ToMoCode == parsed!.MoCode)
                    {
                        errors.Add("toMoCode", "организация совпадает с текущей");
                    }
                }

                if (errors.Any)
                {
                    return errors.Problem();
                }

                // сигнал — та же запись журнала, что решение врача: recommended = текущая организация, chosen = {"signal", "moCode"?};
                // комментарий гражданина — в reason, без обработки текста
                var comment = string.IsNullOrWhiteSpace(body.Comment) ? null : body.Comment.Trim();
                return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, parsed!.Format(),
                    MoJson(parsed.MoCode), RouteSignals.Json(body.Kind!, request ? body.ToMoCode : null), comment, _ => "/api/v1/route/me", ct);
            })
            .RequireAuthorization(Policies.Citizen)
            .WithName("MyRouteSignal")
            .WithSummary("Сигнал гражданина по своему маршруту: «ещё жду», «уже лечился в другом месте», «больше не нужно» или просьба рассмотреть организацию быстрее (toMoCode); врач видит его в рабочем списке и отвечает решением")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status404NotFound).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/{patientRef}", async (string patientRef, HttpContext http, IWorklistRepository worklist, IRefDataRepository refData,
                IDecisionRepository decisions, QueueService queueService, CancellationToken ct) =>
            {
                var (parsed, states, problem) = await ResolveAsync(patientRef, http, worklist, ct);
                if (problem is not null)
                {
                    return problem;
                }

                return await BuildAsync(parsed!, states!, RouteAudience.Doctor, Locale.From(http.Request), refData, decisions, queueService, ct);
            })
            .RequireAuthorization(Policies.Doctor)
            .WithName("PatientRoute")
            .WithSummary("Маршрут пациента рабочего списка (реф SYN-регион-организация-профиль-NN) с панелью врача: приоритет, риск отказа, факторы")
            .Produces<RouteDto>().ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound);

        group.MapPost("/{patientRef}/redirect", async (string patientRef, RouteRedirectRequestDto body, HttpContext http, IWorklistRepository worklist,
                IDecisionRepository decisions, QueueService queueService, CancellationToken ct) =>
            {
                var (parsed, states, problem) = await ResolveAsync(patientRef, http, worklist, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var errors = new ValidationErrors().Require("toMoCode", body.ToMoCode).Require("reason", body.Reason);
                if (!errors.Any && body.ToMoCode == parsed!.MoCode)
                {
                    errors.Add("toMoCode", "организация совпадает с текущей");
                }

                if (errors.Any)
                {
                    return errors.Problem();
                }

                var reference = parsed!.Format();
                return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, reference,
                    MoJson(await RecommendedAsync(parsed, states!, queueService, ct)), MoJson(body.ToMoCode!), body.Reason, _ => $"/api/v1/route/{reference}", ct);
            })
            .RequireAuthorization(Policies.Doctor)
            .WithName("RedirectRoute")
            .WithSummary("Перенаправить пациента в другую организацию с причиной: решение (рекомендация системы и выбор врача) уходит в журнал, гражданин видит его на маршруте")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/{patientRef}/keep", async (string patientRef, RouteKeepRequestDto body, HttpContext http, IWorklistRepository worklist,
                IDecisionRepository decisions, QueueService queueService, CancellationToken ct) =>
            {
                var (parsed, states, problem) = await ResolveAsync(patientRef, http, worklist, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var errors = new ValidationErrors().Require("reason", body.Reason);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                // «оставить» — тоже решение с причиной: закрывает сигнал гражданина и попадает в журнал как Kind = keep
                var reference = parsed!.Format();
                return await DecisionRecording.RecordAsync(http, decisions, DecisionSubjects.Route, reference,
                    MoJson(await RecommendedAsync(parsed, states!, queueService, ct)), MoJson(parsed.MoCode), body.Reason, _ => $"/api/v1/route/{reference}", ct);
            })
            .RequireAuthorization(Policies.Doctor)
            .WithName("KeepRoute")
            .WithSummary("Оставить пациента в текущей организации с причиной — ответ на сигнал гражданина; решение уходит в журнал (Kind = keep)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesProblem(StatusCodes.Status403Forbidden).ProducesProblem(StatusCodes.Status404NotFound)
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
    }

    /// <summary>Рекомендация системы для журнала — самая быстрая альтернатива по модели; без модели рекомендацией
    /// остаётся текущая организация.</summary>
    private static async Task<string> RecommendedAsync(RoutePatientRef parsed, IReadOnlyList<QueueStateRow> states, QueueService queueService, CancellationToken ct)
    {
        var state = states.First(s => s.MoCode == parsed.MoCode && s.ProfileCode == parsed.ProfileCode);
        var alternatives = await TryAsync(() => queueService.AlternativesAsync(AlternativesRequest(state, 1), ct));
        return alternatives is { Items.Count: > 0 } ? alternatives.Items[0].Mo.MoCode : parsed.MoCode;
    }

    /// <summary>Персона гражданина: та же популяция и те же кэшированные прогнозы, что в рабочем списке врача
    /// (QueuePredictions) — гражданин один из пациентов списка. Сид — ИИН из клейма (не сохраняется, только хешируется),
    /// иначе учётная запись: реф не меняется при смене логина того же человека.</summary>
    private static async Task<(RoutePatientRef? Parsed, IReadOnlyList<QueueStateRow>? States, IResult? Problem)> ResolveCitizenAsync(
        string? regionKato, HttpContext http, IWorklistRepository worklist, IRefDataRepository refData, QueuePredictions predictions, CancellationToken ct)
    {
        var user = CurrentUser.From(http);
        var region = user.RegionKato ?? regionKato ?? DefaultRegion;
        var errors = new ValidationErrors().Kato("regionKato", region);
        if (errors.Any)
        {
            return (null, null, errors.Problem());
        }

        var states = await worklist.QueueStatesAsync(region, ct);
        var (byQueue, _) = await predictions.ForQueuesAsync(states, ct);
        var population = WorklistBuilder.Build(states, byQueue);
        if (population.Count == 0)
        {
            return (null, null, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Нет очередей в регионе",
                detail: $"в регионе {region} нет активных очередей на дату среза витрины"));
        }

        var excludedProfiles = RouteBuilder.ExcludedProfiles(await refData.ProfilesAsync(ct));
        RoutePatientRef.TryParse(RouteBuilder.PickPatientRef(population, user.Iin ?? user.Actor, excludedProfiles), out var parsed);
        return (parsed, states, null);
    }

    /// <summary>Разбор рефа, проверка региона врача (клейм region_kato сильнее рефа) и существования пациента в очереди.</summary>
    private static async Task<(RoutePatientRef? Parsed, IReadOnlyList<QueueStateRow>? States, IResult? Problem)> ResolveAsync(
        string patientRef, HttpContext http, IWorklistRepository worklist, CancellationToken ct)
    {
        if (!RoutePatientRef.TryParse(patientRef, out var parsed))
        {
            return (null, null, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Пациент не найден",
                detail: "ожидается реф вида SYN-регион-организация-профиль-NN"));
        }

        var scope = RegionAccess.RegionScope(CurrentUser.From(http));
        if (scope is not null && scope != parsed!.RegionKato)
        {
            return (null, null, Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Пациент другого региона",
                detail: "врач видит маршруты пациентов только своего региона"));
        }

        var states = await worklist.QueueStatesAsync(parsed!.RegionKato, ct);
        var state = states.FirstOrDefault(s => s.MoCode == parsed.MoCode && s.ProfileCode == parsed.ProfileCode);
        if (state is null || parsed.Index > WorklistBuilder.CountFor(state, states.Sum(s => s.QueueLen)))
        {
            return (null, null, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Пациент не найден",
                detail: "в этой очереди нет пациента с таким номером на дату среза витрины"));
        }

        return (parsed, states, null);
    }

    private static async Task<IResult> BuildAsync(
        RoutePatientRef parsed, IReadOnlyList<QueueStateRow> states, string audience, string lang,
        IRefDataRepository refData, IDecisionRepository decisions, QueueService queueService, CancellationToken ct)
    {
        var state = states.First(s => s.MoCode == parsed.MoCode && s.ProfileCode == parsed.ProfileCode);
        var predictTask = TryAsync(() => queueService.PredictAsync(PredictRequest(state), lang, ct));
        var alternativesTask = TryAsync(() => queueService.AlternativesAsync(AlternativesRequest(state, AlternativesLimit), ct));
        var decisionsTask = decisions.ListAsync(null, DecisionSubjects.Route, parsed.Format(), 1, DecisionsLimit, ct);
        var standardTask = refData.RouteStandardAsync(lang, ct);
        var profilesTask = refData.ProfilesAsync(ct);
        await Task.WhenAll(predictTask, alternativesTask, decisionsTask, standardTask, profilesTask);

        var prediction = predictTask.Result;
        var queuePrediction = prediction is null
            ? WorklistBuilder.Fallback(state)
            : new QueuePrediction(prediction.P50Days, prediction.P90Days, prediction.PRefusal, true);
        var item = WorklistBuilder.BuildItem(state, parsed.Index - 1, queuePrediction, WorklistBuilder.FastestP50(states, state.ProfileCode));
        var profileNames = profilesTask.Result.GroupBy(p => p.ProfileCode).ToDictionary(g => g.Key, g => g.First().Name);
        var route = RouteBuilder.Build(new RouteBuilder.Inputs(
            item, state, states, standardTask.Result, prediction, alternativesTask.Result, decisionsTask.Result.Items, profileNames, audience, lang,
            DateTimeOffset.UtcNow));
        return Results.Ok(route);
    }

    /// <summary>Категориальные признаки запроса неизвестны для синтетического пациента — не выдумываем диагноз (Icd10 = null),
    /// дата регистрации — срез витрины, как в рабочем списке.</summary>
    private static PredictRequestDto PredictRequest(QueueStateRow state) =>
        new(state.RegionKato, state.MoCode, state.ProfileCode, null, null, null, null, state.AsOf.ToString("yyyy-MM-dd"), null);

    private static AlternativesRequestDto AlternativesRequest(QueueStateRow state, int limit) =>
        new(state.RegionKato, state.MoCode, state.ProfileCode, null, null, null, null, state.AsOf.ToString("yyyy-MM-dd"), limit, null);

    /// <summary>Сервис моделей недоступен или организация не распознана — как в JournalEndpoints.PredictForQueuesAsync:
    /// маршрут строится по агрегатам витрины, а не отдаёт 503.</summary>
    private static async Task<T?> TryAsync<T>(Func<Task<T>> call) where T : class
    {
        try
        {
            return await call();
        }
        catch (Exception e) when (e is not OperationCanceledException)
        {
            return null;
        }
    }

    private static string MoJson(string moCode) => JsonSerializer.Serialize(new { moCode });
}
