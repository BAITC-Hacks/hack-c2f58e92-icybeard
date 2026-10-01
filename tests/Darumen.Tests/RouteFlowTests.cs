using System.Net;
using System.Net.Http.Json;
using Darumen.Modules.Journal;

namespace Darumen.Tests;

/// <summary>Сценарии маршрута по состояниям (<see cref="RouteProgress"/>): кто и когда может действовать, что видят
/// гражданин, больница пациента и принимающая больница. Свой TestApp на каждый тест: синтетический гражданин —
/// один из пяти пациентов региона, и маршруты разных тестов иначе совпали бы.</summary>
public sealed class RouteFlowTests : IDisposable
{
    private readonly TestApp app = new();

    public void Dispose() => app.Dispose();

    private static string Today => RouteJournal.TodayAt(DateTimeOffset.UtcNow).ToString("yyyy-MM-dd");

    private sealed record Setup(HttpClient Citizen, RouteDto Route, HttpClient Origin, HttpClient Receiving, string ReceivingMoCode);

    private async Task<Setup> StartAsync(string name)
    {
        var citizen = app.CreateClient("citizen", $"c-flow-{name}");
        var route = (await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me"))!;
        var receivingMoCode = route.Organization.MoCode == "22GN" ? "028B" : "22GN";
        return new Setup(citizen, route,
            app.CreateClient("doctor", $"d-flow-{name}-origin", "75", route.Organization.MoCode),
            app.CreateClient("doctor", $"d-flow-{name}-receiving", "75", receivingMoCode),
            receivingMoCode);
    }

    private static async Task<Guid> RedirectAsync(Setup s, string? to = null)
    {
        var response = await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/redirect",
            new RouteRedirectRequestDto(to ?? s.ReceivingMoCode, "в принимающей больнице очередь короче"));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId;
    }

