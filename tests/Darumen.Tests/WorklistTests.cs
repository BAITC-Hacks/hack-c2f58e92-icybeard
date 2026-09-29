using System.Net.Http.Json;
using Darumen.Modules.Journal;
using Darumen.Tests.Fakes;

namespace Darumen.Tests;

public sealed class WorklistTests(TestApp app) : IClassFixture<TestApp>
{
    /// <summary>Прогнозы для тестовых очередей: те же числа, что раньше читались из state.WaitP50/RefusalRate4w
    /// напрямую, но теперь явно оформлены как прогноз модели (3.6) — предсказанный риск отказа 028B (0.32)
    /// выше порога, поэтому и приоритет, и флаг риска считаются по нему, а не по сырому агрегату витрины.</summary>
    private static readonly Dictionary<(string MoCode, string ProfileCode), QueuePrediction> Predictions = new()
    {
        [("028B", "381")] = new QueuePrediction(55, 66, 0.32, true),
        [("22GN", "381")] = new QueuePrediction(9, 20, 0.02, true),
        [("027O", "021")] = new QueuePrediction(7, 15, 0.05, true),
    };

    [Fact]
    public async Task Builder_is_deterministic_and_flags_real_risks()
    {
        var states = await new InMemoryWorklist().QueueStatesAsync("75", CancellationToken.None);
        var first = WorklistBuilder.Build(states, Predictions);
        var second = WorklistBuilder.Build(states, Predictions);
        Assert.Equal(first.Select(i => i.PatientRef), second.Select(i => i.PatientRef));
        Assert.All(first, i => Assert.True(i.Synthetic));
        var eye = first.Where(i => i.MoCode == "028B").ToList();
        Assert.True(eye.Count > 0 && eye.Count <= WorklistBuilder.MaxPerQueue);
        Assert.All(eye, i => Assert.Contains(WorklistBuilder.RefusalRisk, i.RiskFlags));
        Assert.All(eye, i => Assert.Contains(WorklistBuilder.FasterAlternative, i.RiskFlags));
        Assert.Contains(first, i => i.RiskFlags.Contains(WorklistBuilder.StuckOver30));
        Assert.True(first[0].Priority >= first[^1].Priority);
        Assert.Empty(WorklistBuilder.Build([], Predictions));
        Assert.All(WorklistBuilder.Build(states, Predictions, WorklistBuilder.RefusalRisk), i => Assert.Contains(WorklistBuilder.RefusalRisk, i.RiskFlags));
    }

    /// <summary>3.6: приоритет и флаг риска отказа считаются по прогнозу модели, а не по числу флагов —
    /// одна и та же очередь с более высоким предсказанным риском отказа получает более высокий приоритет
    /// и флаг risk_refusal, с более низким — нет, без обращения к настоящему gRPC-сервису.</summary>
    [Fact]
    public void Priority_and_refusal_flag_follow_the_models_refusal_prediction_not_the_flag_count()
    {
        var state = new QueueStateRow(InMemoryWorklist.AsOf, "M1", "Тест", "021", "75", 10, 5, 10, 2.0, 0.0, 5, 10);
        var lowRisk = new Dictionary<(string, string), QueuePrediction> { [("M1", "021")] = new QueuePrediction(5, 10, 0.05, true) };
        var highRisk = new Dictionary<(string, string), QueuePrediction> { [("M1", "021")] = new QueuePrediction(5, 10, 0.9, true) };
        var low = WorklistBuilder.Build([state], lowRisk)[0];
        var high = WorklistBuilder.Build([state], highRisk)[0];
        Assert.True(high.Priority > low.Priority);
        Assert.Contains(WorklistBuilder.RefusalRisk, high.RiskFlags);
        Assert.DoesNotContain(WorklistBuilder.RefusalRisk, low.RiskFlags);
    }

    /// <summary>Сервис моделей недоступен для какой-то очереди (её нет в словаре прогнозов) — рабочий список
    /// не падает, а считает эту очередь по агрегатам витрины (QueuePrediction.FromModel = false).</summary>
    [Fact]
    public async Task Missing_prediction_falls_back_to_aggregates_instead_of_failing()
    {
        var states = await new InMemoryWorklist().QueueStatesAsync("75", CancellationToken.None);
        var items = WorklistBuilder.Build(states, new Dictionary<(string, string), QueuePrediction>());
        Assert.NotEmpty(items);
    }

