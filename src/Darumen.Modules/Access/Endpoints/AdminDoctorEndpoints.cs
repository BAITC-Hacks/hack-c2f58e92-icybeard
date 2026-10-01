using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Врачи (admin.users): направления и совпадение с рекомендацией из журнала решений за квартал, верификация.</summary>
public static class AdminDoctorEndpoints
{
    /// <summary>«За квартал» — скользящие 90 дней, чтобы в начале календарного квартала список не обнулялся.</summary>
    public static readonly TimeSpan StatsWindow = TimeSpan.FromDays(90);

    public static void Map(IEndpointRouteBuilder api)
    {
        var doctors = api.MapGroup("/admin/doctors").WithTags("Admin").RequireAuthorization(Permissions.Policy(Permissions.AdminUsers));

        doctors.MapGet("", async (string? regionKato, string? moCode, string? specialty, string? verification, int? page, int? size, HttpContext http,
                UserDirectory directory, IAccountStore account, IActivityReader activity, OrgDirectory orgs, TimeProvider time, CancellationToken ct) =>
            {
                var scope = await OrgAccess.ResolveAsync(http, moCode, Permissions.AdminUsers);
                if (scope.Problem is not null)
                {
                    return scope.Problem;
                }

                var candidates = (await directory.AllAsync(ct))
                    .Where(u => u.Has(Roles.Doctor) && UserRows.InOrganization(u, scope.MoCode)
                                && (regionKato is null || u.RegionKato == regionKato)
                                && (specialty is null || (u.Specialty?.Contains(specialty, StringComparison.OrdinalIgnoreCase) ?? false)))
                    .ToList();
                var verifications = await account.VerificationsAsync(candidates.Select(u => u.Id).ToList(), ct);
                var filtered = candidates.Where(u => verification is null || StatusOf(u, verifications) == verification)
                    .OrderBy(u => u.Identity.DisplayName, StringComparer.CurrentCulture).ToList();
                var (p, s) = Paging.Normalize(page, size);
                var pageUsers = filtered.Skip((p - 1) * s).Take(s).ToList();
                var stats = await activity.ReferralStatsAsync(pageUsers.Select(u => u.Identity.Username).ToList(), time.GetUtcNow() - StatsWindow, ct);
                var names = await orgs.AllAsync(ct);
                var items = pageUsers.Select(u => Row(u, verifications, stats, names.GetValueOrDefault(u.MoCode ?? string.Empty)?.Name)).ToList();
                return Results.Ok(new Paged<DoctorRowDto>(items, p, s, filtered.Count));
            })
            .WithName("AdminDoctors").WithSummary("Врачи: направления и доля совпадения выбора с рекомендацией за 90 дней, верификация pending | verified | rejected")
            .Produces<Paged<DoctorRowDto>>().ProducesProblem(StatusCodes.Status403Forbidden);

        doctors.MapPost("/{id}/verification", async (string id, VerificationRequestDto body, HttpContext http, UserDirectory directory, IAccountStore account,
                IActivityReader activity, OrgDirectory orgs, AdminActions actions, TimeProvider time, CancellationToken ct) =>
            {
                if (body.Status is null || !VerificationStatuses.All.Contains(body.Status))
                {
                    return new ValidationErrors().Add("status", $"ожидается одно из: {string.Join(", ", VerificationStatuses.All)}").Problem();
                }

                var (target, scope, problem) = await AdminUserEndpoints.TargetAsync(id, http, directory, ct);
                if (problem is not null)
                {
                    return problem;
                }

                // проверка диплома и сертификата — дело администратора платформы, а не руководителя больницы:
                // главврач не подтверждает квалификацию собственного сотрудника (конфликт интересов)
                if (scope.IsOwn)
                {
                    return Results.Problem(statusCode: StatusCodes.Status403Forbidden, title: "Верификацию проводит администратор платформы",
                        detail: "подтвердить или отклонить квалификацию врача может только администратор платформы");
                }

                if (!target!.Has(Roles.Doctor))
                {
                    return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Врач не найден", detail: "у пользователя нет роли doctor");
                }

                var previous = (await account.VerificationsAsync([id], ct)).GetValueOrDefault(id);
                var verification = new DoctorVerification(id, body.Status, body.Comment?.Trim(), CurrentUser.From(http).Actor, time.GetUtcNow());
                await account.SetVerificationAsync(verification, ct);
                await actions.RecordAsync(http, DecisionSubjects.DoctorVerification, id, new { status = previous?.Status ?? VerificationStatuses.Pending },
                    new { status = body.Status }, verification.Comment, ct);
                var stats = await activity.ReferralStatsAsync([target.Identity.Username], time.GetUtcNow() - StatsWindow, ct);
                return Results.Ok(Row(target, new Dictionary<string, DoctorVerification> { [id] = verification }, stats, await orgs.NameAsync(target.MoCode, ct)));
            })
            .WithName("AdminVerifyDoctor").WithSummary("Верификация врача; решение уходит в журнал")
            .Produces<DoctorRowDto>().ProducesProblem(StatusCodes.Status403Forbidden).ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
    }

    private static string StatusOf(DirectoryUser user, IReadOnlyDictionary<string, DoctorVerification> verifications) =>
        verifications.GetValueOrDefault(user.Id)?.Status ?? VerificationStatuses.Pending;

    private static DoctorRowDto Row(DirectoryUser user, IReadOnlyDictionary<string, DoctorVerification> verifications,
        IReadOnlyDictionary<string, ReferralStats> stats, string? moName)
    {
        var referral = stats.GetValueOrDefault(user.Identity.Username);
        return new DoctorRowDto(user.Id, user.Identity.DisplayName, user.Specialty, user.MoCode, moName, user.RegionKato,
            referral?.Referrals ?? 0, referral?.MatchRate, StatusOf(user, verifications));
    }
}
