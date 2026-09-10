namespace Darumen.Shared.Api;

public sealed record ModelInfoDto(string Name, string Version, string TrainedThrough);

public sealed record FactorDto(string Name, double Contribution, string Text);

public sealed record ExplanationDto(string Summary, IReadOnlyList<FactorDto> Factors);

public sealed record Paged<T>(IReadOnlyList<T> Items, int Page, int Size, long Total);

public static class Paging
{
    public const int DefaultSize = 50;
    public const int MaxSize = 500;

    public static (int Page, int Size) Normalize(int? page, int? size) =>
        (Math.Max(page ?? 1, 1), Math.Clamp(size ?? DefaultSize, 1, MaxSize));
}
