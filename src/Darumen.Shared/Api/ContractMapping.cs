using Darumen.Contracts.V1;

namespace Darumen.Shared.Api;

public static class ContractMapping
{
    public static ModelInfoDto ToDto(this ModelInfo model) => new(model.Name, model.Version, model.TrainedThrough);

    public static ExplanationDto ToDto(this Explanation explanation, string lang)
    {
        var kk = lang == Locale.Kk;
        return new ExplanationDto(
            kk ? explanation.SummaryKz : explanation.SummaryRu,
            explanation.Factors.Select(f => new FactorDto(f.Name, f.Contribution, kk ? f.TextKz : f.TextRu)).ToList());
    }
}
