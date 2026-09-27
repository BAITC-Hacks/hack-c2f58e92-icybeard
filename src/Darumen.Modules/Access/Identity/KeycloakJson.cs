using System.Text.Json;
using System.Text.Json.Serialization;

namespace Darumen.Modules.Access.Identity;

/// <summary>Представления Admin REST API Keycloak (camelCase) и их перевод в модели приложения.</summary>
internal static class KeycloakJson
{
    public static readonly JsonSerializerOptions Serializer = new(JsonSerializerDefaults.Web);

    public sealed record UserRep(
        string Id, string Username, string? Email, bool? EmailVerified, string? FirstName, string? LastName, bool? Enabled,
        long? CreatedTimestamp, Dictionary<string, List<string>>? Attributes);

    public sealed record RoleRep(string? Id, string Name, string? Description);

    public sealed record SessionRep(string Id, string? IpAddress, long? Start, long? LastAccess, Dictionary<string, string>? Clients);

    public sealed record EventRep(long Time, string Type, string? IpAddress, string? Error, Dictionary<string, string>? Details);

    public sealed record CredentialRep(string Type, long? CreatedDate);

    /// <summary>Ошибка Admin API: старый формат {error, error_description}, новый — {errorMessage, params}.</summary>
    public sealed record ErrorRep(
        string? Error, string? ErrorMessage, [property: JsonPropertyName("error_description")] string? ErrorDescription, List<string>? Params);

    public static IdentityUser ToUser(UserRep r) => new(
        r.Id, r.Username, r.Email, r.EmailVerified ?? false, r.FirstName, r.LastName, r.Enabled ?? false,
        r.CreatedTimestamp is { } created ? DateTimeOffset.FromUnixTimeMilliseconds(created) : null,
        (r.Attributes ?? []).ToDictionary(a => a.Key, a => (IReadOnlyList<string>)a.Value));

    public static IdentitySession ToSession(SessionRep r) => new(
        r.Id, r.IpAddress, FromMs(r.Start), FromMs(r.LastAccess), (r.Clients ?? []).Values.ToList());

    public static IdentityEvent ToEvent(EventRep r) => new(
        DateTimeOffset.FromUnixTimeMilliseconds(r.Time), r.Type, r.IpAddress, r.Error,
        r.Details?.GetValueOrDefault("auth_method"), r.Details?.GetValueOrDefault("identity_provider"));

    public static IdentityCredential ToCredential(CredentialRep r) => new(r.Type, FromMs(r.CreatedDate));

    private static DateTimeOffset? FromMs(long? ms) => ms is { } value and > 0 ? DateTimeOffset.FromUnixTimeMilliseconds(value) : null;
}
