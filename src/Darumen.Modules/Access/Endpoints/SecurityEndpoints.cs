using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Безопасность аккаунта из Keycloak Admin API: пароль, второй фактор, последние входы, сессии. Смена пароля и
/// настройка приложения-аутентификатора — редиректом в Keycloak (kc_action=UPDATE_PASSWORD / CONFIGURE_TOTP).</summary>
public static class SecurityEndpoints
{
    private const int RecentLogins = 10;
    private const string MobileClient = "darumen-mobile";
    private const string WebClient = "darumen-web";

    public static void Map(IEndpointRouteBuilder api)
    {
        var me = api.MapGroup("/me").WithTags("Account").RequireAuthorization(Policies.Authenticated);

        me.MapGet("/security", async (HttpContext http, IIdentityAdmin identity, CancellationToken ct) =>
            {
                var user = CurrentUser.From(http);
                var credentials = await identity.CredentialsAsync(user.UserId, ct);
                var logins = await identity.LoginEventsAsync(user.UserId, RecentLogins, ct);
                var sessions = await identity.SessionsAsync(user.UserId, ct);
                return Results.Ok(new SecurityDto(
                    credentials.Where(c => c.Type == "password").Select(c => c.CreatedAt).FirstOrDefault(),
                    credentials.Any(c => c.Type == "otp"),
                    false,
                    null,
                    logins.Select(e => new LoginDto(e.At, e.IdentityProvider ?? "password", e.Type == "LOGIN", e.IpAddress)).ToList(),
                    sessions.OrderByDescending(s => s.LastAccess).Select(s => ToDto(s, user.SessionId)).ToList()));
            })
            .WithName("MySecurity").WithSummary("Пароль (дата смены), второй фактор, последние входы и активные сессии (текущая — по sid токена)")
            .Produces<SecurityDto>().ProducesProblem(StatusCodes.Status503ServiceUnavailable);

        me.MapDelete("/sessions/{id}", async (string id, HttpContext http, IIdentityAdmin identity, AdminActions actions, CancellationToken ct) =>
            {
                var user = CurrentUser.From(http);
                if ((await identity.SessionsAsync(user.UserId, ct)).All(s => s.Id != id))
                {
                    return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Сессия не найдена", detail: "у вас нет такой активной сессии");
                }

                await identity.DeleteSessionAsync(id, ct);
                actions.Audit(http, "session_closed", "сессия завершена пользователем");
                return Results.NoContent();
            })
            .WithName("CloseMySession").WithSummary("Завершить одну свою сессию")
            .Produces(StatusCodes.Status204NoContent).ProducesProblem(StatusCodes.Status404NotFound);

        me.MapDelete("/sessions", async (bool? keepCurrent, HttpContext http, IIdentityAdmin identity, AdminActions actions, CancellationToken ct) =>
            {
                var user = CurrentUser.From(http);
                var sessions = await identity.SessionsAsync(user.UserId, ct);
                var closed = 0;
                if (keepCurrent == false)
                {
                    await identity.LogoutAsync(user.UserId, ct);
                    closed = sessions.Count;
                }
                else
                {
                    foreach (var session in sessions.Where(s => s.Id != user.SessionId))
                    {
                        await identity.DeleteSessionAsync(session.Id, ct);
                        closed++;
                    }
                }

                actions.Audit(http, "sessions_closed", $"завершено сессий: {closed}");
                return Results.Ok(new { closed });
            })
            .WithName("CloseMySessions").WithSummary("Завершить все свои сессии; keepCurrent=true (по умолчанию) оставляет текущую");
    }

    private static SessionDto ToDto(IdentitySession session, string? currentSessionId) => new(
        session.Id, Device(session.Clients), null, session.IpAddress, session.Start, session.LastAccess, session.Id == currentSessionId);

    /// <summary>Admin API не отдаёт User-Agent: устройство — по клиенту Keycloak, через который открыта сессия.</summary>
    private static string Device(IReadOnlyList<string> clients) =>
        clients.Contains(MobileClient) ? "Мобильное приложение" : clients.Contains(WebClient) ? "Веб-браузер" : clients.FirstOrDefault() ?? "Неизвестное устройство";
}
