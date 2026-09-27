using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Identity;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Access.Services;

public sealed record InviteCommand(string Email, string DisplayName, string Role, string? MoCode, string? RegionKato, Guid? ApplicationId = null);

/// <summary>Созданное приглашение: Url со свежим токеном — только для письма или ответа администратору, в базе хеш.</summary>
public sealed record CreatedInvitation(Invitation Invitation, string Url);

/// <summary>Приглашение: пользователь в Keycloak (выключен до принятия) с ролью и атрибутами организации, токен на 7 дней.
/// Письмо составляет вызывающий (обычное приглашение или «Заявка одобрена»).</summary>
public sealed class InvitationService(IIdentityAdmin identity, IInvitationStore store, IOptions<WebOptions> web, TimeProvider time)
{
    public static readonly TimeSpan Lifetime = TimeSpan.FromDays(7);

    public async Task<CreatedInvitation> CreateAsync(InviteCommand command, string invitedBy, CancellationToken cancellationToken)
    {
        var email = command.Email.Trim().ToLowerInvariant();
        if (await identity.UserByEmailAsync(email, cancellationToken) is not null)
        {
            throw new IdentityConflictException("пользователь с такой почтой уже есть");
        }

        var (first, last) = SplitName(command.DisplayName);
        var attributes = new Dictionary<string, string>();
        AddIfPresent(attributes, IdentityAttributes.MoCode, command.MoCode);
        AddIfPresent(attributes, IdentityAttributes.RegionKato, command.RegionKato);
        var userId = await identity.CreateUserAsync(new NewIdentityUser(email, email, first, last, attributes), cancellationToken);
        try
        {
            await identity.SetRolesAsync(userId, [command.Role], [], cancellationToken);
        }
        catch
        {
            await identity.DeleteUserAsync(userId, CancellationToken.None); // не оставляем выключенного пользователя без роли
            throw;
        }

        var token = Tokens.New();
        var now = time.GetUtcNow();
        var invitation = new Invitation(Guid.NewGuid(), Tokens.Hash(token), userId, email, command.DisplayName.Trim(), command.Role, command.MoCode,
            command.RegionKato, invitedBy, now, now + Lifetime, null, null, command.ApplicationId);
        await store.AddAsync(invitation, cancellationToken);
        return new CreatedInvitation(invitation, $"{web.Value.Origin}/invite/{token}");
    }

    /// <summary>«Фамилия Имя Отчество» → firstName = первое слово, lastName = остальное: DisplayName собирается обратно без потерь.</summary>
    public static (string? First, string? Last) SplitName(string displayName)
    {
        var parts = displayName.Trim().Split(' ', 2, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return parts.Length switch
        {
            0 => (null, null),
            1 => (parts[0], null),
            _ => (parts[0], parts[1]),
        };
    }

    private static void AddIfPresent(Dictionary<string, string> attributes, string key, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value))
        {
            attributes[key] = value.Trim();
        }
    }
}
