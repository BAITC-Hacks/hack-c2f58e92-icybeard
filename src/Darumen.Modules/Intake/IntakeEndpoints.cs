using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Intake;

public static class IntakeEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        api.MapGet("/intake/batches", async (string? status, string? dataset, int? page, int? size, IIntakeRepository repository, CancellationToken ct) =>
            {
                var (p, s) = Paging.Normalize(page, size);
                return Results.Ok(await repository.BatchesAsync(status, dataset, p, s, ct));
            })
            .RequireAuthorization(Policies.Steward)
            .WithTags("Intake").WithName("IntakeBatches").WithSummary("Партии загрузки данных, пришедшие событиями из Data Intake Fabric")
            .Produces<Paged<BatchDto>>();
    }
}
