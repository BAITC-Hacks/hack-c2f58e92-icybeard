using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Services;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Организации (admin.orgs): справочник + пользователи по атрибуту mo_code + подключение (есть данные очередей) +
/// свежесть загрузок по наборам; администраторы организации из Keycloak.</summary>
public static class AdminOrgEndpoints
{
    public const string Connected = "connected";
    public const string NoData = "no_data";
    private const int ApplicationsPerOrganization = 20;

    public static void Map(IEndpointRouteBuilder api)
    {
        var orgs = api.MapGroup("/admin/orgs").WithTags("Admin").RequireAuthorization(Permissions.Policy(Permissions.AdminOrgs));

        orgs.MapGet("", async (string? regionKato, string? type, string? status, string? q, int? page, int? size, OrgDirectory directory,
                IOrgDataStatus dataStatus, UserDirectory users, CancellationToken ct) =>
            {
                var candidates = (await directory.AllAsync(ct)).Values
                    .Where(o => (regionKato is null || o.RegionKato == regionKato) && (type is null || o.MoType == type)
                                && (q is null || o.Name.Contains(q, StringComparison.OrdinalIgnoreCase) || o.MoCode.Equals(q, StringComparison.OrdinalIgnoreCase)))
                    .ToList();
                var connected = await dataStatus.ConnectedAsync(candidates.Select(o => o.MoCode).ToList(), ct);
                var filtered = candidates.Where(o => status is null || StatusOf(o, connected) == status)
                    .OrderBy(o => o.RegionKato, StringComparer.Ordinal).ThenBy(o => o.Name, StringComparer.CurrentCulture).ToList();
                var (p, s) = Paging.Normalize(page, size);
                var context = await RowContext.LoadAsync(users, dataStatus, ct);
                var items = new List<OrgRowDto>();
                foreach (var org in filtered.Skip((p - 1) * s).Take(s))
                {
                    items.Add(await context.RowAsync(org, connected, ct));
                }

                return Results.Ok(new Paged<OrgRowDto>(items, p, s, filtered.Count));
            })
            .WithName("AdminOrgs").WithSummary("Организации: regionKato, type, status (connected | no_data), q; число пользователей, администраторы, свежесть загрузок")
            .Produces<Paged<OrgRowDto>>();

        orgs.MapGet("/{moCode}", async (string moCode, OrgDirectory directory, IOrgDataStatus dataStatus, UserDirectory users, IOrgApplicationStore applications,
                CancellationToken ct) =>
            {
                var org = (await directory.AllAsync(ct)).GetValueOrDefault(moCode);
                if (org is null)
                {
                    return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Организации нет в справочнике", detail: moCode);
                }

                var connected = await dataStatus.ConnectedAsync([org.MoCode], ct);
                var context = await RowContext.LoadAsync(users, dataStatus, ct);
                var related = await applications.ListAsync(null, org.MoCode, 1, ApplicationsPerOrganization, ct);
                return Results.Ok(new OrgDetailDto(await context.RowAsync(org, connected, ct), related.Items.Select(AdminApplicationEndpoints.ToDto).ToList()));
            })
            .WithName("AdminOrg").WithSummary("Организация: пользователи, администраторы, подключение, свежесть загрузок, заявки")
            .Produces<OrgDetailDto>().ProducesProblem(StatusCodes.Status404NotFound);

        AdminApplicationEndpoints.Map(api);
    }

    private static string StatusOf(OrganizationItemDto org, IReadOnlySet<string> connected) => connected.Contains(org.MoCode) ? Connected : NoData;

    /// <summary>Пользователи Keycloak читаются один раз на запрос; без Keycloak число пользователей и администраторы — null и пусто.</summary>
    private sealed class RowContext(IReadOnlyList<DirectoryUser>? users, IOrgDataStatus dataStatus)
    {
        private readonly Dictionary<string, IReadOnlyList<DatasetFreshness>> _freshness = new();

        public static async Task<RowContext> LoadAsync(UserDirectory directory, IOrgDataStatus dataStatus, CancellationToken ct)
        {
            try
            {
                return new RowContext(await directory.AllAsync(ct), dataStatus);
            }
            catch (IdentityUnavailableException)
            {
                return new RowContext(null, dataStatus);
            }
        }

        public async Task<OrgRowDto> RowAsync(OrganizationItemDto org, IReadOnlySet<string> connected, CancellationToken ct)
        {
            if (!_freshness.TryGetValue(org.RegionKato, out var freshness))
            {
                freshness = await dataStatus.FreshnessAsync(org.RegionKato, ct);
                _freshness[org.RegionKato] = freshness;
            }

            var members = users?.Where(u => UserRows.InOrganization(u, org.MoCode)).ToList();
            var admins = (members ?? []).Where(u => u.Has(Roles.OrgAdmin))
                .Select(u => new OrgAdminDto(u.Id, u.Identity.DisplayName, u.Identity.Email, u.Identity.Enabled ? UserStatuses.Active : UserStatuses.Blocked))
                .ToList();
            return new OrgRowDto(org.MoCode, org.Name, org.RegionKato, org.MoType, members?.Count, StatusOf(org, connected), admins,
                freshness.Select(f => new FreshnessDto(f.Dataset, f.LastLoadedAt, f.Status, f.RowsLoaded)).ToList());
        }
    }
}
