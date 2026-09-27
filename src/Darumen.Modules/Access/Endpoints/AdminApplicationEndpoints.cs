using Darumen.Modules.Access.Data;
using Darumen.Modules.Access.Mail;
using Darumen.Modules.Access.Services;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;

namespace Darumen.Modules.Access.Endpoints;

/// <summary>Заявки на регистрацию (admin.orgs): список, одобрение (администратор организации с приглашением), отказ с причиной.</summary>
public static class AdminApplicationEndpoints
{
    public static void Map(IEndpointRouteBuilder api)
    {
        var applications = api.MapGroup("/admin/org-applications").WithTags("Admin").RequireAuthorization(Permissions.Policy(Permissions.AdminOrgs));

        applications.MapGet("", async (string? status, int? page, int? size, IOrgApplicationStore store, CancellationToken ct) =>
            {
                if (status is not null && !OrgApplicationStatuses.All.Contains(status))
                {
                    return new ValidationErrors().Add("status", $"ожидается одно из: {string.Join(", ", OrgApplicationStatuses.All)}").Problem();
                }

                var (p, s) = Paging.Normalize(page, size);
                var result = await store.ListAsync(status, null, p, s, ct);
                return Results.Ok(new Paged<OrgApplicationDto>(result.Items.Select(ToDto).ToList(), result.Page, result.Size, result.Total));
            })
            .WithName("AdminOrgApplications").WithSummary("Заявки организаций по статусу").Produces<Paged<OrgApplicationDto>>();

        applications.MapPost("/{id:guid}/approve", ApproveAsync)
            .WithName("ApproveOrgApplication").WithSummary("Одобрить: создаётся администратор организации (org_admin) с приглашением, письмо «Заявка одобрена»")
            .Produces<ApplicationDecisionDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity).ProducesProblem(StatusCodes.Status409Conflict);

        applications.MapPost("/{id:guid}/reject", async (Guid id, RejectRequestDto body, HttpContext http, IOrgApplicationStore store, IEmailSender mail,
                AdminActions actions, TimeProvider time, CancellationToken ct) =>
            {
                var (application, problem) = await ReviewableAsync(id, store, ct);
                if (problem is not null)
                {
                    return problem;
                }

                var errors = new ValidationErrors().Require("reason", body.Reason);
                if (errors.Any)
                {
                    return errors.Problem();
                }

                var rejected = application! with
                {
                    Status = OrgApplicationStatuses.Rejected, DecidedAt = time.GetUtcNow(), DecidedBy = CurrentUser.From(http).Actor, RejectReason = body.Reason!.Trim(),
                };
                await store.SaveAsync(rejected, ct);
                await actions.RecordAsync(http, DecisionSubjects.OrgApplication, rejected.Number, new { status = application.Status },
                    new { status = rejected.Status }, rejected.RejectReason, ct);
                var sent = await mail.SendAsync(EmailTemplates.ApplicationRejected(rejected.Email, rejected.OrgName, rejected.Number, rejected.RejectReason!), ct);
                return Results.Ok(new ApplicationDecisionDto(rejected.Status, sent, null, null));
            })
            .WithName("RejectOrgApplication").WithSummary("Отклонить с причиной; письмо заявителю")
            .Produces<ApplicationDecisionDto>().ProducesValidationProblem(StatusCodes.Status422UnprocessableEntity);
    }

    public static OrgApplicationDto ToDto(OrgApplication a) => new(
        a.Id, a.Number, a.OrgName, a.Bin, a.Type, a.RegionKato, a.MoCode, a.AdminName, a.Email, a.Phone, a.Status, a.SubmittedAt, a.EmailVerifiedAt,
        a.DecidedAt, a.DecidedBy, a.RejectReason);

    private static async Task<IResult> ApproveAsync(Guid id, ApproveRequestDto? body, HttpContext http, IOrgApplicationStore store, InvitationService invitations,
        IEmailSender mail, AdminActions actions, TimeProvider time, CancellationToken ct)
    {
        var (application, problem) = await ReviewableAsync(id, store, ct);
        if (problem is not null)
        {
            return problem;
        }

        var moCode = string.IsNullOrWhiteSpace(body?.MoCode) ? application!.MoCode : body.MoCode.Trim();
        if (moCode is null)
        {
            return new ValidationErrors().Add("moCode", "укажите код организации из справочника — администратору организации он обязателен").Problem();
        }

        var actor = CurrentUser.From(http).Actor;
        var created = await invitations.CreateAsync(
            new InviteCommand(application!.Email, application.AdminName, Roles.OrgAdmin, moCode, application.RegionKato, application.Id), actor, ct);
        var approved = application with
        {
            Status = OrgApplicationStatuses.Approved, MoCode = moCode, DecidedAt = time.GetUtcNow(), DecidedBy = actor, InvitationId = created.Invitation.Id,
        };
        await store.SaveAsync(approved, ct);
        await actions.RecordAsync(http, DecisionSubjects.OrgApplication, approved.Number, new { status = application.Status },
            new { status = approved.Status, moCode }, null, ct);
        var sent = await mail.SendAsync(EmailTemplates.ApplicationApproved(approved.Email, approved.OrgName, approved.Number, created.Url,
            created.Invitation.ExpiresAt), ct);
        return Results.Ok(new ApplicationDecisionDto(approved.Status, sent, sent ? null : created.Url, created.Invitation.Id));
    }

    private static async Task<(OrgApplication? Application, IResult? Problem)> ReviewableAsync(Guid id, IOrgApplicationStore store, CancellationToken ct)
    {
        var application = await store.GetAsync(id, ct);
        if (application is null)
        {
            return (null, Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Заявка не найдена"));
        }

        return application.Status == OrgApplicationStatuses.PendingReview
            ? (application, null)
            : (null, Results.Problem(statusCode: StatusCodes.Status409Conflict, title: "Заявку нельзя рассмотреть",
                detail: application.Status == OrgApplicationStatuses.PendingEmail ? "почта заявителя ещё не подтверждена" : $"заявка уже {application.Status}"));
    }
}
