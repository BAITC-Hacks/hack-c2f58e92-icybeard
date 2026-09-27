using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Medicines;

public static class MedicinesEndpoints
{
    private const int DefaultLimit = 50;

    public static void Map(IEndpointRouteBuilder api)
    {
        // проверка рецепта и списки МНН — разрешение medicines.check (гражданин, врач); пример на странице входа — GET /public/login-examples
        var group = api.MapGroup("/medicines").WithTags("Medicines").RequireAuthorization(Permissions.Policy(Permissions.MedicinesCheck));

        group.MapPost("/check", async (CheckRequestDto body, MedicinesService service, CancellationToken ct) =>
            {
                var errors = new ValidationErrors().Kato("regionKato", body.RegionKato);
                if (string.IsNullOrWhiteSpace(body.MnnId) && string.IsNullOrWhiteSpace(body.NosologyId))
                {
                    errors.Add("nosologyId", "нужен nosologyId или mnnId");
                }

                return errors.Any ? errors.Problem() : Results.Ok(await service.CheckAsync(body, ct));
            })
            .WithName("MedicinesCheck").WithSummary("Покрытие, сроки обеспечения и сигнал дефицита для рецепта")
            .Produces<CheckResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        group.MapGet("/nosologies", async (int? limit, IMedicinesRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.NosologiesAsync(Math.Clamp(limit ?? DefaultLimit, 1, 500), ct) }))
            .WithName("Nosologies").WithSummary("Нозологии по объёму выписанных рецептов за год");

        group.MapGet("/mnn", async (string nosologyId, int? limit, IMedicinesRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.MnnAsync(nosologyId, Math.Clamp(limit ?? DefaultLimit, 1, 500), ct) }))
            .WithName("NosologyMnn").WithSummary("МНН, выписываемые при нозологии");

        group.MapGet("/mnn/top", async (int? limit, IMedicinesRepository repository, CancellationToken ct) =>
                Results.Ok(new { items = await repository.TopMnnAsync(Math.Clamp(limit ?? 50, 1, 200), ct) }))
            .WithName("TopMnn").WithSummary("Топ-N МНН по объёму выписанных рецептов за год по всем нозологиям (5.7 C, для прогноза спроса)");
    }
}