    /// <summary>Реф включает профиль: у организации с очередями по двум профилям пациенты не должны получать одинаковые
    /// номера, иначе маршрут по рефу (/route/{patientRef}) неоднозначен. Заодно фиксируется формат, разбор рефа и
    /// машинные коды стадий.</summary>
    [Fact]
    public void Worklist_refs_are_unique_across_profiles_of_one_organisation()
    {
        var states = new List<QueueStateRow>
        {
            new(InMemoryWorklist.AsOf, "M1", "Тест", "381", "75", 100, 20, 40, 5.0, 0.1, 20, 40),
            new(InMemoryWorklist.AsOf, "M1", "Тест", "021", "75", 100, 20, 40, 5.0, 0.1, 20, 40),
        };
        var items = WorklistBuilder.Build(states, new Dictionary<(string, string), QueuePrediction>());
        Assert.True(items.Count >= 2);
        Assert.Equal(items.Count, items.Select(i => i.PatientRef).Distinct().Count());
        Assert.All(items, i =>
        {
            Assert.True(RoutePatientRef.TryParse(i.PatientRef, out var parsed));
            Assert.Equal(i.MoCode, parsed!.MoCode);
            Assert.Equal(i.ProfileCode, parsed.ProfileCode);
            Assert.Equal(i.PatientRef, parsed.Format());
            Assert.Contains(i.StageCode, new[] { WorklistBuilder.StageRegistered, WorklistBuilder.StageWaiting, WorklistBuilder.StageCalled });
            Assert.Contains(i.NextActionCode, new[] { WorklistBuilder.ActionRedirectFaster, WorklistBuilder.ActionReviewBeforeCall, WorklistBuilder.ActionClarifyDate, WorklistBuilder.ActionWaitForCall });
            Assert.NotEmpty(i.NextAction);
        });
        Assert.False(RoutePatientRef.TryParse("SYN-75-028B-01", out _));
        Assert.False(RoutePatientRef.TryParse("SYN-75-028B-381-00", out _));
    }

    [Fact]
    public async Task Worklist_endpoint_uses_the_doctor_region()
    {
        // после задачи 1.2 (worklist.view врача — own) врачу нужна своя организация: без неё — 403 no_organization,
        // а не пустой список, поэтому оба врача ниже — с moCode (в своей организации, разных регионов).
        var body = await app.CreateClient("doctor", "doctor1", "75", "028B").GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.True(body!.Synthetic);
        Assert.Equal("75", body.RegionKato);
        Assert.Equal("2025-03-31", body.AsOf);
        Assert.NotEmpty(body.Items);
        var empty = await app.CreateClient("doctor", "doctor2", "10", "11XY").GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.Empty(empty!.Items);
    }

    /// <summary>Задача 10 плана прозрачности: врач, привязанный к отделению/профилю (клейм profile_code), видит
    /// в рабочем списке только свою очередь — организация та же (028B, профиль 381 в фикстуре), но профиль в клейме
    /// не совпадает с реальным, поэтому список пуст; без клейма (см. Worklist_endpoint_uses_the_doctor_region выше)
    /// врач по-прежнему видит все профили своей организации — привязка не меняет поведение для тех, у кого её нет.</summary>
    [Fact]
    public async Task Doctor_bound_to_a_profile_only_sees_their_own_queue()
    {
        var wrongProfile = app.CreateClient("doctor", "doctor-profile-1", "75", "028B", profileCode: "999");
        var wrongProfileBody = await wrongProfile.GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.Empty(wrongProfileBody!.Items);

        var rightProfile = app.CreateClient("doctor", "doctor-profile-2", "75", "028B", profileCode: "381");
        var rightProfileBody = await rightProfile.GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        Assert.NotEmpty(rightProfileBody!.Items);
        Assert.All(rightProfileBody.Items, i => Assert.Equal("381", i.ProfileCode));
    }

    /// <summary>Регрессия: врач/org_admin с клеймом region_kato не может через query-параметр regionKato
    /// подставить чужой регион — раньше параметр запроса побеждал claim пользователя.</summary>
    [Fact]
    public async Task Worklist_endpoint_rejects_a_foreign_region_from_the_query_string()
    {
        // moCode обязателен для врача (задача 1.2, own-скоуп) — иначе 403 пришёл бы из-за отсутствия организации,
        // а не из-за подмены региона, которую здесь и проверяем.
        var response = await app.CreateClient("doctor", "doctor1", "75", "028B").GetAsync("/api/v1/journal/worklist?regionKato=10");
        Assert.Equal(System.Net.HttpStatusCode.Forbidden, response.StatusCode);
    }

    /// <summary>Прогнозы по очередям региона запрашиваются пакетом и кэшируются на срез витрины (QueuePredictions):
    /// повторный запрос списка не обращается к модели вовсе, а состав и порядок строк совпадают с первым.</summary>
    [Fact]
    public async Task Worklist_predictions_are_batched_and_cached_between_requests()
    {
        var doctor = app.CreateClient("doctor", "doctor1", "75", "028B");
        var first = await doctor.GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
        var previous = app.Queue.OnPredictWait;
        var calls = 0;
        app.Queue.OnPredictWait = request =>
        {
            calls++;
            return previous(request);
        };
        try
        {
            var second = await doctor.GetFromJsonAsync<WorklistResponseDto>("/api/v1/journal/worklist");
            Assert.Equal(0, calls);
            Assert.True(second!.ModelBacked);
            Assert.Equal(first!.Items.Select(i => i.PatientRef), second.Items.Select(i => i.PatientRef));
        }
        finally
        {
            app.Queue.OnPredictWait = previous;
        }
    }
}
