using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Darumen.Contracts.V1;
using Darumen.Modules.Journal;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;
using Darumen.Tests.Fakes;
using Grpc.Core;

namespace Darumen.Tests;

/// <summary>Маршрут пациента: отдельный класс — отдельный TestApp, чтобы записи решений здесь не пересекались
/// с тестами журнала, которые считают события в своём экземпляре.</summary>
public sealed class RouteTests(TestApp app) : IClassFixture<TestApp>
{
    private const string Citizen = "citizen1";

    /// <summary>Маршрут пациента читает решения по своему рефу: фильтр subjectId возвращает только их.</summary>
    [Fact]
    public async Task Decisions_can_be_filtered_by_subject_id()
    {
        var client = app.CreateClient("doctor", "doctor-3", "75");
        var moCode = JsonDocument.Parse("{\"moCode\":\"22GN\"}").RootElement;
        await client.PostAsJsonAsync("/api/v1/journal/decisions", new DecisionRequestDto(DecisionSubjects.Route, "SYN-75-027O-021-01", moCode, moCode, "короче ожидание"));
        await client.PostAsJsonAsync("/api/v1/journal/decisions", new DecisionRequestDto(DecisionSubjects.Route, "SYN-75-027O-021-02", moCode, moCode, null));

        var one = await client.GetFromJsonAsync<Paged<DecisionDto>>("/api/v1/journal/decisions?subject=route&subjectId=SYN-75-027O-021-01");
        var item = Assert.Single(one!.Items);
        Assert.Equal("SYN-75-027O-021-01", item.SubjectId);
        Assert.Equal("22GN", item.Chosen!.Value.GetProperty("moCode").GetString());
        Assert.True((await client.GetFromJsonAsync<Paged<DecisionDto>>("/api/v1/journal/decisions?subject=route"))!.Items.Count >= 2);
    }

    /// <summary>Персона гражданина — из первых десяти «застрявших» строк списка врача (врач видит её на первом
    /// экране), но никогда из профилей, привязанных к полу и беременности: у синтетического гражданина пола нет.</summary>
    [Fact]
    public void Citizen_persona_comes_from_the_top_of_the_worklist_and_skips_sex_specific_profiles()
    {
        var asOf = InMemoryWorklist.AsOf;
        var states = new List<QueueStateRow>
        {
            new(asOf, "0285", "Роддом №1", "251", "75", 600, 60, 80, 1.0, 0.05, 1, 3),
            new(asOf, "027S", "Детская больница", "142", "75", 600, 60, 80, 1.0, 0.05, 1, 3),
            new(asOf, "028B", "Институт глазных болезней", "381", "75", 1784, 47, 90, 11.4, 0.32, 55, 66),
            new(asOf, "22GN", "Городская больница №2", "381", "75", 12, 3, 8, 4.0, 0.02, 9, 20),
        };
        var predictions = new Dictionary<(string MoCode, string ProfileCode), QueuePrediction>
        {
            [("0285", "251")] = new(1, 3, 0.05, true),
            [("027S", "142")] = new(1, 3, 0.05, true),
            [("028B", "381")] = new(55, 66, 0.32, true),
            [("22GN", "381")] = new(9, 20, 0.02, true),
        };
        var population = WorklistBuilder.Build(states, predictions);
        Assert.Contains(population[0].ProfileCode, new[] { "251", "142" });   // «пережидают» прогноз в разы — вершина списка врача

        var excluded = RouteBuilder.ExcludedProfiles(new[]
        {
            new ProfileDto("251", "Гинекологические для взрослых, включая для производства абортов", false, 5),
            new ProfileDto("142", "Торакальной хирургии для детей", false, 3),
            new ProfileDto("381", "Офтальмологические для взрослых", false, 1784),
        });
        Assert.Equal(new HashSet<string> { "231", "241", "251", "142" }, excluded);

        var eligible = population
            .Where(i => !excluded.Contains(i.ProfileCode))
            .Where(i => i.RiskFlags.Contains(WorklistBuilder.StuckOver30) || i.RiskFlags.Contains(WorklistBuilder.FasterAlternative))
            .Take(RouteBuilder.CitizenCandidates).Select(i => i.PatientRef).ToList();
        Assert.NotEmpty(eligible);
        for (var i = 0; i < 20; i++)
        {
            Assert.Contains(RouteBuilder.PickPatientRef(population, $"00000000{i:D4}", excluded), eligible);
        }

        Assert.Equal(RouteBuilder.PickPatientRef(population, "000000000001", excluded), RouteBuilder.PickPatientRef(population, "000000000001", excluded));
    }

