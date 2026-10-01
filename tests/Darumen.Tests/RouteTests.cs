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

/// <summary>Маршрут пациента: свой TestApp на каждый тест — записи решений не пересекаются ни с тестами журнала, ни
/// между собой (гражданин — один из пяти пациентов региона, а маршрут хранит состояние: перевод, согласие).</summary>
public sealed class RouteTests : IDisposable
{
    private readonly TestApp app = new();

    public void Dispose() => app.Dispose();

    private const string Citizen = "citizen1";

    /// <summary>«Сегодня» по Казахстану — дата госпитализации при подтверждении (сегодня..+30 дней).</summary>
    private static string Today => RouteJournal.TodayAt(DateTimeOffset.UtcNow).ToString("yyyy-MM-dd");

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

        // admin (worklist.view: all) — чтобы проверка не зависела от того, в какую организацию региона (028B/22GN/027O)
        // попадёт детерминированный пациент гражданина; после задачи 1.2 (worklist.view врача — own) обычный врач
        // видит только свою организацию и для этой проверки не подходит.
        var worklist = await app.CreateClient("admin", "admin-worklist-check").GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist?regionKato=75");
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
        var doctor = app.CreateClient("doctor", "doctor1", "75", route!.Organization.MoCode);
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

    /// <summary>Согласие пациента: redirect больше не вступает в силу сам по себе — до ответа гражданина решение
    /// висит в статусе pending, виден и пациенту, и врачу; Severe — клинический флаг тяжести, независимый от очереди.</summary>
    [Fact]
    public async Task Redirect_requires_patient_consent_and_carries_the_severity_flag()
    {
        var citizen = app.CreateClient("citizen", "c-consent");
        var route = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        // moCode = организация-отправитель (route.Organization.MoCode): GET /route/{ref} ниже требует worklist.view,
        // у врача это own (задача 1.2) — без совпадающего moCode получил бы 403 no_organization вместо ожидаемого 200.
        var doctor = app.CreateClient("doctor", "doctor-consent", "75", route!.Organization.MoCode);
        var alternative = route.Organization.MoCode == "22GN" ? "028B" : "22GN";

        var redirect = await doctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/redirect",
            new RouteRedirectRequestDto(alternative, "требуется профиль другой клиники", Severe: true));
        Assert.Equal(HttpStatusCode.Created, redirect.StatusCode);
        var decisionId = (await redirect.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId;

        var pending = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var pendingDecision = Assert.Single(pending!.Decisions, d => d.DecisionId == decisionId);
        Assert.Equal(RouteConsent.Pending, pendingDecision.PatientConsent);
        Assert.True(pendingDecision.Severe);

        // тот же decisionId виден и врачу на маршруте пациента
        var doctorView = await doctor.GetFromJsonAsync<RouteDto>($"/api/v1/route/{route.PatientRef}");
        Assert.Equal(RouteConsent.Pending, Assert.Single(doctorView!.Decisions, d => d.DecisionId == decisionId).PatientConsent);

        // чужой decisionId — 404, а не тихое согласие на что-то другое
        var wrongId = await citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(Guid.NewGuid(), true, null));
        Assert.Equal(HttpStatusCode.NotFound, wrongId.StatusCode);

