using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using static Darumen.Modules.Access.Identity.KeycloakJson;

namespace Darumen.Modules.Access.Identity;

/// <summary>Admin REST API Keycloak (/admin/realms/{realm}) под токеном сервисного клиента darumen-admin. Сетевые ошибки,
/// 5xx, 401/403 — <see cref="IdentityUnavailableException"/>; 404 на чтении — null.</summary>
public sealed class KeycloakIdentityAdmin(IHttpClientFactory httpFactory, KeycloakTokenProvider tokens, IOptions<KeycloakAdminOptions> options) : IIdentityAdmin
{
    private static readonly string[] LoginEventTypes = ["LOGIN", "LOGIN_ERROR"];

    private string Admin => $"{options.Value.BaseUrl}/admin/realms/{options.Value.Realm}";

    public async Task<IReadOnlyList<IdentityUser>> UsersAsync(int max, CancellationToken cancellationToken) =>
        (await GetAsync<List<UserRep>>($"/users?briefRepresentation=false&first=0&max={max}", cancellationToken) ?? []).Select(ToUser).ToList();

    public async Task<IdentityUser?> UserAsync(string id, CancellationToken cancellationToken) =>
        await GetAsync<UserRep>($"/users/{Uri.EscapeDataString(id)}", cancellationToken) is { } user ? ToUser(user) : null;

    public async Task<IdentityUser?> UserByEmailAsync(string email, CancellationToken cancellationToken)
    {
        var users = await GetAsync<List<UserRep>>($"/users?email={Uri.EscapeDataString(email)}&exact=true&briefRepresentation=false", cancellationToken) ?? [];
        var match = users.FirstOrDefault(u => string.Equals(u.Email, email, StringComparison.OrdinalIgnoreCase));
        return match is null ? null : ToUser(match);
    }

    public async Task<IReadOnlyList<string>> RoleMembersAsync(string role, int max, CancellationToken cancellationToken) =>
        (await GetAsync<List<UserRep>>($"/roles/{Uri.EscapeDataString(role)}/users?first=0&max={max}&briefRepresentation=true", cancellationToken) ?? [])
            .Select(u => u.Id).ToList();

    public async Task<IReadOnlyList<string>> UserRolesAsync(string id, CancellationToken cancellationToken) =>
        (await GetAsync<List<RoleRep>>($"/users/{Uri.EscapeDataString(id)}/role-mappings/realm", cancellationToken) ?? []).Select(r => r.Name).ToList();

    public async Task<string> CreateUserAsync(NewIdentityUser user, CancellationToken cancellationToken)
    {
        var body = new
        {
            username = user.Username, email = user.Email, firstName = user.FirstName, lastName = user.LastName,
            enabled = false, emailVerified = false,
            attributes = user.Attributes.ToDictionary(a => a.Key, a => new[] { a.Value }),
        };
        using var response = await SendAsync(HttpMethod.Post, "/users", body, cancellationToken);
        if (response.StatusCode == HttpStatusCode.Conflict)
        {
            throw new IdentityConflictException("пользователь с такой почтой или логином уже есть");
        }

        await EnsureSuccessAsync(response, cancellationToken);
        var location = response.Headers.Location?.ToString() ?? throw new IdentityUnavailableException("Keycloak не вернул адрес созданного пользователя");
        return location[(location.LastIndexOf('/') + 1)..];
    }

