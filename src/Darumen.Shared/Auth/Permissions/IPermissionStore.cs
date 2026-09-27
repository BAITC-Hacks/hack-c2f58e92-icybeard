using Darumen.Shared.Api;

namespace Darumen.Shared.Auth;

public sealed record RoleRecord(string Key, string TitleRu, string TitleKk, string? DescriptionRu, string? DescriptionKk, bool Builtin, DateTimeOffset CreatedAt);

public sealed record PermissionChange(string Permission, string? Scope);

public sealed record PermissionChangeRecord(
    long Id, DateTimeOffset At, string Actor, string Role, string Permission, string? OldScope, string? NewScope, string? Comment);

/// <summary>Хранилище ролей и матрицы разрешений (схема auth). Изменения пишутся в role_permission_changes той же транзакцией.</summary>
public interface IPermissionStore
{
    Task<IReadOnlyList<RoleRecord>> RolesAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<RolePermission>> MatrixAsync(CancellationToken cancellationToken);

    /// <summary>Применяет изменения роли (scope null — снять разрешение); возвращает только реально изменившиеся строки.</summary>
    Task<IReadOnlyList<PermissionChangeRecord>> ApplyAsync(
        string role, IReadOnlyList<PermissionChange> changes, string actor, string? comment, CancellationToken cancellationToken);

    /// <summary>Создаёт роль; copyFrom — роль-образец, её строки матрицы копируются (кроме admin.roles).</summary>
    Task<IReadOnlyList<PermissionChangeRecord>> CreateRoleAsync(RoleRecord role, string? copyFrom, string actor, CancellationToken cancellationToken);

    Task<Paged<PermissionChangeRecord>> HistoryAsync(string? role, int page, int size, CancellationToken cancellationToken);
}
