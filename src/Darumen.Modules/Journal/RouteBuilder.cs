using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Darumen.Modules.Queue;
using Darumen.Modules.RefData;
using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

/// <summary>Собирает маршрут пациента из строки рабочего списка и состояния очередей: чистые функции без I/O,
/// детерминированные по рефу (FNV-сид <see cref="WorklistBuilder.Seed"/>). «Сегодня» маршрута — дата среза витрины
/// (AsOf), а не календарь сервера, иначе даты чек-листа и ожидаемая дата рабочего списка разъедутся. Стадии и статусы
/// считаются только по датам, исходы истории — по доле отказов и квантилям ожидания очереди; ничего медицинского.</summary>
public static class RouteBuilder
{
    public const int HistoryMin = 2;
    private const string DateFormat = "yyyy-MM-dd";

    public sealed record Inputs(
        WorklistItemDto Item, QueueStateRow State, IReadOnlyList<QueueStateRow> States, RouteStandardDto Standard,
        PredictResponseDto? Prediction, AlternativesResponseDto? Alternatives, IReadOnlyList<DecisionDto> Decisions,
        IReadOnlyDictionary<string, string> ProfileNames, string Audience, string Lang, DateTimeOffset? Now = null);

    private static readonly (string Code, int Order, string Ru, string Kk)[] DefaultStages =
    [
        (RouteStages.ReferralIssued, 1, "Направление выдано", "Жолдама берілді"),
        (RouteStages.Examination, 2, "Обследование", "Тексеру"),
        (RouteStages.Waitlisted, 3, "Внесено в лист ожидания", "Күту парағына енгізілді"),
        (RouteStages.DateAssigned, 4, "Дата госпитализации назначена", "Емдеуге жатқызу күні белгіленді"),
        (RouteStages.Hospitalized, 5, "Госпитализация", "Емдеуге жатқызу"),
    ];

    /// <summary>Гражданин — один из синтетических пациентов региона. Берём самую большую очередь региона (самый
    /// представительный маршрут: для Алматы это институт глазных болезней с 1 784 направлениями), в ней — «застрявших»
    /// и тех, у кого есть организация быстрее (оба флага считаются из агрегатов, без модели), и выбираем по сиду от
    /// учётной записи. Так у citizen1 сразу есть что показать на маршруте, а врач находит того же пациента в списке.</summary>
    /// <summary>Сколько первых подходящих «застрявших» строк списка врача годятся в персоны гражданина: исключённые
    /// профили занимают верх списка, поэтому окно узкое — персона остаётся на первом экране врача.</summary>
    public const int CitizenCandidates = 5;

    /// <summary>Профили коек, привязанные к полу и беременности (для беременных и рожениц, патология беременности,
    /// гинекологические): у синтетического гражданина нет пола, такой маршрут ему не назначается.</summary>
    public static readonly IReadOnlySet<string> SexSpecificProfiles = new HashSet<string>(StringComparer.Ordinal) { "231", "241", "251" };