        var consent = await citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, "согласен"));
        Assert.Equal(HttpStatusCode.Created, consent.StatusCode);

        var after = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Equal(RouteConsent.Accepted, Assert.Single(after!.Decisions, d => d.DecisionId == decisionId).PatientConsent);

        // повторное согласие — 409: уже согласился, ждём больницу
        var again = await citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, null));
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);

        // до подтверждения больницей согласие можно отозвать; после отзыва перевода нет — ответить на него снова нельзя (404)
        var withdraw = await citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, false, "передумал"));
        Assert.Equal(HttpStatusCode.Created, withdraw.StatusCode);
        var withdrawn = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Equal(RouteStatuses.Kept, withdrawn!.Progress!.Status);
        var late = await citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, null));
        Assert.Equal(HttpStatusCode.NotFound, late.StatusCode);
    }

    /// <summary>Задача 4 плана прозрачности: /route/{patientRef} завязан на организацию-ОТПРАВИТЕЛЯ (она зашита в сам
    /// реф) — принимающая организация получает на нём 403. Видит и подтверждает направление она через отдельный
    /// список входящих (/journal/referrals/incoming) и не может подтвердить его, пока пациент не согласился
    /// (RouteConsent.Accepted) — human-in-the-loop с обеих сторон одного решения.</summary>
    [Fact]
    public async Task Incoming_referral_requires_patient_consent_before_the_receiving_organization_can_confirm_it()
    {
        var citizen = app.CreateClient("citizen", "c-incoming");
        var route = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var sendingDoctor = app.CreateClient("doctor", "doctor-incoming-send", "75", route!.Organization.MoCode);
        var receivingMoCode = route.Organization.MoCode == "22GN" ? "028B" : "22GN";

        var redirect = await sendingDoctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/redirect",
            new RouteRedirectRequestDto(receivingMoCode, "нужен профиль принимающей организации", Severe: true));
        Assert.Equal(HttpStatusCode.Created, redirect.StatusCode);
        var decisionId = (await redirect.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId;

        // у врача принимающей организации нет доступа к /route/{patientRef} — реф закодирован под отправителя
        var receivingDoctor = app.CreateClient("doctor", "doctor-incoming-receive", "75", receivingMoCode);
        var blocked = await receivingDoctor.GetAsync($"/api/v1/route/{route.PatientRef}");
        Assert.Equal(HttpStatusCode.Forbidden, blocked.StatusCode);

        // зато оно видно в списке входящих направлений принимающей организации, с флагом тяжести
        var incoming = await receivingDoctor.GetFromJsonAsync<List<IncomingReferralDto>>("/api/v1/journal/referrals/incoming?severe=true");
        var item = Assert.Single(incoming!, i => i.DecisionId == decisionId);
        Assert.Equal(route.PatientRef, item.PatientRef);
        Assert.True(item.Severe);
        Assert.Equal(RouteConsent.Pending, item.PatientConsent);
        Assert.False(item.Confirmed);

        // подтвердить нельзя, пока пациент не согласился
        var tooEarly = await receivingDoctor.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/confirm",
            new ReferralConfirmRequestDto(route.PatientRef, null));
        Assert.Equal(HttpStatusCode.Conflict, tooEarly.StatusCode);

        await citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, "согласен"));

        var confirm = await receivingDoctor.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/confirm",
            new ReferralConfirmRequestDto(route.PatientRef, "место подготовлено", Today));
        Assert.Equal(HttpStatusCode.Created, confirm.StatusCode);

        // подтверждённое направление по умолчанию больше не в списке несделанных, но видно с includeConfirmed=true
        var afterConfirm = await receivingDoctor.GetFromJsonAsync<List<IncomingReferralDto>>("/api/v1/journal/referrals/incoming");
        Assert.DoesNotContain(afterConfirm!, i => i.DecisionId == decisionId);
        var withConfirmed = await receivingDoctor.GetFromJsonAsync<List<IncomingReferralDto>>("/api/v1/journal/referrals/incoming?includeConfirmed=true");
        var confirmed = Assert.Single(withConfirmed!, i => i.DecisionId == decisionId);
        Assert.True(confirmed.Confirmed);
        Assert.NotNull(confirmed.ConfirmedAt);

        // повторное подтверждение — 409, не тихий успех
        var again = await receivingDoctor.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/confirm",
            new ReferralConfirmRequestDto(route.PatientRef, null, Today));
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);

        // после подтверждения пациент закреплён за принимающей больницей: она видит маршрут, дата — назначенная ею
        var receivingView = await receivingDoctor.GetFromJsonAsync<RouteDto>($"/api/v1/route/{route.PatientRef}");
        Assert.Equal(RouteStatuses.Transferred, receivingView!.Progress!.Status);
        Assert.Equal(Today, receivingView.Dates.PlannedAt);
        Assert.Equal(receivingMoCode, receivingView.Organization.MoCode);

        // организация-отправитель не видит собственное направление как «входящее» у себя
        var sendingSide = app.CreateClient("doctor", "doctor-incoming-send-view", "75", route.Organization.MoCode);
        var sendingIncoming = await sendingSide.GetFromJsonAsync<List<IncomingReferralDto>>("/api/v1/journal/referrals/incoming?includeConfirmed=true");
        Assert.DoesNotContain(sendingIncoming!, i => i.DecisionId == decisionId);

        // регрессия: запись-подтверждение ({"moCode","confirms":decisionId}) — тоже с полем "moCode", как и настоящий
        // redirect/keep, но это не отдельное решение маршрута — не должна попадать в RouteDto.Decisions как фиктивная
        // дублирующая строка ни у гражданина, ни у отправляющей стороны.
        var citizenAfterConfirm = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Equal(decisionId, Assert.Single(citizenAfterConfirm!.Decisions).DecisionId);
        var sendingRoute = await sendingSide.GetFromJsonAsync<RouteDto>($"/api/v1/route/{route.PatientRef}");
        Assert.Equal(decisionId, Assert.Single(sendingRoute!.Decisions).DecisionId);
    }

    /// <summary>Колокольчик (задача 13, упрощена до внутрисистемных уведомлений): после подтверждения направления
    /// отправляющая организация видит его как непрочитанное; отметка прочитанным убирает его из списка и не
    /// затрагивает счётчик входящих (это разные сущности одного и того же decisionId — своё vs чужое направление).</summary>
    [Fact]
    public async Task Bell_shows_unread_confirmation_to_the_sending_organization_until_marked_read()
    {
        var citizen = app.CreateClient("citizen", "c-bell");
        var route = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var sendingDoctor = app.CreateClient("doctor", "doctor-bell-send", "75", route!.Organization.MoCode);
        var receivingMoCode = route.Organization.MoCode == "22GN" ? "028B" : "22GN";

        var redirect = await sendingDoctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/redirect",
            new RouteRedirectRequestDto(receivingMoCode, "нужен профиль принимающей организации", Severe: false));
        var decisionId = (await redirect.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId;

        var sendingSide = app.CreateClient("doctor", "doctor-bell-send-view", "75", route.Organization.MoCode);
        var beforeConfirm = await sendingSide.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell");
        Assert.DoesNotContain(beforeConfirm!.UnreadConfirmations, c => c.DecisionId == decisionId);

        await citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, "согласен"));
        var receivingDoctor = app.CreateClient("doctor", "doctor-bell-receive", "75", receivingMoCode);
        await receivingDoctor.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/confirm", new ReferralConfirmRequestDto(route.PatientRef, null, Today));

        var afterConfirm = await sendingSide.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell");
        var item = Assert.Single(afterConfirm!.UnreadConfirmations, c => c.DecisionId == decisionId);
        Assert.Equal(receivingMoCode, item.ToMoCode);
        // Название организации — из справочника (refdata.mo_registry), не код: в колокольчике конечный пользователь
        // не должен видеть технический код вместо человеческого названия.
        var expectedName = receivingMoCode == "22GN" ? "Городская больница №2" : "Казахский ордена институт глазных болезней";
        Assert.Equal(expectedName, item.ToMoName);
        Assert.False(item.Read);

        // второй сотрудник той же отправляющей организации — общие данные направления, но своя отметка прочтения
        var colleague = app.CreateClient("doctor", "doctor-bell-colleague", "75", route.Organization.MoCode);
        var colleagueView = await colleague.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell");
        Assert.Contains(colleagueView!.UnreadConfirmations, c => c.DecisionId == decisionId);

        var markRead = await sendingSide.PostAsync($"/api/v1/journal/notifications/bell/{NotificationKinds.ReferralConfirmed}/{decisionId}/read", null);
        Assert.Equal(HttpStatusCode.NoContent, markRead.StatusCode);

        var afterRead = await sendingSide.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell");
        Assert.DoesNotContain(afterRead!.UnreadConfirmations, c => c.DecisionId == decisionId);

        // у коллеги без своей отметки — по-прежнему непрочитано (отметка личная, не на организацию)
        var colleagueStillUnread = await colleague.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell");
        Assert.Contains(colleagueStillUnread!.UnreadConfirmations, c => c.DecisionId == decisionId);
    }

    /// <summary>Выписка/эпикриз обратно направившему врачу (задача 11 плана прозрачности): закрыть лечение можно
    /// только после подтверждения приёма, повторная выписка — 409; направившая сторона видит эпикриз в колокольчике
    /// отдельно от уведомления о подтверждении (разные kind — прочтение одного не закрывает другое); запись выписки,
    /// как и подтверждение (регрессия задачи 4), не должна протекать фиктивной строкой в RouteDto.Decisions.</summary>
    [Fact]
    public async Task Discharge_requires_prior_confirmation_and_reaches_the_referring_doctor_separately_from_confirmation()
    {
        var citizen = app.CreateClient("citizen", "c-discharge");
        var route = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        var sendingDoctor = app.CreateClient("doctor", "doctor-discharge-send", "75", route!.Organization.MoCode);
        var receivingMoCode = route.Organization.MoCode == "22GN" ? "028B" : "22GN";

        var redirect = await sendingDoctor.PostAsJsonAsync($"/api/v1/route/{route.PatientRef}/redirect",
            new RouteRedirectRequestDto(receivingMoCode, "нужен профиль принимающей организации", Severe: false));
        var decisionId = (await redirect.Content.ReadFromJsonAsync<DecisionCreatedDto>())!.DecisionId;
        var receivingDoctor = app.CreateClient("doctor", "doctor-discharge-receive", "75", receivingMoCode);

        // выписать нельзя раньше подтверждения приёма
        var tooEarly = await receivingDoctor.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/discharge",
            new DischargeRequestDto(route.PatientRef, "пролечен, выписан"));
        Assert.Equal(HttpStatusCode.Conflict, tooEarly.StatusCode);

        await citizen.PostAsJsonAsync("/api/v1/route/me/consent", new RouteConsentRequestDto(decisionId, true, "согласен"));
        await receivingDoctor.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/confirm", new ReferralConfirmRequestDto(route.PatientRef, null, Today));

        var discharge = await receivingDoctor.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/discharge",
            new DischargeRequestDto(route.PatientRef, "госпитализация прошла успешно, рекомендовано наблюдение по месту жительства"));
        Assert.Equal(HttpStatusCode.Created, discharge.StatusCode);

        // повторная выписка — 409, не тихий успех
        var again = await receivingDoctor.PostAsJsonAsync($"/api/v1/journal/referrals/{decisionId}/discharge",
            new DischargeRequestDto(route.PatientRef, "ещё раз"));
        Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);

        // принимающая сторона видит статус выписки в своём же списке входящих (не только по ошибке 409)
        var ownIncoming = await receivingDoctor.GetFromJsonAsync<List<IncomingReferralDto>>("/api/v1/journal/referrals/incoming?includeConfirmed=true");
        var ownItem = Assert.Single(ownIncoming!, i => i.DecisionId == decisionId);
        Assert.True(ownItem.Discharged);
        Assert.NotNull(ownItem.DischargedAt);

        // направившая сторона видит эпикриз в колокольчике, отдельно от уведомления о подтверждении
        var sendingSide = app.CreateClient("doctor", "doctor-discharge-send-view", "75", route.Organization.MoCode);
        var bell = await sendingSide.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell");
        var dischargeItem = Assert.Single(bell!.UnreadDischarges, d => d.DecisionId == decisionId);
        Assert.Equal(receivingMoCode, dischargeItem.FromMoCode);
        Assert.Contains("госпитализация", dischargeItem.Summary);
        Assert.Contains(bell.UnreadConfirmations, c => c.DecisionId == decisionId); // подтверждение по-прежнему отдельно непрочитано

        // отметка «прочитано» для подтверждения не должна закрывать непрочитанную выписку (разные kind)
        await sendingSide.PostAsync($"/api/v1/journal/notifications/bell/{NotificationKinds.ReferralConfirmed}/{decisionId}/read", null);
        var afterConfirmRead = await sendingSide.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell");
        Assert.DoesNotContain(afterConfirmRead!.UnreadConfirmations, c => c.DecisionId == decisionId);
        Assert.Contains(afterConfirmRead.UnreadDischarges, d => d.DecisionId == decisionId);

        await sendingSide.PostAsync($"/api/v1/journal/notifications/bell/{NotificationKinds.ReferralDischarged}/{decisionId}/read", null);
        var afterDischargeRead = await sendingSide.GetFromJsonAsync<NotificationBellDto>("/api/v1/journal/notifications/bell");
        Assert.DoesNotContain(afterDischargeRead!.UnreadDischarges, d => d.DecisionId == decisionId);

        // регрессия (как в задаче 4): запись выписки не должна протекать фиктивной дублирующей строкой в маршруте
        var citizenRoute = await citizen.GetFromJsonAsync<RouteDto>("/api/v1/route/me");
        Assert.Equal(decisionId, Assert.Single(citizenRoute!.Decisions).DecisionId);
        var sendingRoute = await sendingSide.GetFromJsonAsync<RouteDto>($"/api/v1/route/{route.PatientRef}");
        Assert.Equal(decisionId, Assert.Single(sendingRoute!.Decisions).DecisionId);
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

        // moCode = своя же организация пациента (route.Organization.MoCode): и /journal/worklist, и GET /route/{ref}
        // ниже требуют worklist.view own (задача 1.2) — без совпадающего moCode оба вернули бы 403 no_organization.
        var doctor = app.CreateClient("doctor", "doctor-sig", "75", route!.Organization.MoCode);
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

        // без route.own (стюард) сигнал по «своему маршруту» не отправить
        Assert.Equal(HttpStatusCode.Forbidden,
            (await app.CreateClient("steward", "steward1").PostAsJsonAsync("/api/v1/route/me/signals", new RouteSignalRequestDto(RouteSignals.StillWaiting, null, null))).StatusCode);
    }

    [Fact]
    public async Task Route_me_needs_route_own()
    {
        Assert.Equal(HttpStatusCode.Unauthorized, (await app.CreateClient().GetAsync("/api/v1/route/me")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient("regulator", "regulator1").GetAsync("/api/v1/route/me")).StatusCode);
        Assert.Equal(HttpStatusCode.OK, (await app.CreateClient("admin", "admin1").GetAsync("/api/v1/route/me")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await app.CreateClient("citizen", "c-10").GetAsync("/api/v1/route/me?regionKato=10")).StatusCode);
    }

    [Fact]
    public async Task Doctor_route_lookup_returns_404_for_unknown_ref_and_403_for_another_region()
    {
        // GET /route/{ref} требует worklist.view, у врача это own (задача 1.2) — moCode обязателен; "028B" совпадает
        // с рефом, "11XY" у второго врача — чтобы 403 ниже был именно из-за чужой организации/региона, а не отсутствия moCode.
        var doctor = app.CreateClient("doctor", "doctor1", "75", "028B");
        Assert.Equal(HttpStatusCode.OK, (await doctor.GetAsync("/api/v1/route/SYN-75-028B-381-01")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await doctor.GetAsync("/api/v1/route/SYN-75-028B-381-99")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await doctor.GetAsync("/api/v1/route/nonsense")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await app.CreateClient("doctor", "doctor2", "10", "11XY").GetAsync("/api/v1/route/SYN-75-028B-381-01")).StatusCode);
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
        // admin вместо doctor: GET /route/{ref} требует worklist.view (own у врача, задача 1.2), а рандомизированный
        // по актору PatientRef гражданина может оказаться в любой из трёх организаций региона — admin (scope all)
        // получает тот же RouteAudience.Doctor независимо от организации рефа (эндпоинт не смотрит на роль).
        var doctor = await app.CreateClient("admin", "admin-route-check").GetFromJsonAsync<RouteDto>($"/api/v1/route/{citizen.PatientRef}");
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
