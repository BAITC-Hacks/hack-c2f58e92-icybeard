using Darumen.Modules.Access.Data;
using Darumen.Modules.Journal;

namespace Darumen.Modules.Access.Services;

/// <summary>Настройка «Изменения моего маршрута» (route_updates, in-app) для колокольчика гражданина; по умолчанию включена.</summary>
public sealed class RouteNotificationPreferences(IAccountStore accounts) : IRouteNotificationPreferences
{
    public const string Event = "route_updates";

    public async Task<bool> RouteUpdatesEnabledAsync(string userId, CancellationToken cancellationToken)
    {
        var settings = NotificationSettings.Parse((await accounts.SettingsAsync(userId, cancellationToken))?.NotificationsJson);
        return settings.Events.GetValueOrDefault(Event)?.InApp ?? true;
    }
}
