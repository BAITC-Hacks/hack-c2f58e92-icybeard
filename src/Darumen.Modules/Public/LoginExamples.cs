using Darumen.Modules.Medicines;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Public;

public sealed record LoginWaitExampleDto(string RegionKato, string RegionName, string ProfileCode, string ProfileName, double P50Days, double P90Days, double Within30);

public sealed record LoginRxExampleDto(string Mnn, bool Covered, double? FillP50, double? FillP90);

/// <summary>Пример-карточки страницы входа: ожидание (регион · профиль, p50/p90, доля за 30 дней) и одно МНН с покрытием
/// и сроками обеспечения. Часть без данных — null, страница входа остаётся страницей входа.</summary>
public sealed record LoginExamplesDto(LoginWaitExampleDto? Wait, LoginRxExampleDto? Rx);

public sealed class LoginExamplesOptions
{
    public const string Section = "Public:LoginExamples";

    public string RegionKato { get; set; } = "75";

    /// <summary>Профиль койки; без кода — первый профиль, в названии которого есть ProfileHint.</summary>
    public string? ProfileCode { get; set; }

    public string ProfileHint { get; set; } = "фтальм";
}

/// <summary>Те же сервисы, что раньше дергал веб на странице входа (прогноз ожидания и проверка рецепта), одним анонимным
/// запросом. Полный ответ кэшируется на час, неполный (модели или витрины недоступны) — на минуту.</summary>
public sealed class LoginExamplesService(
    QueueService queue, MedicinesService medicines, IMedicinesRepository medicinesRepository, IRefDataRepository refData, IMemoryCache cache,
    IOptions<LoginExamplesOptions> options, ILogger<LoginExamplesService> logger)
{
    public static readonly TimeSpan CacheFor = TimeSpan.FromHours(1);
    private static readonly TimeSpan PartialCacheFor = TimeSpan.FromMinutes(1);

    public async Task<LoginExamplesDto> GetAsync(string lang, CancellationToken ct)
    {
        var key = $"login-examples|{lang}";
        if (cache.TryGetValue(key, out LoginExamplesDto? cached) && cached is not null)
        {
            return cached;
        }

        var result = new LoginExamplesDto(await TryAsync(() => WaitAsync(lang, ct)), await TryAsync(() => RxAsync(ct)));
        cache.Set(key, result, result.Wait is not null && result.Rx is not null ? CacheFor : PartialCacheFor);
        return result;
    }

    private async Task<LoginWaitExampleDto?> WaitAsync(string lang, CancellationToken ct)
    {
        var settings = options.Value;
        var profiles = await refData.ProfilesAsync(ct);
        var profile = settings.ProfileCode is not null
            ? profiles.FirstOrDefault(p => p.ProfileCode == settings.ProfileCode)
            : profiles.FirstOrDefault(p => p.Name.Contains(settings.ProfileHint, StringComparison.OrdinalIgnoreCase)) ?? profiles.FirstOrDefault();
        if (profile is null)
        {
            return null;
        }

        var region = (await refData.RegionsAsync(lang, ct)).FirstOrDefault(r => r.RegionKato == settings.RegionKato);
        var prediction = await queue.PredictAsync(new PredictRequestDto(settings.RegionKato, null, profile.ProfileCode, null, null, null, null, null), lang, ct);
        return new LoginWaitExampleDto(settings.RegionKato, region?.Name ?? settings.RegionKato, profile.ProfileCode, profile.Name,
            prediction.P50Days, prediction.P90Days, prediction.PWithin30Days);
    }

    private async Task<LoginRxExampleDto?> RxAsync(CancellationToken ct)
    {
        var top = (await medicinesRepository.TopMnnAsync(1, ct)).FirstOrDefault();
        if (top is null)
        {
            return null;
        }

        var check = await medicines.CheckAsync(new CheckRequestDto(top.MnnId, top.NosologyId, null), ct);
        return new LoginRxExampleDto(top.MnnId, check.Covered, check.FillDaysP50, check.FillDaysP90);
    }

    private async Task<T?> TryAsync<T>(Func<Task<T?>> call) where T : class
    {
        try
        {
            return await call();
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            logger.LogWarning(exception, "Login example part is unavailable");
            return null;
        }
    }
}
