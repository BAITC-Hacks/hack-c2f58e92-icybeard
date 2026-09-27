using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using static Darumen.Shared.Auth.RegionAccess;

namespace Darumen.Modules.Queue;

public static class QueueEndpoints
{
    private const int DefaultSeriesDays = 90;
    private const int DefaultOverloadedLimit = 20;
    private const int MaxOverloadedLimit = 200;

    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/queue").WithTags("Queue");

        group.MapPost("/predict", async (PredictRequestDto body, HttpRequest http, QueueService service, CancellationToken ct) =>
            {
                var errors = Validate(body);
                return errors.Any ? errors.Problem() : Results.Ok(await service.PredictAsync(body, Locale.From(http), ct));
            })
            .WithName("PredictWait")
            .WithSummary("Ожидание плановой госпитализации и риск отказа")
            .Produces<PredictResponseDto>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapPost("/alternatives", async (AlternativesRequestDto body, HttpContext http, IPermissionService permissions, QueueService service, CancellationToken ct) =>
            {
                // «где быстрее» по региону и профилю — часть сроков ожидания (wait.public, экран гражданина); с полями направления
                // (диагноз, цель, направившая организация) это уже ассистент направления врача — referral.assist
                if (IsReferralRequest(body) && await permissions.ScopeForAsync(http.User, Permissions.ReferralAssist, ct) == PermissionScope.None)
                {
                    return AccessProblems.Forbidden(AccessProblems.PermissionRequired, Permissions.ReferralAssist);
                }

                var errors = Validate(body.Base);
                return errors.Any ? errors.Problem() : Results.Ok(await service.AlternativesAsync(body, ct));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.WaitPublic, Permissions.ReferralAssist))
            .WithName("QueueAlternatives")
            .WithSummary("Организации того же региона и профиля с меньшим ожиданием (wait.public; с полями направления — referral.assist)")
            .ProducesProblem(StatusCodes.Status403Forbidden)
            .Produces<AlternativesResponseDto>()
            .ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/organizations/{moCode}", async (string moCode, string profileCode, int? days, HttpContext http, IQueueStateRepository repository, CancellationToken ct) =>
            {
                if (await OrgAccess.CheckAsync(http, moCode, Permissions.OrgCabinet) is { } denied)
                {
                    return denied;
                }

                var series = await repository.SeriesAsync(moCode, profileCode, days ?? DefaultSeriesDays, ct);
                return series is null ? Results.NotFound() : Results.Ok(series);
            })
            .RequireAuthorization(Permissions.Policy(Permissions.OrgCabinet))
            .WithName("QueueOrganizationSeries")
            .WithSummary("Ряд очереди и пропускной способности организации по профилю")
            .Produces<OrganizationSeriesDto>()
            .Produces(StatusCodes.Status404NotFound);

        group.MapGet("/overloaded", async (string? regionKato, string? profileCode, int? limit, HttpContext http, IQueueStateRepository repository, CancellationToken ct) =>
            {
                // роль, привязанная к региону (администратор организации, если ему открыли карту), видит только свой регион:
                // клейм region_kato сильнее параметра запроса
                regionKato = RegionScope(CurrentUser.From(http)) ?? regionKato;
                return Results.Ok(new { items = await repository.OverloadedAsync(regionKato, profileCode, Math.Clamp(limit ?? DefaultOverloadedLimit, 1, MaxOverloadedLimit), ct) });
            })
            .RequireAuthorization(Permissions.Policy(Permissions.GovMap))
            .WithName("QueueOverloaded")
            .WithSummary("Организации с нагрузкой (поток / госпитализации) больше 1, самые загруженные — первыми");
    }

    /// <summary>Запрос с признаками конкретного направления — ассистент врача, а не публичные сроки ожидания.</summary>
    internal static bool IsReferralRequest(AlternativesRequestDto body) =>
        !string.IsNullOrWhiteSpace(body.Icd10) || !string.IsNullOrWhiteSpace(body.ReferralPurpose) || !string.IsNullOrWhiteSpace(body.TerritorialType)
        || !string.IsNullOrWhiteSpace(body.FinanceSource) || !string.IsNullOrWhiteSpace(body.ReferringMoCode);

    internal static ValidationErrors Validate(PredictRequestDto body)
    {
        var errors = new ValidationErrors()
            .Require("profileCode", body.ProfileCode)
            .Kato("regionKato", body.RegionKato)
            .Date("registrationDate", body.RegistrationDate);
        if (string.IsNullOrWhiteSpace(body.RegionKato) && string.IsNullOrWhiteSpace(body.MoCode))
        {
            errors.Add("regionKato", "нужен regionKato или moCode");
        }

        return errors;
    }
}
