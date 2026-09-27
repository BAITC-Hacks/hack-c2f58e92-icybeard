using Darumen.Modules.Access.Data;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Services;

public static class UserStatuses
{
    public const string Active = "active";
    public const string Invited = "invited";
    public const string Blocked = "blocked";

    public static readonly string[] All = [Active, Invited, Blocked];
}

/// <summary>Строки пользователей для администрирования: статус (включён — active; выключен с открытым приглашением — invited;
/// иначе blocked), организация из справочника, последняя активность из журнала аудита.</summary>
public sealed class UserRows(IInvitationStore invitations, IActivityReader activity, OrgDirectory orgs, TimeProvider time)
{
    public async Task<IReadOnlyDictionary<string, Invitation>> OpenInvitationsAsync(IReadOnlyList<DirectoryUser> users, CancellationToken ct)
    {
        var disabled = users.Where(u => !u.Identity.Enabled).Select(u => u.Id).ToList();
        return (await invitations.OpenForUsersAsync(disabled, ct)).ToDictionary(i => i.UserId);
    }

    public static string Status(DirectoryUser user, IReadOnlyDictionary<string, Invitation> open) =>
        user.Identity.Enabled ? UserStatuses.Active : open.ContainsKey(user.Id) ? UserStatuses.Invited : UserStatuses.Blocked;

    public UsersSummaryDto Summary(IReadOnlyList<DirectoryUser> users, IReadOnlyDictionary<string, Invitation> open)
    {
        var now = time.GetUtcNow();
        return new UsersSummaryDto(
            users.Count(u => u.Identity.Enabled),
            users.Count(u => !u.Identity.Enabled && open.TryGetValue(u.Id, out var i) && i.ExpiresAt <= now),
            users.Count(u => Status(u, open) == UserStatuses.Blocked));
    }

    public async Task<IReadOnlyList<UserRowDto>> RowsAsync(IReadOnlyList<DirectoryUser> users, IReadOnlyDictionary<string, Invitation> open, CancellationToken ct)
    {
        var names = await orgs.AllAsync(ct);
        var last = await activity.LastActivityAsync(users.Select(u => u.Identity.Username).ToList(), ct);
        return users.Select(u => new UserRowDto(
            u.Id, u.Identity.Username, u.Identity.DisplayName, u.Identity.Email, u.Roles, u.MoCode, u.MoCode is null ? null : names.GetValueOrDefault(u.MoCode)?.Name,
            u.RegionKato, last.TryGetValue(u.Identity.Username, out var at) ? at : null, Status(u, open), u.Via)).ToList();
    }

    /// <summary>Поиск по логину, имени и почте без учёта регистра.</summary>
    public static bool Matches(DirectoryUser user, string? query) =>
        string.IsNullOrWhiteSpace(query)
        || user.Identity.Username.Contains(query, StringComparison.OrdinalIgnoreCase)
        || user.Identity.DisplayName.Contains(query, StringComparison.OrdinalIgnoreCase)
        || (user.Identity.Email?.Contains(query, StringComparison.OrdinalIgnoreCase) ?? false);

    public static bool InOrganization(DirectoryUser user, string? moCode) =>
        moCode is null || string.Equals(user.MoCode, moCode, StringComparison.OrdinalIgnoreCase);

    public static bool HasRole(DirectoryUser user, string? role) => string.IsNullOrWhiteSpace(role) || user.Has(Roles.Normalize(role));
}
