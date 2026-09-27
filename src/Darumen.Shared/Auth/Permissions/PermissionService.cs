using System.Security.Claims;
using Darumen.Shared.Api;
using Microsoft.Extensions.Logging;

namespace Darumen.Shared.Auth;

/// <summary>Разрешения пользователя: объединение строк матрицы по его ролям (максимальный охват). Матрица кэшируется
/// на <see cref="CacheFor"/> и сбрасывается при изменении (<see cref="Invalidate"/>).</summary>
public interface IPermissionService
{
    /// <summary>Охват по матрице без учёта клейма mo_code: admin — All для любого кода.</summary>
    Task<PermissionScope> RawScopeAsync(ClaimsPrincipal user, string code, CancellationToken cancellationToken = default);

    /// <summary>Действующий охват: own без клейма mo_code — пустое разрешение (None).</summary>
    Task<PermissionScope> ScopeForAsync(ClaimsPrincipal user, string code, CancellationToken cancellationToken = default);

    /// <summary>Все действующие разрешения пользователя (для GET /me), в порядке каталога.</summary>
    Task<IReadOnlyList<(string Code, PermissionScope Scope)>> EffectiveAsync(ClaimsPrincipal user, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<RolePermission>> MatrixAsync(CancellationToken cancellationToken = default);

    void Invalidate();
}

public sealed class PermissionService(IPermissionStore store, TimeProvider time, ILogger<PermissionService> logger) : IPermissionService
{
    public static readonly TimeSpan CacheFor = TimeSpan.FromSeconds(30);
    /// <summary>Без Postgres действует матрица по умолчанию; повторная попытка чтения — не чаще раза в это время.</summary>
    private static readonly TimeSpan FallbackFor = TimeSpan.FromSeconds(5);

    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile Snapshot? _snapshot;

    public async Task<PermissionScope> RawScopeAsync(ClaimsPrincipal user, string code, CancellationToken cancellationToken = default)
    {
        var roles = RolesOf(user);
        if (roles.Contains(Roles.Admin))
        {
            return PermissionScope.All;
        }

        var snapshot = await SnapshotAsync(cancellationToken);
        var best = PermissionScope.None;
        foreach (var role in roles)
        {
            if (snapshot.ByRole.TryGetValue(role, out var grants) && grants.TryGetValue(code, out var scope) && scope > best)
            {
                best = scope;
            }
        }

        return best;
    }

    public async Task<PermissionScope> ScopeForAsync(ClaimsPrincipal user, string code, CancellationToken cancellationToken = default)
    {
        var raw = await RawScopeAsync(user, code, cancellationToken);
        return raw == PermissionScope.Own && string.IsNullOrWhiteSpace(CurrentUser.From(user).MoCode) ? PermissionScope.None : raw;
    }

    public async Task<IReadOnlyList<(string Code, PermissionScope Scope)>> EffectiveAsync(ClaimsPrincipal user, CancellationToken cancellationToken = default)
    {
        var result = new List<(string Code, PermissionScope Scope)>();
        foreach (var permission in PermissionCatalog.All)
        {
            var scope = await ScopeForAsync(user, permission.Code, cancellationToken);
            if (scope != PermissionScope.None)
            {
                result.Add((permission.Code, scope));
            }
        }

        return result;
    }

    public async Task<IReadOnlyList<RolePermission>> MatrixAsync(CancellationToken cancellationToken = default) =>
        (await SnapshotAsync(cancellationToken)).Rows;

    public void Invalidate() => _snapshot = null;

    private static IReadOnlyList<string> RolesOf(ClaimsPrincipal user) =>
        user.FindAll(ClaimTypes.Role).Select(c => Roles.Normalize(c.Value)).Distinct().ToList();

    private async Task<Snapshot> SnapshotAsync(CancellationToken cancellationToken)
    {
        var current = _snapshot;
        if (current is not null && time.GetUtcNow() < current.ExpiresAt)
        {
            return current;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            current = _snapshot;
            if (current is not null && time.GetUtcNow() < current.ExpiresAt)
            {
                return current;
            }

            _snapshot = await LoadAsync(current, cancellationToken);
            return _snapshot;
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<Snapshot> LoadAsync(Snapshot? previous, CancellationToken cancellationToken)
    {
        try
        {
            return Snapshot.From(await store.MatrixAsync(cancellationToken), time.GetUtcNow() + CacheFor);
        }
        catch (Exception exception) when (!cancellationToken.IsCancellationRequested)
        {
            // хранилище недоступно: последняя прочитанная матрица, а до первого чтения — матрица по умолчанию
            logger.LogWarning(exception, "Permission matrix was not loaded, using {Source}", previous is null ? "defaults" : "previous snapshot");
            return Snapshot.From(previous?.Rows ?? PermissionCatalog.DefaultMatrix, time.GetUtcNow() + FallbackFor);
        }
    }

    private sealed record Snapshot(IReadOnlyList<RolePermission> Rows, IReadOnlyDictionary<string, Dictionary<string, PermissionScope>> ByRole, DateTimeOffset ExpiresAt)
    {
        public static Snapshot From(IReadOnlyList<RolePermission> rows, DateTimeOffset expiresAt) => new(
            rows,
            rows.GroupBy(r => r.Role).ToDictionary(g => g.Key, g => g.ToDictionary(r => r.Permission, r => PermissionScopes.Parse(r.Scope))),
            expiresAt);
    }
}