    [Fact]
    public async Task Citizen_route_is_deterministic_and_is_one_of_the_regions_worklist_patients()
    {
        var citizen = app.CreateClient("citizen", Citizen);
        var first = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var second = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Equal(first!.PatientRef, second!.PatientRef);
        Assert.True(first.Synthetic);
        Assert.Equal(RouteAudience.Citizen, first.Audience);
        Assert.Equal("75", first.RegionKato);
        Assert.Equal("2025-03-31", first.AsOf);
        Assert.Null(first.Doctor);
        Assert.True(first.Forecast.FromModel);
        Assert.NotNull(first.Forecast.PWithin30Days);
        Assert.Contains(first.Stage, new[] { RouteStages.Waitlisted, RouteStages.DateAssigned });
        Assert.Single(first.Timeline, t => t.Status == RouteTimelineStatus.Current && t.Code == first.Stage);
        Assert.True(first.Standard.Available);
        Assert.Equal(4, first.Checklist.Count);
        Assert.Contains(first.Benchmarks, b => b.Code == "moh_target_wait_days" && b.Value == 20);
        Assert.InRange(first.History.Count, RouteBuilder.HistoryMin, RouteBuilder.HistoryMin + 1);
        Assert.NotEmpty(first.Alternatives);
        Assert.Equal("Офтальмологические для взрослых", first.Organization.ProfileName);

        var worklist = await app.CreateClient("doctor", "doctor1", "75").GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.Contains(worklist!.Items, i => i.PatientRef == first.PatientRef);
    }

    /// <summary>Чистый построитель: стадия и статусы чек-листа — только по датам. Пациент ждёт 47 дней, значит все
    /// 14-дневные обследования, сданные до регистрации, уже истекли, а флюорография (12 месяцев) действует.</summary>
    [Fact]
    public async Task Stage_and_checklist_status_follow_dates_only()
    {
        var standard = await new InMemoryRefData().RouteStandardAsync("ru", CancellationToken.None);
        var states = await new InMemoryWorklist().QueueStatesAsync("75", CancellationToken.None);
        var state = states[0];
        var waiting = Item(WorklistBuilder.StageWaiting, daysWaiting: 47, expectedDate: "2025-04-20");
        var route = RouteBuilder.Build(Inputs(waiting, state, states, standard));

        Assert.Equal(RouteStages.Waitlisted, route.Stage);
        Assert.Equal("2025-02-12", route.Dates.RegisteredAt);
        Assert.Null(route.Dates.PlannedAt);
        Assert.False(route.Forecast.FromModel);
        Assert.Null(route.Forecast.PWithin30Days);
        Assert.Equal(RouteTimelineStatus.Done, route.Timeline.Single(t => t.Code == RouteStages.ReferralIssued).Status);
        Assert.Equal(RouteTimelineStatus.Upcoming, route.Timeline.Single(t => t.Code == RouteStages.Hospitalized).Status);
        Assert.Null(route.Timeline.Single(t => t.Code == RouteStages.Hospitalized).Date);
        Assert.All(route.Checklist.Where(c => c.ValidityDays == 14), c => Assert.Equal(RouteChecklistStatus.Expired, c.Status));
        Assert.Equal(RouteChecklistStatus.Valid, route.Checklist.Single(c => c.Code == "fluorography").Status);

        var called = Item(WorklistBuilder.StageCalled, daysWaiting: 3, expectedDate: "2025-04-02");
        var soon = RouteBuilder.Build(Inputs(called, state, states, standard));
        Assert.Equal(RouteStages.DateAssigned, soon.Stage);
        Assert.Equal("2025-04-02", soon.Dates.PlannedAt);
        Assert.Equal(RouteTimelineStatus.Current, soon.Timeline.Single(t => t.Code == RouteStages.DateAssigned).Status);
    }

