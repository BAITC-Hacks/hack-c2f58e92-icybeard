using Darumen.Shared.Api;

namespace Darumen.Modules.Simulation;

public sealed record ScenarioDto(double? CapacityDeltaPct, double? RedistributeSharePct, int? HorizonDays);

public sealed record SimulateRequestDto(string? RegionKato, string? ProfileCode, ScenarioDto? Scenario);

public sealed record OutcomeDto(double MeanWaitDays);

public sealed record SimulateResponseDto(
    int Organisations, OutcomeDto Baseline, OutcomeDto Scenario, double DeltaDays, double[] Ci,
    IReadOnlyList<string> Assumptions, ModelInfoDto Model);

public sealed record ConstraintsDto(double? MaxDistanceKm, double? MaxShareMovedPct, int? HorizonDays);

public sealed record RedistributeRequestDto(string? RegionKato, string? ProfileCode, ConstraintsDto? Constraints);

public sealed record OrganizationRefDto(string MoCode, string Name, string RegionKato);

public sealed record MoveDto(
    OrganizationRefDto FromMo, OrganizationRefDto ToMo, double SharePct, double ArrivalsPerDay,
    double WaitFromBefore, double WaitFromAfter, double WaitToBefore, double WaitToAfter);

public sealed record RedistributeResponseDto(
    IReadOnlyList<MoveDto> Moves, double TotalWaitDaysBefore, double TotalWaitDaysAfter, double TotalDeltaDays,
    int HorizonDays, ModelInfoDto Model);
