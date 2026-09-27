using Darumen.Shared.Api;

namespace Darumen.Shared.Auth;

/// <summary>Ограничение доступа к данным по региону для ролей, привязанных к одному региону (администратор организации, врач ПМСП).</summary>
public static class RegionAccess
{
    /// <summary>Регион, которым ограничен пользователь: администратор организации и врач работают только со своим регионом из клейма
    /// region_kato (врач — с маршрутами пациентов своего региона, /route/{patientRef}). Для остальных ролей (регулятор и т.д.)
    /// и при отсутствии клейма — null, то есть без ограничения.</summary>
    public static string? RegionScope(CurrentUser user) =>
        user.Role is Roles.OrgAdmin or Roles.Doctor && !string.IsNullOrWhiteSpace(user.RegionKato) ? user.RegionKato : null;
}