    [Fact]
    public async Task Fourteen_day_tests_expire_when_the_wait_exceeds_their_validity()
    {
        var standard = await new InMemoryRefData().RouteStandardAsync("ru", CancellationToken.None);
        var states = await new InMemoryWorklist().QueueStatesAsync("75", CancellationToken.None);
        var fresh = RouteBuilder.Build(Inputs(Item(WorklistBuilder.StageWaiting, daysWaiting: 2, expectedDate: "2025-04-05"), states[0], states, standard));
        Assert.DoesNotContain(fresh.Checklist, c => c.Status == RouteChecklistStatus.Expired);
        var stale = RouteBuilder.Build(Inputs(Item(WorklistBuilder.StageWaiting, daysWaiting: 60, expectedDate: "2025-04-05"), states[0], states, standard));
        Assert.All(stale.Checklist.Where(c => c.ValidityDays == 14), c => Assert.Equal(RouteChecklistStatus.Expired, c.Status));
    }

    [Fact]
    public async Task History_outcomes_follow_the_queues_refusal_rate_and_wait_quantiles()
    {
        var standard = await new InMemoryRefData().RouteStandardAsync("ru", CancellationToken.None);
        var item = Item(WorklistBuilder.StageWaiting, daysWaiting: 10, expectedDate: "2025-04-10");
        var alwaysRefuses = new QueueStateRow(InMemoryWorklist.AsOf, "M1", "Тест", "381", "75", 10, 5, 10, 2.0, 1.0, 20, 40);
        var neverRefuses = alwaysRefuses with { RefusalRate4w = 0.0 };

        var refused = RouteBuilder.Build(Inputs(item, alwaysRefuses, [alwaysRefuses], standard));
        Assert.All(refused.History, h => Assert.Equal(RouteOutcomes.Refused, h.Outcome));
        var hospitalized = RouteBuilder.Build(Inputs(item, neverRefuses, [neverRefuses], standard));
        Assert.All(hospitalized.History, h => Assert.Equal(RouteOutcomes.Hospitalized, h.Outcome));
        Assert.All(hospitalized.History, h => Assert.InRange(h.WaitDays, 20, 40));
        Assert.All(hospitalized.History, h => Assert.True(string.CompareOrdinal(h.RegisteredAt, "2025-03-31") < 0));
    }

    /// <summary>Сквозной сценарий защиты: врач перенаправляет пациента из рабочего списка, гражданин видит решение
    /// на своём маршруте; повтор с тем же Idempotency-Key не создаёт второй записи.</summary>
    [Fact]
    public async Task Doctor_redirect_is_visible_on_the_citizens_route()
    {
        var citizen = app.CreateClient("citizen", Citizen);
        var route = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var doctor = app.CreateClient("doctor", "doctor1", "75");
        doctor.DefaultRequestHeaders.Add(DecisionRecording.IdempotencyHeader, "route-k-1");
        var body = new RouteRedirectRequestDto("22GN", "ожидание короче, профиль совпадает");

        var first = await doctor.PostAsJsonAsync($"/api/v1/route/{route!.PatientRef}/redirect", body);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        var created = await first.Content.ReadFromJsonAsync<DecisionCreatedDto>();
        var second = await doctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/redirect", body);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(created!.DecisionId, (await second.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId);

        var after = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var decision = Assert.Single(after!.Decisions, d => d.DecisionId == created.DecisionId);
        Assert.Equal(RouteDecisionKinds.Redirect, decision.Kind);
        Assert.Equal("22GN", decision.ToMoCode);
        Assert.Equal("Городская больница №2", decision.ToMoName);
        Assert.Equal("doctor", decision.Role);

        var same = await doctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/redirect", new RouteRedirectRequestDto(route.Organization.MoCode, "та же"));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, same.StatusCode);
        var noReason = await doctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/redirect", new RouteRedirectRequestDto("22GN", null));
        Assert.Equal(HttpStatusCode.UnprocessableEntity, noReason.StatusCode);
    }

