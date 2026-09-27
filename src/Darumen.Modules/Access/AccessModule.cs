using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Endpoints;
using Darumen.Modules.Access.Identity;
using Darumen.Modules.Access.Mail;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Auth;
using Darumen.Shared.Modules;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Access;

/// <summary>Доступ и администрирование (docs/rbac.md): /me и аккаунт, пользователи, врачи, роли, организации и заявки,
/// публичные регистрация организации, приглашения и восстановление пароля.</summary>
public sealed class AccessModule : IDarumenModule
{
    private const string RealmsSegment = "/realms/";

    public string Name => "access";

    public void AddServices(IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<WebOptions>(configuration.GetSection(WebOptions.Section));
        services.Configure<MailOptions>(configuration.GetSection(MailOptions.Section));
        services.Configure<KeycloakAdminOptions>(configuration.GetSection(KeycloakAdminOptions.Section));
        services.PostConfigure<KeycloakAdminOptions>(options => ApplyAuthority(options, configuration));
        services.AddMemoryCache();
        services.TryAddSingleton(TimeProvider.System);

        services.AddHttpClient(KeycloakTokenProvider.HttpClientName, (sp, client) =>
            client.Timeout = TimeSpan.FromSeconds(Math.Max(1, sp.GetRequiredService<IOptions<KeycloakAdminOptions>>().Value.TimeoutSeconds)));
        services.AddSingleton<KeycloakTokenProvider>();
        services.AddSingleton<IIdentityAdmin, KeycloakIdentityAdmin>();
        services.AddSingleton<IEmailSender, SmtpEmailSender>();
        services.AddExceptionHandler<IdentityExceptionHandler>();

        services.AddSingleton<IInvitationStore, PostgresInvitationStore>();
        services.AddSingleton<IOrgApplicationStore, PostgresOrgApplicationStore>();
        services.AddSingleton<IAccountStore, PostgresAccountStore>();
        services.AddSingleton<PostgresActivityReader>();
        services.AddSingleton<IActivityReader>(sp => sp.GetRequiredService<PostgresActivityReader>());
        services.AddSingleton<IOrgDataStatus>(sp => sp.GetRequiredService<PostgresActivityReader>());

        services.AddScoped<OrgDirectory>();
        services.AddScoped<UserDirectory>();
        services.AddScoped<UserRows>();
        services.AddScoped<InvitationService>();
        services.AddScoped<OrgApplicationService>();
        services.AddScoped<AdminActions>();
    }

    public void MapEndpoints(IEndpointRouteBuilder api)
    {
        MeEndpoints.Map(api);
        SecurityEndpoints.Map(api);
        AdminUserEndpoints.Map(api);
        AdminDoctorEndpoints.Map(api);
        AdminRoleEndpoints.Map(api);
        AdminOrgEndpoints.Map(api);
        PublicAccessEndpoints.Map(api);
    }

    /// <summary>Keycloak:Admin:BaseUrl и Realm по умолчанию — из Auth:Authority (http://keycloak:8080/realms/darumen).</summary>
    private static void ApplyAuthority(KeycloakAdminOptions options, IConfiguration configuration)
    {
        var authority = (configuration.GetSection(AuthOptions.Section).Get<AuthOptions>() ?? new AuthOptions()).Authority.TrimEnd('/');
        var index = authority.IndexOf(RealmsSegment, StringComparison.Ordinal);
        options.BaseUrl = (string.IsNullOrWhiteSpace(options.BaseUrl) ? index >= 0 ? authority[..index] : authority : options.BaseUrl).TrimEnd('/');
        if (string.IsNullOrWhiteSpace(options.Realm))
        {
            options.Realm = index >= 0 ? authority[(index + RealmsSegment.Length)..] : "darumen";
        }
    }
}
