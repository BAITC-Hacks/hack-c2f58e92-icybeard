using Darumen.Shared.Api;

namespace Darumen.Shared.Auth;

/// <summary>Ограничение доступа к данным по региону для ролей, привязанных к одному региону (главврач).</summary>
public static class RegionAccess
{
    /// <summary>Регион, которым ограничен пользователь: главврач работает только со своим регионом из клейма region_kato.
    /// Для остальных ролей (регулятор и т.д.) — null, то есть без ограничения.</summary>
    public static string? RegionScope(CurrentUser user) =>
        user.Role == Roles.Chief && !string.IsNullOrWhiteSpace(user.RegionKato) ? user.RegionKato : null;
}
