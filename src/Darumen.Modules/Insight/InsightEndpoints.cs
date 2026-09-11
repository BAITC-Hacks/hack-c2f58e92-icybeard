using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Insight;

public static class InsightEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var group = api.MapGroup("/insight").WithTags("Insight").RequireAuthorization(Policies.ChiefOrRegulator);

        group.MapPost("/ask", async (AskRequestDto body, InsightService service, CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Require("question", body.Question).Kato("regionKato", body.RegionKato);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                if (!service.Available)
                {
                    return Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable, title: "Insight не настроен", detail: "Задайте DEEPSEEK_API_KEY (или Insight:ApiKey), чтобы включить вопросы к данным.");
                }

                return Results.Ok(await service.AskAsync(body.Question!, body.RegionKato, ct));
            })
            .WithName("InsightAsk").WithSummary("Вопрос к данным: ответ с цифрой, графиком и списком использованных инструментов")
            .Produces<AskResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity).ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        group.MapGet("/status", (InsightService service, Microsoft.Extensions.Options.IOptions<InsightOptions> options) =>
                Results.Ok(new { available = service.Available, provider = options.Value.Provider, model = options.Value.Model }))
            .WithName("InsightStatus").WithSummary("Настроен ли доступ к модели");
    }
}
