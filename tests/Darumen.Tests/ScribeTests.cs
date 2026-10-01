using System.Net;
using System.Net.Http.Json;
using Darumen.Modules.Journal;
using Darumen.Shared.Api;

namespace Darumen.Tests;

/// <summary>Согласие пациента на запись приёма: врач запрашивает, пациент отвечает в «Моём пути», запись — только по
/// действующему согласию (один приём), утверждённая памятка появляется у пациента. Свой TestApp на каждый тест.</summary>
public sealed class ScribeTests : IDisposable
{
    private readonly TestApp app = new();

    public void Dispose() => app.Dispose();

    private sealed record Setup(HttpClient Citizen, HttpClient Doctor, string PatientRef);

    private async Task<Setup> StartAsync(string name)
    {
        var citizen = app.CreateClient("citizen", $"c-scribe-{name}");
        var route = (await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me"))!;
        return new Setup(citizen, app.CreateClient("doctor", $"d-scribe-{name}", "75", route.Organization.MoCode), route.PatientRef);
    }

    private static async Task<Guid> RequestAsync(Setup s)
    {
        var response = await s.Doctor.PostAsJsonAsync("/api/v1/scribe-consents", new ScribeConsentRequestDto(s.PatientRef, "запишем приём, памятка придёт вам"));
        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        return (await response.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId;
    }

    private static Task<HttpResponseMessage> AnswerAsync(Setup s, Guid id, bool granted) =>
        s.Citizen.PostAsJsonAsync($"/api/v1/route/me/scribe/{id}/answer", new ScribeConsentAnswerDto(granted));

    private static Task<HttpResponseMessage> SessionAsync(Setup s, Guid? id) =>
        s.Doctor.PostAsJsonAsync("/api/v1/scribe/sessions", new ScribeSessionRequestDto(id, "ru"));

    private static async Task<ScribeConsentDto> CitizenViewAsync(Setup s, Guid id) =>
        Assert.Single((await s.Citizen.GetFromJsonAsync<List<ScribeConsentDto>>("/api/v1/route/me/scribe"))!, c => c.RequestId == id);

    [Fact]
    public async Task Recording_needs_the_patients_consent_and_the_leaflet_reaches_the_patient()
    {
        var s = await StartAsync("full");
        var id = await RequestAsync(s);

        var pending = await CitizenViewAsync(s, id);
        Assert.Equal(ScribeConsentStatuses.Pending, pending.Status);
        Assert.Equal("запишем приём, памятка придёт вам", pending.Comment);
        var bell = await s.Citizen.GetFromJsonAsync<CitizenNotificationsDto>("/api/v1/route/me/notifications");
        var ask = Assert.Single(bell!.Items, i => i.Id == id);
        Assert.Equal(CitizenNotifications.ScribeConsent, ask.Kind);
        Assert.True(ask.NeedsAction);

        // второй запрос, пока первый действует, — 409; записать без согласия или до ответа нельзя
        Assert.Equal(HttpStatusCode.Conflict,
            (await s.Doctor.PostAsJsonAsync("/api/v1/scribe-consents", new ScribeConsentRequestDto(s.PatientRef, null))).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await SessionAsync(s, null)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await SessionAsync(s, id)).StatusCode);
        Assert.Empty(app.Scribe.Created);

        Assert.Equal(HttpStatusCode.Created, (await AnswerAsync(s, id, true)).StatusCode);
        var started = await SessionAsync(s, id);
        Assert.Equal(HttpStatusCode.Created, started.StatusCode);
        var session = (await started.Content.ReadFromJsonAsync<ScribeSessionCreatedDto>())!;
        Assert.Equal(s.PatientRef, session.PatientRef);
        Assert.Equal(s.PatientRef, Assert.Single(app.Scribe.Created).PatientRef);

        // одно согласие — одна запись; после начала записи отозвать согласие нельзя
        Assert.Equal(HttpStatusCode.Conflict, (await SessionAsync(s, id)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await AnswerAsync(s, id, false)).StatusCode);
        Assert.Equal(ScribeConsentStatuses.Recording, (await CitizenViewAsync(s, id)).Status);
        Assert.Equal(session.SessionId, (await CitizenViewAsync(s, id)).SessionId); // врач может продолжить эту запись

        var approve = await s.Doctor.PostAsJsonAsync($"/api/v1/scribe/sessions/{session.SessionId}/approve",
            new ScribeApproveRequestDto([new ScribeSectionDto("Жалобы", "кашель")], "Пейте больше воды. Явка через 2 недели."));
        Assert.Equal(HttpStatusCode.OK, approve.StatusCode);
        var token = (await approve.Content.ReadFromJsonAsync<ScribeApprovedDto>())!.LeafletToken;

        var done = await CitizenViewAsync(s, id);
        Assert.Equal(ScribeConsentStatuses.Completed, done.Status);
        Assert.Equal(token, done.LeafletToken);
        var after = await s.Citizen.GetFromJsonAsync<CitizenNotificationsDto>("/api/v1/route/me/notifications");
        Assert.Contains(after!.Items, i => i.Kind == CitizenNotifications.ScribeLeaflet);
        Assert.DoesNotContain(after.Items, i => i.Kind == CitizenNotifications.ScribeConsent);

        // повторное утверждение — 409 от сервиса, новый запрос после завершения — можно
        Assert.Equal(HttpStatusCode.Conflict, (await s.Doctor.PostAsJsonAsync($"/api/v1/scribe/sessions/{session.SessionId}/approve",
            new ScribeApproveRequestDto([new ScribeSectionDto("Жалобы", "кашель")], "другая"))).StatusCode);
        await RequestAsync(s);
    }

    [Fact]
    public async Task Declined_or_withdrawn_consent_blocks_recording_and_allows_a_new_request()
    {
        var s = await StartAsync("decline");
        var declined = await RequestAsync(s);
        Assert.Equal(HttpStatusCode.Created, (await AnswerAsync(s, declined, false)).StatusCode);
        Assert.Equal(ScribeConsentStatuses.Declined, (await CitizenViewAsync(s, declined)).Status);
        Assert.Equal(HttpStatusCode.Conflict, (await SessionAsync(s, declined)).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await AnswerAsync(s, declined, true)).StatusCode);

        var withdrawn = await RequestAsync(s);
        await AnswerAsync(s, withdrawn, true);
        Assert.Equal(HttpStatusCode.Created, (await AnswerAsync(s, withdrawn, false)).StatusCode);
        Assert.Equal(ScribeConsentStatuses.Withdrawn, (await CitizenViewAsync(s, withdrawn)).Status);
        Assert.Equal(HttpStatusCode.Conflict, (await SessionAsync(s, withdrawn)).StatusCode);

        var cancelled = await RequestAsync(s);
        Assert.Equal(HttpStatusCode.Created, (await s.Doctor.PostAsJsonAsync($"/api/v1/scribe-consents/{cancelled}/cancel",
            new ScribeConsentRequestDto(s.PatientRef, null))).StatusCode);
        Assert.Equal(ScribeConsentStatuses.Cancelled, (await CitizenViewAsync(s, cancelled)).Status);
        Assert.Empty(app.Scribe.Created);
    }

