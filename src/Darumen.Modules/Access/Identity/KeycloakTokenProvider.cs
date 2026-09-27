using System.Net.Http.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Access.Identity;

/// <summary>Токен сервисного аккаунта darumen-admin (client credentials), кэшируется до истечения минус запас.</summary>
public sealed class KeycloakTokenProvider(IHttpClientFactory httpFactory, IOptions<KeycloakAdminOptions> options, TimeProvider time)
{
    public const string HttpClientName = "keycloak-admin";
    private static readonly TimeSpan Margin = TimeSpan.FromSeconds(30);

    private readonly SemaphoreSlim _gate = new(1, 1);
    private (string Token, DateTimeOffset ExpiresAt)? _cached;

    public async Task<string> TokenAsync(CancellationToken cancellationToken)
    {
        if (_cached is { } cached && time.GetUtcNow() < cached.ExpiresAt)
        {
            return cached.Token;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (_cached is { } again && time.GetUtcNow() < again.ExpiresAt)
            {
                return again.Token;
            }

            var token = await RequestAsync(cancellationToken);
            _cached = (token.AccessToken, time.GetUtcNow() + TimeSpan.FromSeconds(token.ExpiresIn) - Margin);
            return token.AccessToken;
        }
        finally
        {
            _gate.Release();
        }
    }

    public void Reset() => _cached = null;

    private async Task<TokenResponse> RequestAsync(CancellationToken cancellationToken)
    {
        var settings = options.Value;
        var form = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["grant_type"] = "client_credentials",
            ["client_id"] = settings.ClientId,
            ["client_secret"] = settings.ClientSecret ?? KeycloakAdminOptions.DevClientSecret,
        });
        HttpResponseMessage response;
        try
        {
            response = await httpFactory.CreateClient(HttpClientName)
                .PostAsync($"{settings.BaseUrl}/realms/{settings.Realm}/protocol/openid-connect/token", form, cancellationToken);
        }
        catch (Exception exception) when (exception is HttpRequestException or TaskCanceledException && !cancellationToken.IsCancellationRequested)
        {
            throw new IdentityUnavailableException("Keycloak недоступен: не удалось получить токен сервисного клиента", exception);
        }

        using (response)
        {
            if (!response.IsSuccessStatusCode)
            {
                throw new IdentityUnavailableException(
                    $"Keycloak отклонил клиента {settings.ClientId} ({(int)response.StatusCode}): проверьте клиента и Keycloak__Admin__ClientSecret");
            }

            return await response.Content.ReadFromJsonAsync<TokenResponse>(cancellationToken)
                   ?? throw new IdentityUnavailableException("Keycloak вернул пустой ответ на запрос токена");
        }
    }

    private sealed record TokenResponse([property: JsonPropertyName("access_token")] string AccessToken, [property: JsonPropertyName("expires_in")] int ExpiresIn);
}