    private static readonly Regex PediatricProfile = new("детей|педиатр|новорожд", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    /// <summary>Профили, которые синтетическому взрослому гражданину без пола не назначаются: привязанные к полу и
    /// беременности (<see cref="SexSpecificProfiles"/>) и детские — по названию в справочнике («… для детей»,
    /// «Педиатрические», «Патология новорожденных»); у кодов детских профилей единого правила нет.</summary>
    public static IReadOnlySet<string> ExcludedProfiles(IEnumerable<ProfileDto> profiles)
    {
        var excluded = new HashSet<string>(SexSpecificProfiles, StringComparer.Ordinal);
        excluded.UnionWith(profiles.Where(p => PediatricProfile.IsMatch(p.Name)).Select(p => p.ProfileCode));
        return excluded;
    }

    /// <summary>Персона гражданина — один из первых <see cref="CitizenCandidates"/> «застрявших» пациентов списка врача
    /// (список отсортирован по приоритету): врач видит его на первом экране, и сквозной сценарий врач → гражданин
    /// не требует искать пациента в глубине списка. Регион без проблемных очередей — любой из первых строк.</summary>
    public static string PickPatientRef(IReadOnlyList<WorklistItemDto> population, string actor, IReadOnlySet<string>? excludedProfiles = null)
    {
        static bool Flagged(WorklistItemDto i) => i.RiskFlags.Contains(WorklistBuilder.StuckOver30) || i.RiskFlags.Contains(WorklistBuilder.FasterAlternative);
        var excluded = excludedProfiles ?? SexSpecificProfiles;
        var eligible = population.Where(i => !excluded.Contains(i.ProfileCode)).ToList();
        var candidates = eligible.Where(Flagged).Take(CitizenCandidates).ToList();
        if (candidates.Count == 0)
        {
            candidates = (eligible.Count > 0 ? eligible : population).Take(CitizenCandidates).ToList();
        }

        return candidates[(int)(WorklistBuilder.Seed("citizen|" + actor) % (uint)candidates.Count)].PatientRef;
    }

    public static RouteDto Build(Inputs input)
    {
        var item = input.Item;
        var state = input.State;
        var today = state.AsOf;
        var reference = item.PatientRef;
        var kk = input.Lang == Locale.Kk;

        var registeredAt = today.AddDays(-item.DaysWaiting);
        var issuedAt = registeredAt.AddDays(-(1 + (int)(WorklistBuilder.Seed(reference + "|issued") % 10)));
        var expectedAt = DateOnly.ParseExact(item.ExpectedDate!, DateFormat, CultureInfo.InvariantCulture);
        DateOnly? plannedAt = item.StageCode == WorklistBuilder.StageCalled ? expectedAt : null;
        var stage = plannedAt is not null ? RouteStages.DateAssigned : RouteStages.Waitlisted;

        var checklist = Checklist(input.Standard, reference, issuedAt, registeredAt, today, plannedAt ?? expectedAt);
        var examinedAt = checklist.Count > 0 ? checklist.Max(c => Parse(c.DoneAt)) : registeredAt;
        var timeline = Timeline(input.Standard, stage, issuedAt, examinedAt, registeredAt, plannedAt, kk);

        var fallback = WorklistBuilder.Fallback(state);
        var forecast = input.Prediction is { } prediction
            ? new RouteForecastDto(prediction.P50Days, prediction.P90Days, prediction.PWithin30Days, true, prediction.Model)
            : new RouteForecastDto(fallback.P50Days, fallback.P90Days, null, false, null);

        var names = input.States.GroupBy(s => s.MoCode).ToDictionary(g => g.Key, g => g.First().MoName);
        foreach (var alternative in input.Alternatives?.Items ?? [])
        {
            names.TryAdd(alternative.Mo.MoCode, alternative.Mo.Name);
        }

        // сигналы гражданина — реальные события (время сервера), в отличие от дат маршрута, живущих в «сегодня» витрины
        var signals = RouteSignals.FromDecisions(input.Decisions, names);
        var validationDue = RouteSignals.ValidationDue(signals, input.Now ?? DateTimeOffset.UtcNow);
        IReadOnlyList<string> riskFlags = signals.Any(s => s.Open) && !item.RiskFlags.Contains(WorklistBuilder.PatientSignal)
            ? [.. item.RiskFlags, WorklistBuilder.PatientSignal]
            : item.RiskFlags;
        var doctor = input.Audience == RouteAudience.Doctor
            ? new RouteDoctorPanelDto(item.Priority, riskFlags, item.NextAction, item.NextActionCode, item.Explanation,
                input.Prediction?.PRefusal ?? fallback.PRefusal, input.Prediction?.RefusalOrgInTraining ?? false, input.Prediction?.Explanation)
            : null;

        return new RouteDto(
            reference, true, input.Audience, Format(today), state.RegionKato,
            new RouteOrganizationDto(state.MoCode, state.MoName, state.ProfileCode, input.ProfileNames.GetValueOrDefault(state.ProfileCode, state.ProfileCode)),
            stage, timeline.FirstOrDefault(t => t.Code == stage)?.Title ?? stage, timeline,
            new RouteDatesDto(Format(issuedAt), Format(registeredAt), plannedAt is null ? null : Format(plannedAt.Value), Format(expectedAt)),
            item.DaysWaiting, forecast, input.Standard.Benchmarks, checklist,
            input.Alternatives?.Items ?? [], input.Alternatives?.Model,
            Decisions(input.Decisions, state.MoCode, names), History(input.States, reference, today, input.ProfileNames), doctor,
            Basis(kk, today),
            new RouteStandardRefDto(input.Standard.Meta.Source, input.Standard.Meta.SourceUrl, input.Standard.Meta.SourceDate, input.Standard.Available),
            signals, validationDue);
    }

    /// <summary>Стадии Стандарта до госпитализации; отказ на таймлайне активного маршрута не показывается.
    /// Даты только у пройденных и текущей стадии; норма — у всех, интерфейс показывает её для предстоящих.</summary>
    private static IReadOnlyList<RouteStageDto> Timeline(
        RouteStandardDto standard, string current, DateOnly issuedAt, DateOnly examinedAt, DateOnly registeredAt, DateOnly? plannedAt, bool kk)
    {
        var defs = standard.Available
            ? standard.Stages.Where(s => s.Code != RouteStages.Refused).Select(s => (s.Code, s.Order, Title: s.Title, Norm: (string?)s.Norm)).ToList()
            : DefaultStages.Select(d => (d.Code, d.Order, Title: kk ? d.Kk : d.Ru, Norm: (string?)null)).ToList();
        var currentOrder = defs.Where(d => d.Code == current).Select(d => d.Order).DefaultIfEmpty(int.MaxValue).First();
        return defs.Select(d =>
        {
            var status = d.Order < currentOrder ? RouteTimelineStatus.Done : d.Order == currentOrder ? RouteTimelineStatus.Current : RouteTimelineStatus.Upcoming;
            DateOnly? date = d.Code switch
            {
                RouteStages.ReferralIssued => issuedAt,
                RouteStages.Examination => examinedAt,
                RouteStages.Waitlisted => registeredAt,
                RouteStages.DateAssigned => plannedAt,
                _ => null,
            };
            return new RouteStageDto(d.Code, d.Order, d.Title, status == RouteTimelineStatus.Upcoming || date is null ? null : Format(date.Value), status, d.Norm);
        }).ToList();
    }

    /// <summary>Каждое обследование сдано между выдачей направления и регистрацией; статус — только по датам: истёк к
    /// «сегодня», истечёт к назначенной/ожидаемой дате, действителен. При медиане ожидания 47 дней 14-дневные
    /// анализы истекают в очереди — это логистический вывод, не медицинский.</summary>
    private static IReadOnlyList<RouteChecklistItemDto> Checklist(
        RouteStandardDto standard, string reference, DateOnly issuedAt, DateOnly registeredAt, DateOnly today, DateOnly horizon)
    {
        var span = Math.Max(0, registeredAt.DayNumber - issuedAt.DayNumber);
        var items = new List<RouteChecklistItemDto>();
        foreach (var def in standard.Checklist)
        {
            var doneAt = issuedAt.AddDays((int)(WorklistBuilder.Seed($"{reference}|check|{def.Code}") % (uint)(span + 1)));
            var validUntil = doneAt.AddDays(def.ValidityDays);
            var status = validUntil < today ? RouteChecklistStatus.Expired : validUntil < horizon ? RouteChecklistStatus.Expiring : RouteChecklistStatus.Valid;
            items.Add(new RouteChecklistItemDto(def.Code, def.Title, def.ValidityDays, def.ValidityLabel, Format(doneAt), Format(validUntil), status));
        }

        return items;
    }

    /// <summary>2–3 прошлых направления: организация и профиль из очередей региона по сиду, исход — по доле отказов
    /// очереди, ожидание — между p50 и p90. Причина отказа не приписывается: в открытых данных её нет.</summary>
    private static IReadOnlyList<RouteHistoryDto> History(
        IReadOnlyList<QueueStateRow> states, string reference, DateOnly today, IReadOnlyDictionary<string, string> profileNames)
    {
        if (states.Count == 0)
        {
            return [];
        }

        var count = HistoryMin + (int)(WorklistBuilder.Seed(reference + "|hist") % 2);
        var rows = new List<RouteHistoryDto>();
        for (var k = 0; k < count; k++)
        {
            var pick = states[(int)(WorklistBuilder.Seed($"{reference}|hist|{k}") % (uint)states.Count)];
            var outcomeQuantile = (WorklistBuilder.Seed($"{reference}|hist|{k}|outcome") % 1000) / 1000.0;
            var waitQuantile = (WorklistBuilder.Seed($"{reference}|hist|{k}|wait") % 1000) / 1000.0;
            var outcome = outcomeQuantile < (pick.RefusalRate4w ?? 0) ? RouteOutcomes.Refused : RouteOutcomes.Hospitalized;
            var p50 = pick.WaitP50 ?? pick.QueueAgeP50 ?? 10;
            var p90 = Math.Max(pick.WaitP90 ?? p50 * 2, p50);
            var waitDays = (int)Math.Round(p50 + (p90 - p50) * waitQuantile);
            var registered = today.AddDays(-(45 + 120 * k + (int)(WorklistBuilder.Seed($"{reference}|hist|{k}|reg") % 60)));
            rows.Add(new RouteHistoryDto(
                pick.MoCode, pick.MoName, pick.ProfileCode, profileNames.GetValueOrDefault(pick.ProfileCode, pick.ProfileCode),
                Format(registered), outcome, Format(registered.AddDays(waitDays)), waitDays));
        }

        return rows.OrderByDescending(r => r.RegisteredAt, StringComparer.Ordinal).ToList();
    }

    private static IReadOnlyList<RouteDecisionDto> Decisions(IReadOnlyList<DecisionDto> decisions, string currentMoCode, IReadOnlyDictionary<string, string> names)
    {
        var rows = new List<RouteDecisionDto>();
        foreach (var decision in decisions)
        {
            // сигналы гражданина ({"signal": …}) — не решения врача, они идут в RouteDto.Signals; подтверждение
            // приёма принимающей организацией ({"moCode", "confirms": decisionId}, задача 4) и выписка/эпикриз
            // ({"moCode", "discharges": decisionId, "summary": …}, задача 11) — тоже не отдельные решения redirect/keep
            // для этого списка (у обеих есть поле "moCode", иначе бы прошли через фильтр ниже и создали фиктивную
            // дублирующую строку redirect/keep, как уже было найдено и исправлено для задачи 4) — их статус виден
            // отдельно, через ReferralConfirmation.ConfirmedAt/DischargeSummary.RecordFor на решении redirect.
            var to = MoCode(decision.Chosen);
            if (to is null || RouteSignals.Kind(decision.Chosen) is not null || ReferralConfirmation.Confirms(decision.Chosen) is not null
                || DischargeSummary.Discharges(decision.Chosen) is not null)
            {
                continue;
            }

            var kind = to == currentMoCode ? RouteDecisionKinds.Keep : RouteDecisionKinds.Redirect;
            rows.Add(new RouteDecisionDto(
                decision.DecisionId, decision.Role, decision.RecordedAt, MoCode(decision.Recommended), to, names.GetValueOrDefault(to, to), decision.Reason,
                kind, kind == RouteDecisionKinds.Redirect ? RouteConsent.StatusFor(decision.DecisionId, decisions) : null,
                kind == RouteDecisionKinds.Redirect && Severe(decision.Chosen)));
        }

        return rows;
    }

    private static string? MoCode(JsonElement? json) =>
        json is { ValueKind: JsonValueKind.Object } element && element.TryGetProperty("moCode", out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    /// <summary>Клинический флаг тяжести (RouteRedirectRequestDto.Severe), независимый от очередных RiskFlags в WorklistBuilder:
    /// врач ставит его при направлении беременных или сложных операций — принимающая сторона видит это отдельно от риска отказа.</summary>
    private static bool Severe(JsonElement? json) =>
        json is { ValueKind: JsonValueKind.Object } element && element.TryGetProperty("severe", out var value)
        && value.ValueKind == JsonValueKind.True;

    private static string Basis(bool kk, DateOnly asOf) => kk
        ? $"Синтетикалық маршрут: пациент ойдан шығарылған, ал мерзімдер, кезек және нәтижелер {asOf:dd.MM.yyyy} күнгі аймақ кезектерінің нақты жағдайынан алынған. Бас тарту себептері ашық деректерде жоқ және пациентке тіркелмейді."
        : $"Синтетический маршрут: пациент выдуман, а сроки, очередь и исходы взяты из реального состояния очередей региона на {asOf:dd.MM.yyyy}. Причины отказов в открытых данных отсутствуют и пациенту не приписываются.";

    private static string Format(DateOnly date) => date.ToString(DateFormat, CultureInfo.InvariantCulture);

    private static DateOnly Parse(string date) => DateOnly.ParseExact(date, DateFormat, CultureInfo.InvariantCulture);
}