    public async Task UpdateUserAsync(string id, IdentityUserUpdate update, CancellationToken cancellationToken)
    {
        var current = await GetAsync<UserRep>($"/users/{Uri.EscapeDataString(id)}", cancellationToken)
                      ?? throw new IdentityNotFoundException($"пользователь {id} не найден в Keycloak");
        var attributes = current.Attributes ?? [];
        foreach (var (key, value) in update.Attributes ?? new Dictionary<string, string?>())
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                attributes.Remove(key);
            }
            else
            {
                attributes[key] = [value];
            }
        }

        var body = new
        {
            username = current.Username, email = current.Email, firstName = current.FirstName, lastName = current.LastName,
            enabled = update.Enabled ?? current.Enabled, emailVerified = update.EmailVerified ?? current.EmailVerified, attributes,
        };
        using var response = await SendAsync(HttpMethod.Put, $"/users/{Uri.EscapeDataString(id)}", body, cancellationToken);
        await EnsureSuccessAsync(response, cancellationToken);
    }

    public async Task DeleteUserAsync(string id, CancellationToken cancellationToken)
    {
        using var response = await SendAsync(HttpMethod.Delete, $"/users/{Uri.EscapeDataString(id)}", null, cancellationToken);
        if (response.StatusCode != HttpStatusCode.NotFound)
        {
            await EnsureSuccessAsync(response, cancellationToken);
        }
    }

    public async Task SetRolesAsync(string id, IReadOnlyCollection<string> add, IReadOnlyCollection<string> remove, CancellationToken cancellationToken)
    {
        var path = $"/users/{Uri.EscapeDataString(id)}/role-mappings/realm";
        var current = (await GetAsync<List<RoleRep>>(path, cancellationToken) ?? []).ToList();
        var toRemove = current.Where(r => remove.Contains(r.Name) && !add.Contains(r.Name)).ToList();
        var toAdd = new List<RoleRep>();
        foreach (var name in add.Where(n => current.All(r => r.Name != n)))
        {
            toAdd.Add(await GetAsync<RoleRep>($"/roles/{Uri.EscapeDataString(name)}", cancellationToken)
                      ?? throw new IdentityUnavailableException($"в реалме нет роли {name}"));
        }

        if (toRemove.Count > 0)
        {
            using var removed = await SendAsync(HttpMethod.Delete, path, toRemove, cancellationToken);
            await EnsureSuccessAsync(removed, cancellationToken);
        }

        if (toAdd.Count > 0)
        {
            using var added = await SendAsync(HttpMethod.Post, path, toAdd, cancellationToken);
            await EnsureSuccessAsync(added, cancellationToken);
        }
    }

    public async Task SetPasswordAsync(string id, string password, CancellationToken cancellationToken)
    {
        using var response = await SendAsync(HttpMethod.Put, $"/users/{Uri.EscapeDataString(id)}/reset-password",
            new { type = "password", value = password, temporary = false }, cancellationToken);
        if (response.StatusCode == HttpStatusCode.BadRequest)
        {
            var error = await ReadErrorAsync(response, cancellationToken);
            throw new IdentityPolicyException(error?.Error ?? error?.ErrorMessage ?? "invalidPasswordMessage", error?.Params ?? [], error?.ErrorDescription);
        }

        await EnsureSuccessAsync(response, cancellationToken);
    }

    public async Task<IReadOnlyList<IdentityCredential>> CredentialsAsync(string id, CancellationToken cancellationToken) =>
        (await GetAsync<List<CredentialRep>>($"/users/{Uri.EscapeDataString(id)}/credentials", cancellationToken) ?? []).Select(ToCredential).ToList();

    public async Task<IReadOnlyList<IdentitySession>> SessionsAsync(string id, CancellationToken cancellationToken) =>
        (await GetAsync<List<SessionRep>>($"/users/{Uri.EscapeDataString(id)}/sessions", cancellationToken) ?? []).Select(ToSession).ToList();

    public async Task DeleteSessionAsync(string sessionId, CancellationToken cancellationToken)
    {
        using var response = await SendAsync(HttpMethod.Delete, $"/sessions/{Uri.EscapeDataString(sessionId)}", null, cancellationToken);
        if (response.StatusCode != HttpStatusCode.NotFound)
        {
            await EnsureSuccessAsync(response, cancellationToken);
        }
    }

    public async Task LogoutAsync(string id, CancellationToken cancellationToken)
    {
        using var response = await SendAsync(HttpMethod.Post, $"/users/{Uri.EscapeDataString(id)}/logout", null, cancellationToken);
        await EnsureSuccessAsync(response, cancellationToken);
    }

    public async Task<IReadOnlyList<IdentityEvent>> LoginEventsAsync(string id, int max, CancellationToken cancellationToken)
    {
        var types = string.Join('&', LoginEventTypes.Select(t => $"type={t}"));
        return (await GetAsync<List<EventRep>>($"/events?user={Uri.EscapeDataString(id)}&{types}&first=0&max={max}", cancellationToken) ?? [])
            .Select(ToEvent).OrderByDescending(e => e.At).ToList();
    }

    public async Task CreateRoleAsync(string name, string? description, CancellationToken cancellationToken)
    {
        using var response = await SendAsync(HttpMethod.Post, "/roles", new { name, description }, cancellationToken);
        if (response.StatusCode != HttpStatusCode.Conflict)
        {
            await EnsureSuccessAsync(response, cancellationToken);
        }
    }

    public async Task ExecuteActionsEmailAsync(
        string id, IReadOnlyList<string> actions, int lifespanSeconds, string clientId, string redirectUri, CancellationToken cancellationToken)
    {
        var query = $"lifespan={lifespanSeconds}&client_id={Uri.EscapeDataString(clientId)}&redirect_uri={Uri.EscapeDataString(redirectUri)}";
        using var response = await SendAsync(HttpMethod.Put, $"/users/{Uri.EscapeDataString(id)}/execute-actions-email?{query}", actions, cancellationToken);
        await EnsureSuccessAsync(response, cancellationToken);
    }

    private async Task<T?> GetAsync<T>(string path, CancellationToken cancellationToken) where T : class
    {
        using var response = await SendAsync(HttpMethod.Get, path, null, cancellationToken);
        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }

        await EnsureSuccessAsync(response, cancellationToken);
        return await response.Content.ReadFromJsonAsync<T>(Serializer, cancellationToken);
    }

    private async Task<HttpResponseMessage> SendAsync(HttpMethod method, string path, object? body, CancellationToken cancellationToken)
    {
        var token = await tokens.TokenAsync(cancellationToken);
        using var request = new HttpRequestMessage(method, Admin + path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body, options: Serializer);
        }

        try
        {
            var response = await httpFactory.CreateClient(KeycloakTokenProvider.HttpClientName).SendAsync(request, cancellationToken);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                tokens.Reset(); // токен отозван или истёк раньше срока — следующий запрос получит новый
            }

            return response;
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
        {
            throw new IdentityUnavailableException("Keycloak недоступен", exception);
        }
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        var error = await ReadErrorAsync(response, cancellationToken);
        var detail = error?.ErrorMessage ?? error?.Error ?? error?.ErrorDescription ?? response.ReasonPhrase;
        throw response.StatusCode switch
        {
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden => new IdentityUnavailableException(
                $"у клиента darumen-admin нет прав на это действие в Keycloak ({(int)response.StatusCode})"),
            HttpStatusCode.Conflict => new IdentityConflictException(detail ?? "конфликт в Keycloak"),
            HttpStatusCode.NotFound => new IdentityNotFoundException(detail ?? "не найдено в Keycloak"),
            _ => new IdentityUnavailableException($"Keycloak ответил {(int)response.StatusCode}: {detail}"),
        };
    }

    private static async Task<ErrorRep?> ReadErrorAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            return await response.Content.ReadFromJsonAsync<ErrorRep>(Serializer, cancellationToken);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