    /// <summary>Двусторонний маршрут: просьба гражданина «рассмотреть организацию быстрее» поднимает его в рабочем
    /// списке врача с флагом и остаётся открытой, пока врач не ответит решением; «оставить» с причиной закрывает её,
    /// гражданин видит и сигнал, и ответ. Повтор с тем же Idempotency-Key не создаёт второй записи.</summary>
    [Fact]
    public async Task Citizen_signal_reaches_the_doctors_worklist_and_a_keep_decision_closes_it()
    {
        var citizen = app.CreateClient("citizen", "c-signal");
        var route = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var alternative = route!.Organization.MoCode == "22GN" ? "028B" : "22GN";
        citizen.DefaultRequestHeaders.Add(DecisionRecording.IdempotencyHeader, "sig-1");
        var body = new RouteSignalRequestDto(RouteSignals.RequestRedirect, alternative, "живу рядом");

        var first = await citizen.PostAsJsonAsync("/api/v1/route/me/signals", body);
        Assert.Equal(HttpStatusCode.Created, first.StatusCode);
        var created = await first.Content.ReadFromJsonAsync<DecisionCreatedDto>();
        var second = await citizen.PostAsJsonAsync("/api/v1/route/me/signals", body);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(created!.DecisionId, (await second.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId);

        var after = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var signal = Assert.Single(after!.Signals, s => s.DecisionId == created.DecisionId);
        Assert.True(signal.Open);
        Assert.Equal(alternative, signal.ToMoCode);
        Assert.Equal("живу рядом", signal.Comment);
        Assert.DoesNotContain(after.Decisions, d => d.DecisionId == created.DecisionId);
        Assert.True(after.ValidationDue);

        var doctor = app.CreateClient("doctor", "doctor-sig", "75");
        var worklist = await doctor.GetFromJsonAsync<WorklistResponseDto>($"/api/v1/journal/worklist?flag={WorklistBuilder.PatientSignal}");
        var row = Assert.Single(worklist!.Items, i => i.PatientRef == route.PatientRef);
        Assert.Contains(WorklistBuilder.PatientSignal, row.RiskFlags);
        Assert.Equal(RouteSignals.RequestRedirect, row.PatientSignal!.Kind);
        Assert.Equal(alternative, row.PatientSignal.ToMoCode);
        var doctorRoute = await doctor.GetFromJsonAsync<RouteDto>($"/api/v1/route/{route.PatientRef}");
        Assert.Contains(WorklistBuilder.PatientSignal, doctorRoute!.Doctor!.RiskFlags);

        doctor.DefaultRequestHeaders.Add(DecisionRecording.IdempotencyHeader, "keep-1");
        var keep = await doctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/keep", new RouteKeepRequestDto("профиль требует именно этой клиники"));
        Assert.Equal(HttpStatusCode.Created, keep.StatusCode);
        var keepId = (await keep.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId;
        Assert.Equal(HttpStatusCode.UnprocessableEntity, (await doctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/keep", new RouteKeepRequestDto(null))).StatusCode);

        var closed = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.False(Assert.Single(closed!.Signals, s => s.DecisionId == created.DecisionId).Open);
        var answer = Assert.Single(closed.Decisions, d => d.DecisionId == keepId);
        Assert.Equal(RouteDecisionKinds.Keep, answer.Kind);
        Assert.Equal("профиль требует именно этой клиники", answer.Reason);
        var listAfter = await doctor.GetFromJsonAsync<WorklistResponseDto>($"/api/v1/journal/worklist?flag={WorklistBuilder.PatientSignal}");
        Assert.DoesNotContain(listAfter!.Items, i => i.PatientRef == route.PatientRef);
    }

    /// <summary>Валидация листа ожидания: новый маршрут просит подтвердить ожидание, «ещё жду» снимает вопрос на 30 дней;
    /// незнакомый вид сигнала и просьба «быстрее» в свою же организацию — 422; сигналы шлёт только гражданин.</summary>
    [Fact]
    public async Task Still_waiting_confirmation_clears_validation_due_and_bad_signals_are_rejected()
    {
        var citizen = app.CreateClient("citizen", "c-valid");
        var route = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.True(route!.ValidationDue);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await citizen.PostAsJsonAsync("/api/v1/route/me/signals", new RouteSignalRequestDto("nap", null, null))).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await citizen.PostAsJsonAsync("/api/v1/route/me/signals", new RouteSignalRequestDto(RouteSignals.RequestRedirect, route.Organization.MoCode, null))).StatusCode);
        Assert.Equal(HttpStatusCode.UnprocessableEntity,
            (await citizen.PostAsJsonAsync("/api/v1/route/me/signals", new RouteSignalRequestDto(RouteSignals.RequestRedirect, null, null))).StatusCode);

        Assert.Equal(HttpStatusCode.Created,
            (await citizen.PostAsJsonAsync("/api/v1/route/me/signals", new RouteSignalRequestDto(RouteSignals.StillWaiting, null, null))).StatusCode);
        var after = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.False(after!.ValidationDue);
        Assert.Equal(RouteSignals.StillWaiting, after.Signals[0].Kind);
        Assert.Null(after.Signals[0].ToMoCode);

        Assert.Equal(HttpStatusCode.Forbidden,
            (await app.CreateClient("doctor", "doctor1", "75").PostAsJsonAsync("/api/v1/route/me/signals", new RouteSignalRequestDto(RouteSignals.StillWaiting, null, null))).StatusCode);
    }

    [Fact]
    public async Task Route_me_is_for_citizens_only()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await app.CreateClient().GetAsync("/api/v1/route/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient("doctor", "doctor1", "75").GetAsync("/api/v1/route/me")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await app.CreateClient("admin", "admin1").GetAsync("/api/v1/route/me")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await app.CreateClient("citizen", "c-10").GetAsync("/api/v1/route/me?regionKato=10")).StatusCode);
    }

    [Fact]
    public async Task Doctor_route_lookup_returns_404_for_unknown_ref_and_403_for_another_region()
    {
        var doctor = app.CreateClient("doctor", "doctor1", "75");
        Assert.Equal(HttpStatusCode.OK, (await doctor.GetAsync("/api/v1/route/SYN-75-028B-381-01")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await doctor.GetAsync("/api/v1/route/SYN-75-028B-381-99")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await doctor.GetAsync("/api/v1/route/nonsense")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient("doctor", "doctor2", "10").GetAsync("/api/v1/route/SYN-75-028B-381-01")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient("citizen", Citizen).GetAsync("/api/v1/route/SYN-75-028B-381-01")).StatusCode);
    }

    [Fact]
    public async Task Route_survives_model_outage_with_aggregate_fallback()
    {
        var predictWait = app.Queue.OnPredictWait;
        var predictRefusal = app.Queue.OnPredictRefusal;
        app.Queue.OnPredictWait = _ => throw new RpcException(new Status(StatusCode.Unavailable, "models down"));
        app.Queue.OnPredictRefusal = _ => throw new RpcException(new Status(StatusCode.Unavailable, "models down"));
        try
        {
            var response = await app.CreateClient("citizen", Citizen).GetAsync("/api/v1/route/me");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);
            var route = await response.Content.ReadFromJsonAsync<RouteDto>();
            Assert.False(route!.Forecast.FromModel);
            Assert.Null(route.Forecast.PWithin30Days);
            Assert.Null(route.Forecast.Model);
            Assert.True(route.Forecast.P50Days > 0);
        }
        finally
        {
            app.Queue.OnPredictWait = predictWait;
            app.Queue.OnPredictRefusal = predictRefusal;
        }
    }

