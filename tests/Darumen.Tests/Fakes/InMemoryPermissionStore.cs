using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Tests.Fakes;

/// <summary>Матрица ролей в памяти с тем же сидом, что миграция AuthRbac (PermissionCatalog.DefaultMatrix).</summary>
public sealed class InMemoryPermissionStore : IPermissionStore
{
    private readonly Lock _gate = new();
    private readonly List<RoleRecord> _roles = PermissionCatalog.BuiltinRoles
        .Select(r => new RoleRecord(r.Key, r.TitleRu, r.TitleKk, r.DescriptionRu, r.DescriptionKk, true, DateTimeOffset.UtcNow)).ToList();
    private readonly Dictionary<(string Role, string Permission), string> _matrix = PermissionCatalog.DefaultMatrix.ToDictionary(r => (r.Role, r.Permission), r => r.Scope);
    private readonly List<PermissionChangeRecord> _changes = [];

    public int MatrixReads { get; private set; }

    public Task<IReadOnlyList<RoleRecord>> RolesAsync(CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            return Task.FromResult<IReadOnlyList<RoleRecord>>(_roles.ToList());
        }
    }

    public Task<IReadOnlyList<RolePermission>> MatrixAsync(CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            MatrixReads++;
            return Task.FromResult<IReadOnlyList<RolePermission>>(_matrix.Select(m => new RolePermission(m.Key.Role, m.Key.Permission, m.Value)).ToList());
        }
    }

    public Task<IReadOnlyList<PermissionChangeRecord>> ApplyAsync(string role, IReadOnlyList<PermissionChange> changes, string actor, string? comment, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            var applied = new List<PermissionChangeRecord>();
            foreach (var change in changes)
            {
                var old = _matrix.GetValueOrDefault((role, change.Permission));
                if (old == change.Scope)
                {
                    continue;
                }

                Write(role, change);
                applied.Add(Log(actor, role, change.Permission, old, change.Scope, comment));
            }

            return Task.FromResult<IReadOnlyList<PermissionChangeRecord>>(applied);
        }
    }

    public Task<IReadOnlyList<PermissionChangeRecord>> CreateRoleAsync(RoleRecord role, string? copyFrom, string actor, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            _roles.Add(role);
            var seed = _matrix.Where(m => m.Key.Role == copyFrom && m.Key.Permission != Permissions.AdminRoles)
                .Select(m => new PermissionChange(m.Key.Permission, m.Value)).ToList();
            if (seed.All(s => s.Permission != Permissions.WaitPublic))
            {
                seed.Add(new PermissionChange(Permissions.WaitPublic, PermissionScopes.All));
            }

            var applied = seed.Select(s =>
            {
                Write(role.Key, s);
                return Log(actor, role.Key, s.Permission, null, s.Scope, "роль создана");
            }).ToList();
            return Task.FromResult<IReadOnlyList<PermissionChangeRecord>>(applied);
        }
    }

    public Task<Paged<PermissionChangeRecord>> HistoryAsync(string? role, int page, int size, CancellationToken cancellationToken)
    {
        lock (_gate)
        {
            var items = _changes.Where(c => role is null || c.Role == role).OrderByDescending(c => c.Id).ToList();
            return Task.FromResult(new Paged<PermissionChangeRecord>(items.Skip((page - 1) * size).Take(size).ToList(), page, size, items.Count));
        }
    }

    private void Write(string role, PermissionChange change)
    {
        if (change.Scope is null)
        {
            _matrix.Remove((role, change.Permission));
        }
        else
        {
            _matrix[(role, change.Permission)] = change.Scope;
        }
    }

    private PermissionChangeRecord Log(string actor, string role, string permission, string? oldScope, string? newScope, string? comment)
    {
        var record = new PermissionChangeRecord(_changes.Count + 1, DateTimeOffset.UtcNow, actor, role, permission, oldScope, newScope, comment);
        _changes.Add(record);
        return record;
    }
}