    [Fact]
    public async Task Only_the_patients_hospital_can_ask_and_citizens_cannot_use_the_doctor_side()
    {
        var s = await StartAsync("access");
        var other = s.PatientRef.Contains("-22GN-") ? "028B" : "22GN";
        var stranger = app.CreateClient("doctor", "d-scribe-stranger", "75", other);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await stranger.PostAsJsonAsync("/api/v1/scribe-consents", new ScribeConsentRequestDto(s.PatientRef, null))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await s.Citizen.PostAsJsonAsync("/api/v1/scribe-consents", new ScribeConsentRequestDto(s.PatientRef, null))).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound,
            (await s.Doctor.PostAsJsonAsync("/api/v1/scribe-consents", new ScribeConsentRequestDto("SYN-75-XXXX-381-01", null))).StatusCode);

        var id = await RequestAsync(s);
        await AnswerAsync(s, id, true);
        // согласие дано больнице пациента: врач другой больницы не может им воспользоваться
        Assert.Equal(HttpStatusCode.Forbidden, (await stranger.PostAsJsonAsync("/api/v1/scribe/sessions", new ScribeSessionRequestDto(id, "ru"))).StatusCode);
    }

    [Fact]
    public async Task Unfinished_recording_does_not_block_a_new_request()
    {
        var s = await StartAsync("resume");
        var first = await RequestAsync(s);
        await AnswerAsync(s, first, true);
        Assert.Equal(HttpStatusCode.Created, (await SessionAsync(s, first)).StatusCode);

        // запись начата и брошена (страницу закрыли): согласие израсходовано, но можно попросить новое
        var second = await RequestAsync(s);
        Assert.NotEqual(first, second);
        Assert.Equal(ScribeConsentStatuses.Recording, (await CitizenViewAsync(s, first)).Status);
        Assert.Equal(ScribeConsentStatuses.Pending, (await CitizenViewAsync(s, second)).Status);

        // брошенную запись врач отменяет: аудио удаляется в сервисе, повторно отменить или утвердить её нельзя
        var discard = await s.Doctor.PostAsJsonAsync($"/api/v1/scribe-consents/{first}/discard", new ScribeConsentRequestDto(s.PatientRef, null));
        Assert.Equal(HttpStatusCode.Created, discard.StatusCode);
        Assert.Equal(ScribeConsentStatuses.Discarded, (await CitizenViewAsync(s, first)).Status);
        Assert.Single(app.Scribe.Discarded);
        Assert.Equal(HttpStatusCode.Conflict,
            (await s.Doctor.PostAsJsonAsync($"/api/v1/scribe-consents/{first}/discard", new ScribeConsentRequestDto(s.PatientRef, null))).StatusCode);
    }

    [Fact]
    public async Task Doctor_bell_shows_what_the_patient_did_until_read()
    {
        var s = await StartAsync("bell");
        Assert.Equal(HttpStatusCode.Created, (await s.Citizen.PostAsJsonAsync("/api/v1/route/me/signals",
            new RouteSignalRequestDto(RouteSignals.PreferCurrent, null, "хочу остаться"))).StatusCode);
        var id = await RequestAsync(s);
        await AnswerAsync(s, id, false);

        var bell = (await s.Doctor.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell"))!;
        var stay = Assert.Single(bell.PatientSignals!, x => x.Kind == RouteJournalKinds.PreferCurrent);
        Assert.Equal(s.PatientRef, stay.PatientRef);
        Assert.Equal("хочу остаться", stay.Comment);
        Assert.Contains(bell.PatientSignals!, x => x.Kind == PatientSignals.ScribeDeclined && x.PatientRef == s.PatientRef);

        // прочитано — пропадает; врач чужой больницы этих событий не видит
        Assert.Equal(HttpStatusCode.NoContent,
            (await s.Doctor.PostAsync($"/api/v1/journal/notifications/bell/{NotificationKinds.PatientSignal}/{stay.Id}/read", null)).StatusCode);
        var after = (await s.Doctor.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell"))!;
        Assert.DoesNotContain(after.PatientSignals!, x => x.Id == stay.Id);
        var other = s.PatientRef.Contains("-22GN-") ? "028B" : "22GN";
        var stranger = (await app.CreateClient("doctor", "d-bell-stranger", "75", other).GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell"))!;
        Assert.DoesNotContain(stranger.PatientSignals ?? [], x => x.PatientRef == s.PatientRef);
    }

    [Fact]
    public void Unused_consent_expires_after_its_day()
    {
        var at = new DateTimeOffset(2026, 10, 1, 6, 0, 0, TimeSpan.Zero);
        var request = new DecisionDto(Guid.NewGuid(), "doctor1", "doctor", DecisionSubjects.Scribe, "SYN-75-028B-381-01", null,
            System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(ScribeConsents.RequestJson("028B")), null, at);
        var granted = new DecisionDto(Guid.NewGuid(), "citizen1", "citizen", DecisionSubjects.Scribe, "SYN-75-028B-381-01", null,
            System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(ScribeConsents.AnswerJson(ScribeConsentStatuses.Granted, request.DecisionId)),
            null, at.AddMinutes(5));

        Assert.Equal(ScribeConsentStatuses.Granted, Assert.Single(ScribeConsents.From([granted, request], new DateOnly(2026, 10, 1))).Status);
        Assert.Equal(ScribeConsentStatuses.Expired, Assert.Single(ScribeConsents.From([granted, request], new DateOnly(2026, 10, 2))).Status);
    }
}
