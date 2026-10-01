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
        IReadOnlyDictionary<string, string> ProfileNames, string Audience, string Lang, DateTimeOffset? Now = null,
        RouteProgress? Progress = null, RouteSide Side = RouteSide.None, DateOnly? Today = null, IReadOnlyDictionary<string, string>? ExtraNames = null);

    private static readonly (string Code, int Order, string Ru, string Kk)[] DefaultStages =
    [
        (RouteStages.ReferralIssued, 1, "Направление выдано", "Жолдама берілді"),
        (RouteStages.Examination, 2, "Обследование", "Тексеру"),
        (RouteStages.Waitlisted, 3, "Внесено в лист ожидания", "Күту парағына енгізілді"),
        (RouteStages.Transfer, 3, "Перевод", "Ауыстыру"),
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
        var progress = input.Progress ?? RouteProgress.From(input.Decisions, state.MoCode);
        var realToday = input.Today ?? DateOnly.FromDateTime((input.Now ?? DateTimeOffset.UtcNow).UtcDateTime);

        var registeredAt = today.AddDays(-item.DaysWaiting);
        var issuedAt = registeredAt.AddDays(-(1 + (int)(WorklistBuilder.Seed(reference + "|issued") % 10)));
        var expectedAt = DateOnly.ParseExact(item.ExpectedDate!, DateFormat, CultureInfo.InvariantCulture);
        // дата по данным очереди (пациента вызвали) — или назначенная принимающей больницей после перевода
        DateOnly? plannedAt = progress.TransferConfirmed ? progress.Transfer!.PlannedAt
            : item.StageCode == WorklistBuilder.StageCalled ? expectedAt : null;
        var stage = StageOf(progress, plannedAt);

        var checklist = Checklist(input.Standard, reference, issuedAt, registeredAt, today, plannedAt ?? expectedAt);
        var examinedAt = checklist.Count > 0 ? checklist.Max(c => Parse(c.DoneAt)) : registeredAt;
        var timeline = Timeline(input.Standard, stage, issuedAt, examinedAt, registeredAt, plannedAt, progress, kk);

        var fallback = WorklistBuilder.Fallback(state);
        var forecast = input.Prediction is { } prediction
            ? new RouteForecastDto(prediction.P50Days, prediction.P90Days, prediction.PWithin30Days, true, prediction.Model)
            : new RouteForecastDto(fallback.P50Days, fallback.P90Days, null, false, null);

        var names = input.States.GroupBy(s => s.MoCode).ToDictionary(g => g.Key, g => g.First().MoName);
        foreach (var alternative in input.Alternatives?.Items ?? [])
        {
            names.TryAdd(alternative.Mo.MoCode, alternative.Mo.Name);
        }

        foreach (var (code, name) in input.ExtraNames ?? new Dictionary<string, string>())
        {
            names.TryAdd(code, name);
        }

        // сигналы гражданина — реальные события (время сервера), в отличие от дат маршрута, живущих в «сегодня» витрины;
        // «открыт» только сигнал, на который ещё нужен ответ (просьба о переводе или о снятии с очереди) — по проекции
        var signals = RouteSignals.FromDecisions(input.Decisions, names)
            .Select(sig => sig with { Open = sig.DecisionId == progress.OpenSignalId }).ToList();
        var validationDue = progress.Status is RouteStatuses.Waiting or RouteStatuses.Kept
                            && RouteSignals.ValidationDue(signals, input.Now ?? DateTimeOffset.UtcNow);
        var open = signals.FirstOrDefault(sig => sig.Open);
        var adjusted = WorklistBuilder.Apply(item, progress, input.Side, realToday,
            open is null ? null : new PatientSignalDto(open.Kind, open.ToMoCode, open.ToMoName, open.Comment, open.RecordedAt));
        var doctor = input.Audience == RouteAudience.Doctor
            ? new RouteDoctorPanelDto(adjusted.Priority, adjusted.RiskFlags, adjusted.NextAction, adjusted.NextActionCode, adjusted.Explanation,
                input.Prediction?.PRefusal ?? fallback.PRefusal, input.Prediction?.RefusalOrgInTraining ?? false, input.Prediction?.Explanation)
            : null;

        // после подтверждённого перевода пациент — у принимающей больницы; переводить дальше по этому направлению нельзя
        var profileName = input.ProfileNames.GetValueOrDefault(state.ProfileCode, state.ProfileCode);
        var organization = progress.TransferConfirmed
            ? new RouteOrganizationDto(progress.ResponsibleMoCode, names.GetValueOrDefault(progress.ResponsibleMoCode, progress.ResponsibleMoCode),
                state.ProfileCode, profileName)
            : new RouteOrganizationDto(state.MoCode, state.MoName, state.ProfileCode, profileName);
        IReadOnlyList<AlternativeDto> alternatives = progress.TransferConfirmed || progress.IsClosed ? [] : input.Alternatives?.Items ?? [];
        var citizen = input.Audience == RouteAudience.Citizen;

        return new RouteDto(
            reference, true, input.Audience, Format(today), state.RegionKato, organization,
            stage, timeline.FirstOrDefault(t => t.Code == stage)?.Title ?? stage, timeline,
            new RouteDatesDto(Format(issuedAt), Format(registeredAt), plannedAt is null ? null : Format(plannedAt.Value), Format(expectedAt)),
            item.DaysWaiting, forecast, input.Standard.Benchmarks, checklist,
            alternatives, input.Alternatives?.Model,
            Decisions(input.Decisions, progress.OriginMoCode, names), History(input.States, reference, today, input.ProfileNames, state.ProfileCode), doctor,
            Basis(kk, today),
            new RouteStandardRefDto(input.Standard.Meta.Source, input.Standard.Meta.SourceUrl, input.Standard.Meta.SourceDate, input.Standard.Available),
            signals, validationDue,
            ProgressDto(progress, input.Side, realToday, names, citizen),
            RouteJournalKinds.Build(input.Decisions, progress.OriginMoCode, names, citizen));
    }

    /// <summary>Текущий этап: из данных очереди, пока система ничего не меняла; «Перевод» — пока перевод не подтверждён;
    /// дата госпитализации и сама госпитализация — по ответам принимающей больницы.</summary>
    private static string StageOf(RouteProgress progress, DateOnly? plannedAt) => progress.Status switch
    {
        RouteStatuses.TransferPendingConsent or RouteStatuses.TransferPendingConfirmation => RouteStages.Transfer,
        RouteStatuses.Admitted => RouteStages.Hospitalized,
        RouteStatuses.Closed when progress.ClosedReason == RouteCloseReasons.Discharged => RouteStages.Hospitalized,
        _ when progress.TransferConfirmed => RouteStages.DateAssigned,
        _ => plannedAt is not null ? RouteStages.DateAssigned : RouteStages.Waitlisted,
    };

    public static RouteProgressDto ProgressDto(RouteProgress progress, RouteSide side, DateOnly today, IReadOnlyDictionary<string, string> names, bool citizen)
    {
        string Name(string code) => names.GetValueOrDefault(code, code);
        var transfer = progress.Transfer is { } t
            ? new RouteTransferDto(t.DecisionId, t.ToMoCode, Name(t.ToMoCode), !citizen && t.Severe, t.Reason, t.ProposedAt, t.ConsentAt, t.ConfirmedAt,
                t.PlannedAt is { } planned ? Format(planned) : null, t.AdmittedAt)
            : null;
        var attempt = progress.LastAttempt is { } a ? new RouteTransferAttemptDto(a.Outcome, a.ToMoCode, Name(a.ToMoCode), a.At, a.Reason) : null;
        return new RouteProgressDto(progress.Status, progress.OriginMoCode, progress.ResponsibleMoCode, Name(progress.ResponsibleMoCode), transfer, attempt,
            progress.PrefersCurrent, progress.ClosedReason, progress.ClosedAt, progress.Overdue(today),
            progress.Allowed(side, today).OrderBy(x => x, StringComparer.Ordinal).ToList(),
            progress.RejectedMoCodes.Concat(progress.DeclinedMoCodes).Distinct(StringComparer.OrdinalIgnoreCase).ToList(),
            side.ToString().ToLowerInvariant());
    }

    /// <summary>Этапы Стандарта до госпитализации плюс «Перевод», если он идёт или состоялся; отказ на таймлайне активного
    /// маршрута не показывается. Даты только у пройденных и текущей стадии; норма — у всех, интерфейс показывает её для
    /// предстоящих. Первые три этапа приходят из ИС БГ (данные очереди) и только показываются.</summary>
    private static IReadOnlyList<RouteStageDto> Timeline(
        RouteStandardDto standard, string current, DateOnly issuedAt, DateOnly examinedAt, DateOnly registeredAt, DateOnly? plannedAt,
        RouteProgress progress, bool kk)
    {
        var defs = standard.Available
            ? standard.Stages.Where(s => s.Code != RouteStages.Refused && s.Code != RouteStages.Transfer)
                .Select(s => (s.Code, s.Order, s.Title, Norm: (string?)s.Norm)).ToList()
            : DefaultStages.Where(d => d.Code != RouteStages.Transfer)
                .Select(d => (d.Code, d.Order, Title: kk ? d.Kk : d.Ru, Norm: (string?)null)).ToList();
        var transfer = progress.Transfer;
        if (transfer is not null && (progress.TransferActive || progress.TransferConfirmed))
        {
            var waitlisted = defs.FindIndex(d => d.Code == RouteStages.Waitlisted);
            var title = DefaultStages.First(d => d.Code == RouteStages.Transfer);
            defs.Insert(waitlisted + 1, (RouteStages.Transfer, 0, kk ? title.Kk : title.Ru, null));
        }

        defs = defs.Select((d, i) => (d.Code, Order: i + 1, d.Title, d.Norm)).ToList();
        var currentOrder = defs.Where(d => d.Code == current).Select(d => d.Order).DefaultIfEmpty(int.MaxValue).First();
        var finished = progress.IsClosed && progress.ClosedReason == RouteCloseReasons.Discharged;
        return defs.Select(d =>
        {
            var status = finished || d.Order < currentOrder ? RouteTimelineStatus.Done
                : d.Order == currentOrder ? RouteTimelineStatus.Current : RouteTimelineStatus.Upcoming;
            DateOnly? date = d.Code switch
            {
                RouteStages.ReferralIssued => issuedAt,
                RouteStages.Examination => examinedAt,
                RouteStages.Waitlisted => registeredAt,
                RouteStages.Transfer => DateOnly.FromDateTime((transfer!.ConfirmedAt ?? transfer.ProposedAt).UtcDateTime),
                RouteStages.DateAssigned => plannedAt,
                RouteStages.Hospitalized => transfer?.AdmittedAt is { } admitted ? DateOnly.FromDateTime(admitted.UtcDateTime) : null,
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
        IReadOnlyList<QueueStateRow> states, string reference, DateOnly today, IReadOnlyDictionary<string, string> profileNames, string currentProfile)
    {
        // взрослому пациенту без пола в историю не попадают профили «по полу/беременности» и детские — те же правила,
        // что при выборе персоны гражданина (ExcludedProfiles); если текущий профиль сам такой, фильтр не нужен
        bool Restricted(string code) =>
            SexSpecificProfiles.Contains(code) || (profileNames.TryGetValue(code, out var name) && PediatricProfile.IsMatch(name));
        if (!Restricted(currentProfile))
        {
            var allowed = states.Where(s => !Restricted(s.ProfileCode)).ToList();
            if (allowed.Count > 0)
            {
                states = allowed;
            }
        }

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

    /// <summary>Решения врача (оставить / перевести) из журнала; все остальные события маршрута — в хронике
    /// (<see cref="RouteJournalKinds"/>) и в состоянии (<see cref="RouteProgress"/>). Разбор формы chosen — только в
    /// <see cref="RouteEvents.Parse"/>, чтобы новые события с полем moCode не превращались в фиктивные решения.</summary>
    private static IReadOnlyList<RouteDecisionDto> Decisions(IReadOnlyList<DecisionDto> decisions, string originMoCode, IReadOnlyDictionary<string, string> names)
    {
        var rows = new List<RouteDecisionDto>();
        foreach (var decision in decisions)
        {
            var e = RouteEvents.Parse(decision);
            if (e.Kind != RouteEventKind.DoctorDecision)
            {
                continue;
            }

            var to = e.MoCode!;
            var kind = string.Equals(to, originMoCode, StringComparison.OrdinalIgnoreCase) ? RouteDecisionKinds.Keep : RouteDecisionKinds.Redirect;
            rows.Add(new RouteDecisionDto(
                decision.DecisionId, decision.Role, decision.RecordedAt, MoCode(decision.Recommended), to, names.GetValueOrDefault(to, to), decision.Reason,
                kind, kind == RouteDecisionKinds.Redirect ? RouteConsent.StatusFor(decision.DecisionId, decisions) : null,
                kind == RouteDecisionKinds.Redirect && e.Severe));
        }

        return rows;
    }

    private static string? MoCode(JsonElement? json) =>
        json is { ValueKind: JsonValueKind.Object } element && element.TryGetProperty("moCode", out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static string Basis(bool kk, DateOnly asOf) => kk
        ? $"Синтетикалық маршрут: пациент ойдан шығарылған, ал мерзімдер, кезек және нәтижелер {asOf:dd.MM.yyyy} күнгі аймақ кезектерінің нақты жағдайынан алынған. Бас тарту себептері ашық деректерде жоқ және пациентке тіркелмейді."
        : $"Синтетический маршрут: пациент выдуман, а сроки, очередь и исходы взяты из реального состояния очередей региона на {asOf:dd.MM.yyyy}. Причины отказов в открытых данных отсутствуют и пациенту не приписываются.";

    private static string Format(DateOnly date) => date.ToString(DateFormat, CultureInfo.InvariantCulture);

    private static DateOnly Parse(string date) => DateOnly.ParseExact(date, DateFormat, CultureInfo.InvariantCulture);
}
