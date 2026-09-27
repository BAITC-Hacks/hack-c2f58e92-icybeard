using Darumen.Modules.Access.Identity;
using Darumen.Shared.Auth;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Access.Services;

/// <summary>Пользователь Keycloak с ролями приложения (chief → org_admin).</summary>
public sealed record DirectoryUser(IdentityUser Identity, IReadOnlyList<string> Roles)
{
    public string Id => Identity.Id;
    public string? MoCode => Identity.Attribute(IdentityAttributes.MoCode);
    public string? RegionKato => Identity.Attribute(IdentityAttributes.RegionKato);
    public string? Specialty => Identity.Attribute(IdentityAttributes.Specialty);
    public string? Position => Identity.Attribute(IdentityAttributes.Position);
    public string Via => Identity.Attribute(IdentityAttributes.Via) ?? "password";
    public bool Has(string role) => Roles.Contains(role);
}

/// <summary>Каталог пользователей реалма: пользователи и участники каждой роли приложения (роли из auth.roles, плюс legacy chief).</summary>
public sealed class UserDirectory(IIdentityAdmin identity, IPermissionStore permissions, IOptions<KeycloakAdminOptions> options, ILogger<UserDirectory> logger)
{
    public async Task<IReadOnlyList<DirectoryUser>> AllAsync(CancellationToken cancellationToken)
    {
        var max = options.Value.MaxUsers;
        var users = await identity.UsersAsync(max, cancellationToken);
        var rolesByUser = new Dictionary<string, HashSet<string>>();
        foreach (var role in await RoleKeysAsync(cancellationToken))
        {
            foreach (var id in await identity.RoleMembersAsync(role, max, cancellationToken))
            {
                if (!rolesByUser.TryGetValue(id, out var set))
                {
                    set = [];
                    rolesByUser[id] = set;
                }

                set.Add(Roles.Normalize(role));
            }
        }

        return users.Select(u => new DirectoryUser(u, Ordered(rolesByUser.GetValueOrDefault(u.Id) ?? []))).ToList();
    }

    public async Task<DirectoryUser?> FindAsync(string id, CancellationToken cancellationToken)
    {
        var user = await identity.UserAsync(id, cancellationToken);
        if (user is null)
        {
            return null;
        }

        var roles = (await identity.UserRolesAsync(id, cancellationToken)).Where(Roles.IsApplicationRole).Select(Roles.Normalize).ToHashSet();
        return new DirectoryUser(user, Ordered(roles));
    }

    /// <summary>Ключи ролей приложения; без Postgres — встроенные роли.</summary>
    public async Task<IReadOnlyList<string>> RoleKeysAsync(CancellationToken cancellationToken)
    {
        try
        {
            return (await permissions.RolesAsync(cancellationToken)).Select(r => r.Key).Append(Roles.LegacyChief).Distinct().ToList();
        }
        catch (Exception exception) when (!cancellationToken.IsCancellationRequested && exception is not IdentityUnavailableException)
        {
            logger.LogWarning(exception, "Roles were not read from auth.roles, using built-in roles");
            return PermissionCatalog.BuiltinRoles.Select(r => r.Key).Append(Roles.LegacyChief).ToList();
        }
    }

    private static List<string> Ordered(IEnumerable<string> roles) =>
        roles.OrderBy(r => Array.IndexOf(Roles.All, r) is var i && i < 0 ? int.MaxValue : i).ThenBy(r => r, StringComparer.Ordinal).ToList();
}
