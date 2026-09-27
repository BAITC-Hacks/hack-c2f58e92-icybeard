using System.Data.Common;
using Dapper;
using Darumen.Shared.Api;
using Darumen.Shared.Data;

namespace Darumen.Shared.Auth;

public sealed class PostgresPermissionStore(IDbConnectionFactory db) : IPermissionStore
{
    private const string ChangeColumns =
        "id AS Id, at AS At, actor AS Actor, role AS Role, permission AS Permission, old_scope AS OldScope, new_scope AS NewScope, comment AS Comment";

    public async Task<IReadOnlyList<RoleRecord>> RolesAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<RoleRow>(new CommandDefinition(
            """
            SELECT key AS Key, title_ru AS TitleRu, title_kk AS TitleKk, description_ru AS DescriptionRu, description_kk AS DescriptionKk,
                   builtin AS Builtin, created_at AS CreatedAt
            FROM auth.roles ORDER BY builtin DESC, created_at, key
            """,
            cancellationToken: cancellationToken));
        return rows.Select(r => new RoleRecord(r.Key, r.TitleRu, r.TitleKk, r.DescriptionRu, r.DescriptionKk, r.Builtin, Utc(r.CreatedAt))).ToList();
    }

    public async Task<IReadOnlyList<RolePermission>> MatrixAsync(CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        var rows = await connection.QueryAsync<RolePermission>(new CommandDefinition(
            "SELECT role AS Role, permission AS Permission, scope AS Scope FROM auth.role_permissions ORDER BY role, permission",
            cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<IReadOnlyList<PermissionChangeRecord>> ApplyAsync(
        string role, IReadOnlyList<PermissionChange> changes, string actor, string? comment, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        var applied = new List<PermissionChangeRecord>();
        foreach (var change in changes)
        {
            var old = await connection.QueryFirstOrDefaultAsync<string?>(new CommandDefinition(
                "SELECT scope FROM auth.role_permissions WHERE role = @role AND permission = @permission FOR UPDATE",
                new { role, permission = change.Permission }, transaction, cancellationToken: cancellationToken));
            if (old == change.Scope)
            {
                continue;
            }

            await WriteScopeAsync(connection, transaction, role, change, cancellationToken);
            applied.Add(await LogAsync(connection, transaction, new LogEntry(actor, role, change.Permission, old, change.Scope, comment), cancellationToken));
        }

        await transaction.CommitAsync(cancellationToken);
        return applied;
    }

    public async Task<IReadOnlyList<PermissionChangeRecord>> CreateRoleAsync(RoleRecord role, string? copyFrom, string actor, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO auth.roles (key, title_ru, title_kk, description_ru, description_kk, builtin, created_at)
            VALUES (@Key, @TitleRu, @TitleKk, @DescriptionRu, @DescriptionKk, false, now())
            """,
            role, transaction, cancellationToken: cancellationToken));

        var seed = copyFrom is null
            ? []
            : (await connection.QueryAsync<RolePermission>(new CommandDefinition(
                "SELECT role AS Role, permission AS Permission, scope AS Scope FROM auth.role_permissions WHERE role = @copyFrom AND permission <> @adminRoles",
                new { copyFrom, adminRoles = Permissions.AdminRoles }, transaction, cancellationToken: cancellationToken))).ToList();
        if (seed.All(p => p.Permission != Permissions.WaitPublic))
        {
            seed.Add(new RolePermission(role.Key, Permissions.WaitPublic, PermissionScopes.All)); // wait.public не снимается ни с одной роли
        }

        var comment = copyFrom is null ? "роль создана" : $"роль создана копией {copyFrom}";
        var applied = new List<PermissionChangeRecord>();
        foreach (var permission in seed)
        {
            var change = new PermissionChange(permission.Permission, permission.Scope);
            await WriteScopeAsync(connection, transaction, role.Key, change, cancellationToken);
            applied.Add(await LogAsync(connection, transaction, new LogEntry(actor, role.Key, change.Permission, null, change.Scope, comment), cancellationToken));
        }

        await transaction.CommitAsync(cancellationToken);
        return applied;
    }

    public async Task<Paged<PermissionChangeRecord>> HistoryAsync(string? role, int page, int size, CancellationToken cancellationToken)
    {
        await using var connection = await db.OpenAsync(cancellationToken);
        const string where = "WHERE (@role IS NULL OR role = @role)";
        var parameters = new { role, size, offset = (page - 1) * size };
        var total = await connection.ExecuteScalarAsync<long>(new CommandDefinition(
            $"SELECT count(*) FROM auth.role_permission_changes {where}", parameters, cancellationToken: cancellationToken));
        var rows = await connection.QueryAsync<ChangeRow>(new CommandDefinition(
            $"SELECT {ChangeColumns} FROM auth.role_permission_changes {where} ORDER BY id DESC LIMIT @size OFFSET @offset",
            parameters, cancellationToken: cancellationToken));
        return new Paged<PermissionChangeRecord>(rows.Select(ToRecord).ToList(), page, size, total);
    }

    /// <summary>scope null — разрешение снимается (строка удаляется), иначе вставка или обновление охвата.</summary>
    private static Task WriteScopeAsync(DbConnection connection, DbTransaction transaction, string role, PermissionChange change, CancellationToken ct) =>
        change.Scope is null
            ? connection.ExecuteAsync(new CommandDefinition(
                "DELETE FROM auth.role_permissions WHERE role = @role AND permission = @permission",
                new { role, permission = change.Permission }, transaction, cancellationToken: ct))
            : connection.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO auth.role_permissions (role, permission, scope) VALUES (@role, @permission, @scope)
                ON CONFLICT (role, permission) DO UPDATE SET scope = excluded.scope
                """,
                new { role, permission = change.Permission, scope = change.Scope }, transaction, cancellationToken: ct));

    private static async Task<PermissionChangeRecord> LogAsync(DbConnection connection, DbTransaction transaction, LogEntry entry, CancellationToken ct)
    {
        var row = await connection.QuerySingleAsync<ChangeRow>(new CommandDefinition(
            $"""
            INSERT INTO auth.role_permission_changes (at, actor, role, permission, old_scope, new_scope, comment)
            VALUES (now(), @Actor, @Role, @Permission, @OldScope, @NewScope, @Comment)
            RETURNING {ChangeColumns}
            """,
            entry, transaction, cancellationToken: ct));
        return ToRecord(row);
    }

    private static PermissionChangeRecord ToRecord(ChangeRow r) =>
        new(r.Id, Utc(r.At), r.Actor, r.Role, r.Permission, r.OldScope, r.NewScope, r.Comment);

    private static DateTimeOffset Utc(DateTime at) => new(DateTime.SpecifyKind(at, DateTimeKind.Utc));

    private sealed record LogEntry(string Actor, string Role, string Permission, string? OldScope, string? NewScope, string? Comment);

    private sealed record RoleRow(string Key, string TitleRu, string TitleKk, string? DescriptionRu, string? DescriptionKk, bool Builtin, DateTime CreatedAt);

    private sealed record ChangeRow(long Id, DateTime At, string Actor, string Role, string Permission, string? OldScope, string? NewScope, string? Comment);
}
