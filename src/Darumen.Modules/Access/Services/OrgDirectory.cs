using Darumen.Modules.RefData;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace Darumen.Modules.Access.Services;

/// <summary>Справочник организаций (refdata.mo_registry) по коду, кэш на час: названия в /me, пользователях и организациях.</summary>
public sealed class OrgDirectory(IRefDataRepository refData, IMemoryCache cache, ILogger<OrgDirectory> logger)
{
    private const string CacheKey = "access-org-directory";
    private const int MaxOrganizations = 20_000;
    private static readonly TimeSpan CacheFor = TimeSpan.FromHours(1);

    public async Task<IReadOnlyDictionary<string, OrganizationItemDto>> AllAsync(CancellationToken cancellationToken)
    {
        if (cache.TryGetValue(CacheKey, out IReadOnlyDictionary<string, OrganizationItemDto>? cached) && cached is not null)
        {
            return cached;
        }

        try
        {
            var items = await refData.OrganizationsAsync(null, null, null, MaxOrganizations, cancellationToken);
            var byCode = items.GroupBy(o => o.MoCode, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);
            cache.Set(CacheKey, (IReadOnlyDictionary<string, OrganizationItemDto>)byCode, CacheFor);
            return byCode;
        }
        catch (Exception exception) when (!cancellationToken.IsCancellationRequested)
        {
            // без справочника названия просто не подставляются; кэш не заполняется, чтобы повторить при следующем запросе
            logger.LogWarning(exception, "Organization registry is unavailable");
            return new Dictionary<string, OrganizationItemDto>();
        }
    }

    public async Task<string?> NameAsync(string? moCode, CancellationToken cancellationToken) =>
        moCode is null ? null : (await AllAsync(cancellationToken)).GetValueOrDefault(moCode)?.Name;
}
