using Darumen.Contracts.V1;
using Darumen.Modules.Queue;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Darumen.Shared.Messaging;

namespace Darumen.Modules.Journal;

public static class JournalEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/journal").WithTags("Journal").RequireAuthorization(Policies.DoctorOrRegulator);

        group.MapPost("/decisions", async (DecisionRequestDto body, HttpContext http, IDecisionRepository repository, CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Require("subject", body.Subject).Require("subjectId", body.SubjectId);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var user = CurrentUser.From(http);
                var key = http.Request.Headers.TryGetValue("Idempotency-Key", out var k) && !string.IsNullOrWhiteSpace(k) ? k.ToString() : null;
                var (decision, created) = await repository.RecordAsync(
                    new NewDecision(user.Actor, user.Role, body.Subject!, body.SubjectId!, body.Recommended?.GetRawText(), body.Chosen?.GetRawText(), body.Reason, key),
                    dto => new DecisionRecorded
                    {
                        Meta = Events.Meta(),
                        DecisionId = dto.DecisionId.ToString(),
                        ActorRole = user.Role,
                        Subject = body.Subject!,
                        Recommended = body.Recommended?.GetRawText() ?? string.Empty,
                        Chosen = body.Chosen?.GetRawText() ?? string.Empty,
                        Reason = body.Reason ?? string.Empty,
                    },
                    ct);

                var payload = new DecisionCreatedDto(decision.DecisionId, decision.RecordedAt);
                return created ? Results.Created($"/api/v1/journal/decisions/{decision.DecisionId}", payload) : Results.Ok(payload);
            })
            .WithName("RecordDecision").WithSummary("Записать решение человека (рекомендация и выбор)")
            .Produces<DecisionCreatedDto>(StatusCodes.Status201Created).Produces<DecisionCreatedDto>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/decisions", async (string? actor, string? subject, int? page, int? size, HttpContext http, IDecisionRepository repository, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                var who = actor == "me" ? CurrentUser.From(http).Actor : actor;
                return Results.Ok(await repository.ListAsync(who, subject, p, s, ct));
            })
            .WithName("Decisions").WithSummary("Журнал решений").Produces<Paged<DecisionDto>>();

        group.MapGet("/worklist", async (string? regionKato, string? flag, HttpContext http, IWorklistRepository repository, QueueService queueService, CancellationToken ct) =>
            {
                var user = CurrentUser.From(http);
                var region = regionKato ?? user.RegionKato ?? "75";
                var states = await repository.QueueStatesAsync(region, ct);
                var asOf = states.Count > 0 ? states[0].AsOf.ToString("yyyy-MM-dd") : string.Empty;
                var (predictions, modelBacked) = await PredictForQueuesAsync(states, queueService, ct);
                return Results.Ok(new WorklistResponseDto(WorklistBuilder.Build(states, predictions, flag), true, asOf, region, modelBacked));
            })
            .RequireAuthorization(Policies.Doctor)
            .WithName("Worklist").WithSummary("Рабочий список врача: синтетические пациенты на реальных очередях региона").Produces<WorklistResponseDto>();

        group.MapGet("/audit", async (string? actor, int? page, int? size, IAuditRepository repository, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                return Results.Ok(await repository.ListAsync(actor, p, s, ct));
            })
            .RequireAuthorization(Policies.Regulator)
            .WithName("Audit").WithSummary("Журнал аудита запросов врачей и регуляторов").Produces<Paged<AuditEntryDto>>();
    }

    /// <summary>3.6: один прогноз модели на очередь (mo_code, profile_code), не на синтетического пациента —
    /// той же очереди соответствует несколько строк рабочего списка, им не нужно по отдельному вызову gRPC каждой
    /// (см. WorklistBuilder.Build). Категориальные признаки запроса неизвестны для синтетических пациентов —
    /// оставлены пустыми (не выдумываем диагноз), дата регистрации — дата среза витрины, чтобы модель не увидела
    /// признаки календаря за пределами обучения. Сервис моделей недоступен для конкретной очереди — WorklistBuilder
    /// сам считает по агрегатам витрины (см. QueuePrediction.FromModel), рабочий список не падает целиком.</summary>
    private static async Task<(IReadOnlyDictionary<(string MoCode, string ProfileCode), QueuePrediction> Predictions, bool ModelBacked)> PredictForQueuesAsync(
        IReadOnlyList<QueueStateRow> states, QueueService queueService, CancellationToken ct)
    {
        var queues = states.Select(s => (s.RegionKato, s.MoCode, s.ProfileCode, AsOf: s.AsOf)).Distinct().ToList();
        var results = await Task.WhenAll(queues.Select(async q =>
        {
            try
            {
                var request = new PredictRequestDto(q.RegionKato, q.MoCode, q.ProfileCode, null, null, null, null, q.AsOf.ToString("yyyy-MM-dd"), null);
                var prediction = await queueService.PredictAsync(request, "ru", ct);
                return ((q.MoCode, q.ProfileCode), Prediction: (QueuePrediction?)new QueuePrediction(prediction.P50Days, prediction.P90Days, prediction.PRefusal, true));
            }
            catch
            {
                // сервис моделей недоступен или организация/профиль не распознаны — WorklistBuilder откатится на агрегаты витрины
                return ((q.MoCode, q.ProfileCode), Prediction: (QueuePrediction?)null);
            }
        }));
        var predictions = results.Where(r => r.Prediction is not null).ToDictionary(r => r.Item1, r => r.Prediction!);
        return (predictions, predictions.Count > 0);
    }
}