    [Fact]
    public async Task Citizen_view_hides_doctor_panel_and_doctor_view_shows_it()
    {
        var citizen = await app.CreateClient("citizen", Citizen).GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Null(citizen!.Doctor);
        var doctor = await app.CreateClient("doctor", "doctor1", "75").GetFromJsonAsync<RouteDto>($"/api/v1/route/{citizen.PatientRef}");
        Assert.Equal(RouteAudience.Doctor, doctor!.Audience);
        Assert.NotNull(doctor.Doctor);
        Assert.Equal(0.08, doctor.Doctor!.PRefusal, 3);
        Assert.NotNull(doctor.Doctor.Shap);
        Assert.Equal(citizen.PatientRef, doctor.PatientRef);
        Assert.Equal(citizen.Stage, doctor.Stage);

        var kk = app.CreateClient("citizen", Citizen);
        kk.DefaultRequestHeaders.Add("Accept-Language", "kk");
        var kazakh = await kk.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Contains("Синтетикалық", kazakh!.Basis);
        Assert.Equal("Күту парағына енгізілді", kazakh.Timeline.Single(t => t.Code == RouteStages.Waitlisted).Title);
    }

    private static WorklistItemDto Item(string stageCode, int daysWaiting, string expectedDate) => new(
        "SYN-75-028B-381-01", true, "ожидает", stageCode, expectedDate, [], 0, "ждать вызова", WorklistBuilder.ActionWaitForCall, "тест", "028B", "Институт глазных болезней", "381", "75", daysWaiting);

    private static RouteBuilder.Inputs Inputs(WorklistItemDto item, QueueStateRow state, IReadOnlyList<QueueStateRow> states, RouteStandardDto standard) =>
        new(item, state, states, standard, null, null, [], new Dictionary<string, string>(), RouteAudience.Citizen, "ru");
}