    private static async Task<RouteProgressDto> CitizenProgressAsync(Setup s) =>
        (await s.Citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me"))!.Progress!;

    [Fact]
    public async Task New_route_is_waiting_and_shows_only_the_actions_of_each_side()
    {
        var s = await StartAsync("new");
        Assert.Equal(RouteStatuses.Waiting, s.Route.Progress!.Status);
        Assert.Equal("citizen", s.Route.Progress.Side);
        Assert.Contains(RouteActions.RequestTransfer, s.Route.Progress.Allowed);
        Assert.DoesNotContain(RouteActions.Redirect, s.Route.Progress.Allowed);
        Assert.DoesNotContain(s.Route.Timeline, t => t.Code == RouteStages.Transfer);

        var doctorView = await s.Origin.GetFromJsonAsync<RouteDto>($"/api/v1/route/{s.Route.PatientRef}");
        Assert.Equal("origin", doctorView!.Progress!.Side);
        Assert.Contains(RouteActions.Redirect, doctorView.Progress.Allowed);
        Assert.Contains(RouteActions.Keep, doctorView.Progress.Allowed);
    }

    [Fact]
    public async Task Transfer_goes_through_consent_confirmation_and_admission_and_locks_the_route()
    {
        var s = await StartAsync("full");
        var decisionId = await RedirectAsync(s);

        var pending = await s.Citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Equal(RouteStatuses.TransferPendingConsent, pending!.Progress!.Status);
        Assert.Equal(RouteStages.Transfer, pending.Stage);
        Assert.Contains(pending.Timeline, t => t.Code == RouteStages.Transfer);
        Assert.DoesNotContain(RouteActions.RequestTransfer, pending.Progress.Allowed);

        // пока ждём пациента: второй перевод и просьба гражданина о переводе — 409
        Assert.Equal(HttpStatusCode.Conflict, (await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/redirect",
            new RouteRedirectRequestDto("027O", "ещё один"))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await s.Citizen.PostAsJsonAsync("/api/v1/route/me/signals",
            new RouteSignalRequestDto(RouteSignals.RequestRedirect, "027O", null))).StatusCode);

        Assert.Equal(HttpStatusCode.Created, (await s.Citizen.PostAsJsonAsync("/api/v1/route/me/consent",
            new RouteConsentRequestDto(decisionId, true, null))).StatusCode);
        Assert.Equal(RouteStatuses.TransferPendingConfirmation, (await CitizenProgressAsync(s)).Status);

        // дата обязательна и не дальше чем через 30 дней
        var confirmUrl = $"/api/v1/journal/referrals/{decisionId}/confirm";
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await s.Receiving.PostAsJsonAsync(confirmUrl, new ReferralConfirmRequestDto(s.Route.PatientRef, null))).StatusCode);
        var tooFar = RouteJournal.TodayAt(DateTimeOffset.UtcNow).AddDays(RouteProgress.MaxPlannedDays + 1).ToString("yyyy-MM-dd");
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await s.Receiving.PostAsJsonAsync(confirmUrl, new ReferralConfirmRequestDto(s.Route.PatientRef, null, tooFar))).StatusCode);
        Assert.Equal(HttpStatusCode.Created,
            (await s.Receiving.PostAsJsonAsync(confirmUrl, new ReferralConfirmRequestDto(s.Route.PatientRef, null, Today))).StatusCode);

        var transferred = await s.Citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Equal(RouteStatuses.Transferred, transferred!.Progress!.Status);
        Assert.Equal(Today, transferred.Dates.PlannedAt);
        Assert.Equal(RouteStages.DateAssigned, transferred.Stage);
        Assert.Equal(s.ReceivingMoCode, transferred.Organization.MoCode);
        Assert.Empty(transferred.Alternatives);
        Assert.False(transferred.ValidationDue);
        Assert.Equal(new[] { RouteActions.Withdraw }, transferred.Progress.Allowed);

        // больница пациента больше не решает: ни перевода, ни «оставить», ни отмены
        foreach (var path in new[] { "redirect", "keep", "cancel-transfer" })
        {
            var body = path == "redirect" ? (object)new RouteRedirectRequestDto("027O", "ещё раз") : new RouteReasonRequestDto("причина");
            Assert.Equal(HttpStatusCode.Conflict, (await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/{path}", body)).StatusCode);
        }

        // пациент — в рабочем списке принимающей больницы, а у больницы пациента его больше нет
        var receivingList = await s.Receiving.GetFromJsonAsync<WorklistResponseDto>($"/api/v1/journal/worklist?flag={WorklistBuilder.TransferredIn}");
        var row = Assert.Single(receivingList!.Items, i => i.PatientRef == s.Route.PatientRef);
        Assert.Equal(s.ReceivingMoCode, row.MoCode);
        Assert.Contains(WorklistBuilder.TransferredIn, row.RiskFlags);
        var originList = await s.Origin.GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.DoesNotContain(originList!.Items, i => i.PatientRef == s.Route.PatientRef);

        // в день госпитализации: госпитализирован, потом выписка закрывает маршрут
        var admit = await s.Receiving.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/admit", new ReferralReasonRequestDto(s.Route.PatientRef, null));
        Assert.Equal(HttpStatusCode.Created, admit.StatusCode);
        Assert.Equal(RouteStatuses.Admitted, (await CitizenProgressAsync(s)).Status);
        Assert.Equal(HttpStatusCode.Created, (await s.Receiving.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/discharge",
            new DischargeRequestDto(s.Route.PatientRef, "выписан с улучшением"))).StatusCode);

        var closed = await s.Citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Equal(RouteStatuses.Closed, closed!.Progress!.Status);
        Assert.Equal(RouteCloseReasons.Discharged, closed.Progress.ClosedReason);
        Assert.Empty(closed.Progress.Allowed);
        Assert.All(closed.Timeline, t => Assert.Equal(RouteTimelineStatus.Done, t.Status));
        // гражданину текст эпикриза не показывается — только факт выписки
        Assert.Null(Assert.Single(closed.Journal!, j => j.Kind == RouteJournalKinds.Discharge).Reason);
    }

    [Fact]
    public async Task Rejected_hospital_is_not_offered_again_and_the_patient_stays_in_their_queue()
    {
        var s = await StartAsync("reject");
        var decisionId = await RedirectAsync(s);
        await s.Citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, null));

        var url = $"/api/v1/journal/referrals/{decisionId}/reject";
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await s.Receiving.PostAsJsonAsync(url, new ReferralReasonRequestDto(s.Route.PatientRef, null))).StatusCode);
        Assert.Equal(HttpStatusCode.Created,
            (await s.Receiving.PostAsJsonAsync(url, new ReferralReasonRequestDto(s.Route.PatientRef, "нет мест по профилю"))).StatusCode);

        var progress = await CitizenProgressAsync(s);
        Assert.Equal(RouteStatuses.Kept, progress.Status);
        Assert.Equal(TransferOutcomes.Rejected, progress.LastAttempt!.Outcome);
        Assert.Equal("нет мест по профилю", progress.LastAttempt.Reason);
        Assert.Contains(s.ReceivingMoCode, progress.BlockedMoCodes);

        Assert.Equal(HttpStatusCode.Conflict, (await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/redirect",
            new RouteRedirectRequestDto(s.ReceivingMoCode, "попробуем снова"))).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await s.Citizen.PostAsJsonAsync("/api/v1/route/me/signals",
            new RouteSignalRequestDto(RouteSignals.RequestRedirect, s.ReceivingMoCode, null))).StatusCode);
        // отказавшая больница больше не видит это направление как входящее
        var incoming = await s.Receiving.GetFromJsonAsync<List<IncomingReferralDto>>("/api/v1/journal/referrals/incoming");
        Assert.DoesNotContain(incoming!, i => i.DecisionId == decisionId);
    }

    [Fact]
    public async Task Origin_can_cancel_an_unconfirmed_transfer_and_the_receiving_side_loses_it()
    {
        var s = await StartAsync("cancel");
        var decisionId = await RedirectAsync(s);
        await s.Citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, null));

        // отменить перевод может только больница пациента: у принимающей такого действия нет
        Assert.Equal(HttpStatusCode.Conflict, (await s.Receiving.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/cancel-transfer",
            new RouteReasonRequestDto("не наш"))).StatusCode);
        Assert.Equal(HttpStatusCode.Created, (await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/cancel-transfer",
            new RouteReasonRequestDto("пациенту подошла дата у нас"))).StatusCode);

        var progress = await CitizenProgressAsync(s);
        Assert.Equal(RouteStatuses.Kept, progress.Status);
        Assert.Equal(TransferOutcomes.Cancelled, progress.LastAttempt!.Outcome);
        Assert.Equal(HttpStatusCode.NotFound, (await s.Receiving.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/confirm",
            new ReferralConfirmRequestDto(s.Route.PatientRef, null, Today))).StatusCode);
    }

    [Fact]
    public async Task Withdrawal_is_confirmed_by_the_responsible_hospital_and_closes_the_route()
    {
        var s = await StartAsync("withdraw");
        Assert.Equal(HttpStatusCode.Created, (await s.Citizen.PostAsJsonAsync("/api/v1/route/me/signals",
            new RouteSignalRequestDto(RouteSignals.TreatedElsewhere, null, "прооперировали платно"))).StatusCode);
        Assert.Equal(RouteStatuses.WithdrawalRequested, (await CitizenProgressAsync(s)).Status);

        // пока просьба не разобрана, перевести нельзя; снять — только с причиной
        Assert.Equal(HttpStatusCode.Conflict, (await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/redirect",
            new RouteRedirectRequestDto(s.ReceivingMoCode, "быстрее"))).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/close", new RouteReasonRequestDto(null))).StatusCode);
        Assert.Equal(HttpStatusCode.Created,
            (await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/close", new RouteReasonRequestDto("подтверждено звонком"))).StatusCode);

        var progress = await CitizenProgressAsync(s);
        Assert.Equal(RouteStatuses.Closed, progress.Status);
        Assert.Equal(RouteEvents.ClosedTreatedElsewhere, progress.ClosedReason);
        Assert.Equal(HttpStatusCode.Conflict, (await s.Citizen.PostAsJsonAsync("/api/v1/route/me/signals",
            new RouteSignalRequestDto(RouteSignals.StillWaiting, null, null))).StatusCode);
        var list = await s.Origin.GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.DoesNotContain(list!.Items, i => i.PatientRef == s.Route.PatientRef);
    }

    [Fact]
    public async Task Prefer_current_stops_offers_but_the_doctor_can_still_propose_a_transfer()
    {
        var s = await StartAsync("stay");
        Assert.Equal(HttpStatusCode.Created, (await s.Citizen.PostAsJsonAsync("/api/v1/route/me/signals",
            new RouteSignalRequestDto(RouteSignals.PreferCurrent, null, null))).StatusCode);
        var progress = await CitizenProgressAsync(s);
        Assert.True(progress.PrefersCurrent);
        Assert.DoesNotContain(RouteActions.PreferCurrent, progress.Allowed);

        await RedirectAsync(s);
        Assert.Equal(RouteStatuses.TransferPendingConsent, (await CitizenProgressAsync(s)).Status);
    }

    [Fact]
    public async Task Citizen_bell_shows_what_others_did_and_needs_an_answer_for_a_proposed_transfer()
    {
        var s = await StartAsync("bell");
        await s.Citizen.PostAsJsonAsync("/api/v1/route/me/signals", new RouteSignalRequestDto(RouteSignals.StillWaiting, null, null));
        var empty = await s.Citizen.GetFromJsonAsync<CitizenNotificationsDto>("/api/v1/route/me/notifications");
        Assert.DoesNotContain(empty!.Items, i => i.Kind == RouteJournalKinds.StillWaiting); // свои действия — не уведомления

        var decisionId = await RedirectAsync(s);
        var bell = await s.Citizen.GetFromJsonAsync<CitizenNotificationsDto>("/api/v1/route/me/notifications");
        var proposal = Assert.Single(bell!.Items, i => i.Id == decisionId);
        Assert.Equal(RouteJournalKinds.Redirect, proposal.Kind);
        Assert.True(proposal.NeedsAction);
        Assert.False(proposal.Read);
        Assert.True(bell.Unread >= 1);

        Assert.Equal(HttpStatusCode.NoContent, (await s.Citizen.PostAsync($"/api/v1/route/me/notifications/{decisionId}/read", null)).StatusCode);
        var afterRead = await s.Citizen.GetFromJsonAsync<CitizenNotificationsDto>("/api/v1/route/me/notifications");
        Assert.True(Assert.Single(afterRead!.Items, i => i.Id == decisionId).Read);

        await s.Citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, null));
        await s.Receiving.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/confirm", new ReferralConfirmRequestDto(s.Route.PatientRef, null, Today));
        var confirmed = await s.Citizen.GetFromJsonAsync<CitizenNotificationsDto>("/api/v1/route/me/notifications");
        var confirmation = Assert.Single(confirmed!.Items, i => i.Kind == RouteJournalKinds.Confirm);
        Assert.Equal(Today, confirmation.PlannedAt);
        Assert.False(Assert.Single(confirmed.Items, i => i.Id == decisionId).NeedsAction);
    }

    [Fact]
    public async Task Repeated_request_with_the_same_key_returns_the_same_record_even_after_the_state_changed()
    {
        var s = await StartAsync("idem");
        s.Origin.DefaultRequestHeaders.Add(DecisionRecording.IdempotencyHeader, "flow-idem-1");
        var first = await RedirectAsync(s);
        var again = await s.Origin.PostAsJsonAsync($"/api/v1/route/{s.Route.PatientRef}/redirect",
            new RouteRedirectRequestDto(s.ReceivingMoCode, "в принимающей больнице очередь короче"));
        Assert.Equal(HttpStatusCode.OK, again.StatusCode);
        Assert.Equal(first, (await again.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId);
    }
}
