using Darumen.Shared.Api;

namespace Darumen.Shared.Auth;

/// <summary>Привязка врача к отделению/профилю (задача 10 плана прозрачности): необязательный клейм profile_code
/// сужает рабочий список врача до одной очереди (mo_code, profile_code) вместо всех очередей организации. Врач без
/// этого клейма продолжает видеть все профили своей организации — поведение не меняется, привязка добавляется поверх,
/// а не заменяет существующую org-скоуп-логику (<see cref="OrgAccess"/>). Только для врача: у org_admin/bed_manager
/// рабочий список — по всей организации, у них привязка к профилю не имеет смысла (это позиция руководителя/менеджера,
/// не конкретного специалиста).</summary>
public static class ProfileAccess
{
    /// <summary>Профиль, которым ограничен врач, если у него есть клейм profile_code; иначе null — без ограничения.</summary>
    public static string? ProfileScope(CurrentUser user) =>
        user.Role is Roles.Doctor && !string.IsNullOrWhiteSpace(user.ProfileCode) ? user.ProfileCode : null;
}
