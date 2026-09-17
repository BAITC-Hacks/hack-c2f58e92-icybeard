using Darumen.Shared.Api;

namespace Darumen.Modules.Queue;

public sealed record PredictRequestDto(
    string? RegionKato, string? MoCode, string? ProfileCode, string? Icd10, string? ReferralPurpose,
    string? TerritorialType, string? FinanceSource, string? RegistrationDate, string? ReferringMoCode = null);

public sealed record QueueSnapshotDto(int Len, double? AgeP50, double ThroughputPerDay);

public sealed record PredictResponseDto(
    double P50Days, double P90Days, double PWithin30Days, double PRefusal, QueueSnapshotDto? Queue,
    ExplanationDto Explanation, ModelInfoDto Model, bool RefusalOrgInTraining);

public sealed record AlternativesRequestDto(
    string? RegionKato, string? MoCode, string? ProfileCode, string? Icd10, string? ReferralPurpose,
    string? TerritorialType, string? FinanceSource, string? RegistrationDate, int? Limit, double? MaxDistanceKm,
    string? ReferringMoCode = null)
{
    public PredictRequestDto Base => new(RegionKato, MoCode, ProfileCode, Icd10, ReferralPurpose, TerritorialType, FinanceSource, RegistrationDate, ReferringMoCode);
}

public sealed record OrganizationDto(string MoCode, string Name, string RegionKato);

public sealed record AlternativeDto(OrganizationDto Mo, double P50Days, double P90Days, double PRefusal, double DistanceKm);

public sealed record AlternativesResponseDto(IReadOnlyList<AlternativeDto> Items, ModelInfoDto Model);

public sealed record QueueDayDto(string Day, int Registered, int Hospitalized, int Refused, int QueueLen, double? QueueAgeP50);

public sealed record ThroughputDto(string Day, double ThroughputPerDay, double? RefusalRate4w, double? WaitP50Days, double? WaitP90Days);

public sealed record OrganizationSeriesDto(string MoCode, string ProfileCode, IReadOnlyList<QueueDayDto> Days, ThroughputDto? Throughput);
