using Darumen.Contracts.V1;
using Darumen.Shared.Api;
using Darumen.Shared.Options;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Queue;

/// <summary>Оркестрация вызовов Queue Intelligence (gRPC) и витрины состояния очереди.</summary>
public sealed class QueueService(
    QueueIntelligence.QueueIntelligenceClient client,
    IQueueStateRepository states,
    IOptions<ModelServicesOptions> options)
{
    public async Task<PredictResponseDto> PredictAsync(PredictRequestDto dto, string lang, CancellationToken cancellationToken)
    {
        var request = ToProto(dto);
        var deadline = Deadline();
        var waitCall = client.PredictWaitAsync(request, deadline: deadline, cancellationToken: cancellationToken);
        var refusalCall = client.PredictRefusalAsync(request, deadline: deadline, cancellationToken: cancellationToken);
        var wait = await waitCall;
        var refusal = await refusalCall;
        var snapshot = string.IsNullOrWhiteSpace(dto.MoCode)
            ? null
            : await states.SnapshotAsync(dto.MoCode, dto.ProfileCode!, cancellationToken);
        return new PredictResponseDto(
            wait.P50Days, wait.P90Days, wait.PWithin30Days, refusal.PRefusal, snapshot,
            wait.Explanation.ToDto(lang), wait.Model.ToDto(), refusal.OrgInTraining);
    }

    public async Task<AlternativesResponseDto> AlternativesAsync(AlternativesRequestDto dto, CancellationToken cancellationToken)
    {
        var response = await client.AlternativesAsync(
            new AlternativesRequest { Base = ToProto(dto.Base), Limit = dto.Limit ?? 0, MaxDistanceKm = dto.MaxDistanceKm ?? 0 },
            deadline: Deadline(), cancellationToken: cancellationToken);
        var items = response.Alternatives
            .Select(a => new AlternativeDto(
                new OrganizationDto(a.Organization.MoCode, a.Organization.Name, a.Organization.Region?.Kato ?? string.Empty),
                a.P50Days, a.P90Days, a.PRefusal, a.DistanceKm))
            .ToList();
        return new AlternativesResponseDto(items, response.Model.ToDto());
    }

    internal static PredictWaitRequest ToProto(PredictRequestDto dto) => new()
    {
        Region = new RegionRef { Kato = dto.RegionKato ?? string.Empty },
        MoCode = dto.MoCode ?? string.Empty,
        ProfileCode = dto.ProfileCode ?? string.Empty,
        Icd10 = dto.Icd10 ?? string.Empty,
        ReferralPurpose = dto.ReferralPurpose ?? string.Empty,
        TerritorialType = dto.TerritorialType ?? string.Empty,
        FinanceSource = dto.FinanceSource ?? string.Empty,
        RegistrationDate = dto.RegistrationDate ?? string.Empty,
    };

    private DateTime Deadline() => DateTime.UtcNow.AddSeconds(options.Value.TimeoutSeconds);
}
