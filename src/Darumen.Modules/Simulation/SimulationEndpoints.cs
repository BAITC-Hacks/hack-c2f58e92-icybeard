using Darumen.Contracts.V1;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Darumen.Shared.Options;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Simulation;

public static class SimulationEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        api.MapPost("/simulate", async (SimulateRequestDto body, Contracts.V1.Simulation.SimulationClient client, IOptions<ModelServicesOptions> options, CancellationToken ct) =>
            {
                var errors = Validate(body.RegionKato, body.ProfileCode);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var scenario = body.Scenario ?? new ScenarioDto(null, null, null);
                var response = await client.SimulateAsync(new SimulateRequest
                {
                    Region = new RegionRef { Kato = body.RegionKato },
                    ProfileCode = body.ProfileCode,
                    CapacityDeltaPct = scenario.CapacityDeltaPct ?? 0,
                    RedirectSharePct = scenario.RedistributeSharePct ?? 0,
                    HorizonDays = scenario.HorizonDays ?? 0,
                    BedsDelta = scenario.BedsDelta ?? 0,
                }, deadline: Deadline(options), cancellationToken: ct);
                return Results.Ok(new SimulateResponseDto(
                    response.Organisations, new OutcomeDto(response.Baseline.MeanWaitDays), new OutcomeDto(response.Scenario.MeanWaitDays),
                    response.DeltaDays, [response.CiLow, response.CiHigh], response.Assumptions.ToList(), response.Model.ToDto(),
                    response.AdmissionsPerDay));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.GovSimulator))
            .WithTags("Simulation").WithName("Simulate").WithSummary("Сценарий «что если» для региона и профиля")
            .Produces<SimulateResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);

        api.MapPost("/redistribute", async (RedistributeRequestDto body, Contracts.V1.Simulation.SimulationClient client, IOptions<ModelServicesOptions> options, CancellationToken ct) =>
            {
                var errors = Validate(body.RegionKato, body.ProfileCode);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var constraints = body.Constraints ?? new ConstraintsDto(null, null, null);
                var response = await client.RedistributeAsync(new RedistributeRequest
                {
                    Region = new RegionRef { Kato = body.RegionKato },
                    ProfileCode = body.ProfileCode,
                    MaxShareMovedPct = constraints.MaxShareMovedPct ?? 0,
                    MaxDistanceKm = constraints.MaxDistanceKm ?? 0,
                    HorizonDays = constraints.HorizonDays ?? 0,
                }, deadline: Deadline(options), cancellationToken: ct);
                var moves = response.Moves.Select(m => new MoveDto(
                    ToDto(m.From), ToDto(m.To), m.ShareOfSourcePct, m.ArrivalsPerDay,
                    m.WaitFromBefore, m.WaitFromAfter, m.WaitToBefore, m.WaitToAfter)).ToList();
                return Results.Ok(new RedistributeResponseDto(
                    moves, response.TotalWaitDaysBefore, response.TotalWaitDaysAfter, response.TotalDeltaDays, response.HorizonDays, response.Model.ToDto()));
            })
            .RequireAuthorization(Permissions.Policy(Permissions.GovSimulator))
            .WithTags("Simulation").WithName("Redistribute").WithSummary("Жадное перераспределение направлений внутри региона и профиля")
            .Produces<RedistributeResponseDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
    }

    private static ValidationErrors Validate(string? regionKato, string? profileCode) =>
        new ValidationErrors().Require("regionKato", regionKato).Kato("regionKato", regionKato).Require("profileCode", profileCode);

    private static OrganizationRefDto ToDto(OrganizationRef org) => new(org.MoCode, org.Name, org.Region?.Kato ?? string.Empty);

    private static DateTime Deadline(IOptions<ModelServicesOptions> options) => DateTime.UtcNow.AddSeconds(options.Value.TimeoutSeconds);
}
