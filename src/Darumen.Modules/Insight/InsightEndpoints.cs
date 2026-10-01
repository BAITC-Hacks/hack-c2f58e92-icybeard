using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Insight;

public static class InsightEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/insight").WithTags("Insight").RequireAuthorization(Permissions.Policy(Permissions.InsightAsk));

        group.MapPost("/ask", async (AskRequestDto body, InsightService service, CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Require("question", body.Question).Kato("regionKato", body.RegionKato);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                if (!service.Available)
                {
                    return Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable, title: "Insight не настроен", detail: "Задайте ключ провайдера (DEEPSEEK_API_KEY или Insight:ApiKey) либо провайдера ollama без ключа.");
                }

                try
                {
                    return Results.Ok(await service.AskAsync(body.Question!, body.RegionKato, ct));
                }
                catch (InsightUnavailableException exception)
                {
                    return Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable, title: "Модель недоступна", detail: exception.Message);
                }
            })
            .RequireRateLimiting(RateLimits.ModelCalls)
            .WithName("InsightAsk").WithSummary("Вопрос к данным: ответ с цифрой, графиком и списком использованных инструментов")
            .Produces<AskResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity)
            .ProducesProblem(StatusCodes.Status503ServiceUnavailable).Produces(StatusCodes.Status429TooManyRequests);

        group.MapGet("/status", async (InsightService service, Microsoft.Extensions.Options.IOptions<InsightOptions> options, CancellationToken ct) =>
            {
                var available = service.Available;
                var reachable = available ? await service.ProbeAsync(ct) : (bool?)null;
                return Results.Ok(new { available, reachable, provider = options.Value.Provider, model = options.Value.Model });
            })
            .WithName("InsightStatus").WithSummary("Настроен ли доступ к модели и отвечает ли локальная модель (reachable; null — не проверялось)");

        group.MapGet("/reports", async (string? month, string? profileCode, string? format, HttpRequest http,
                InsightReportService reports, CancellationToken ct) =>
            {
                var kind = format == "xlsx" ? "xlsx" : "pdf";
                var report = await reports.BuildAsync(month, profileCode, kind, Locale.From(http), ct);
                return report is null
                    ? Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Отчёт не собран",
                        detail: "индекс не рассчитан или месяц вне доступных")
                    : Results.File(report.Content, report.ContentType, report.FileName);
            })
            .WithName("InsightReports").WithSummary("Отчёт по индексу доступности за месяц: format=pdf|xlsx")
            .Produces(StatusCodes.Status200OK).ProducesProblem(StatusCodes.Status404NotFound);
    }
}
