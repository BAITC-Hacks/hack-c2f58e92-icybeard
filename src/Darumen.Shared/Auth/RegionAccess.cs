using Darumen.Shared.Api;

namespace Darumen.Shared.Auth;

/// <summary>Ограничение доступа к данным по региону для ролей, которые могут быть привязаны к одному региону
/// (администратор организации, врач ПМСП, региональный регулятор).</summary>
public static class RegionAccess
{
    /// <summary>Регион, которым ограничен пользователь, если у него есть клейм region_kato: администратор организации и
    /// врач работают только со своим регионом (врач — с маршрутами пациентов своего региона, /route/{patientRef}).
    /// Регулятор — та же логика (задача 9 плана прозрачности): несколько регуляторов, часть национальные (без клейма —
    /// без ограничения, видят всё, как раньше), часть региональные (с клеймом — тот же региональный охват, что у
    /// org_admin/doctor: /journal/worklist, /anomalies, ack аномалии вне региона — 403/AckOutcome.OutOfScope).
    /// Для остальных ролей и при отсутствии клейма — null, то есть без ограничения.</summary>
    public static string? RegionScope(CurrentUser user) =>
        user.Role is Roles.OrgAdmin or Roles.Doctor or Roles.Regulator && !string.IsNullOrWhiteSpace(user.RegionKato) ? user.RegionKato : null;
}
