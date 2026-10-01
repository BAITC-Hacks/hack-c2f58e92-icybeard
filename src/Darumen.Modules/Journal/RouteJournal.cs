using System.Collections.Concurrent;
using System.Globalization;
using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

/// <summary>Общие операции над журналом маршрута для эндпоинтов маршрута, входящих направлений, рабочего списка и
/// колокольчика: загрузить события по рефу и свернуть их в <see cref="RouteProgress"/>, «сегодня» по времени Казахстана,
/// единый ответ 409 и последовательное выполнение действий по одному пациенту.</summary>
public static class RouteJournal
{
    /// <summary>Сколько записей журнала читать по одному маршруту: запросы, решения, согласия и ответы больниц —
    /// десятки записей даже на длинном маршруте; с запасом, чтобы проекция никогда не работала по обрезанной истории.</summary>
    public const int HistoryLimit = 500;

    /// <summary>Сколько записей по всем маршрутам читать для рабочего списка и колокольчика (журнал маршрутов стенда —
    /// сотни записей).</summary>
    public const int AllRoutesLimit = 2000;

    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Gates = new(StringComparer.Ordinal);

    public static async Task<(IReadOnlyList<DecisionDto> Decisions, RouteProgress Progress)> LoadAsync(
        IDecisionRepository decisions, RoutePatientRef reference, CancellationToken ct)
    {
        var items = (await decisions.ListAsync(null, DecisionSubjects.Route, reference.Format(), 1, HistoryLimit, ct)).Items;
        return (items, RouteProgress.From(items, reference.MoCode));
    }

    /// <summary>Проекции всех маршрутов из одной выборки журнала: реф → (события, состояние).</summary>
    public static async Task<IReadOnlyDictionary<string, (IReadOnlyList<DecisionDto> Decisions, RouteProgress Progress)>> AllAsync(
        IDecisionRepository decisions, CancellationToken ct)
    {
        var items = (await decisions.ListAsync(null, DecisionSubjects.Route, null, 1, AllRoutesLimit, ct)).Items;
        var result = new Dictionary<string, (IReadOnlyList<DecisionDto>, RouteProgress)>(StringComparer.Ordinal);
        foreach (var group in items.GroupBy(d => d.SubjectId))
        {
            if (RoutePatientRef.TryParse(group.Key, out var parsed))
            {
                var list = group.ToList();
                result[group.Key] = (list, RouteProgress.From(list, parsed!.MoCode));
            }
        }

        return result;
    }

    /// <summary>Действия по одному пациенту выполняются строго по очереди: проверка «можно ли» и запись в журнал не
    /// перемешиваются между двумя одновременными запросами (два врача, две вкладки). Стенд — один экземпляр API; при
    /// нескольких экземплярах эту роль должна взять блокировка в базе (pg_advisory_xact_lock по рефу).</summary>
    public static async Task<IResult> SerializedAsync(string reference, Func<Task<IResult>> action)
    {
        var gate = Gates.GetOrAdd(reference, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync();
        try
        {
            return await action();
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>«Сегодня» для дат госпитализации — по времени Казахстана (Asia/Almaty), а не UTC сервера.</summary>
    public static DateOnly Today(HttpContext http) =>
        TodayAt((http.RequestServices.GetService<TimeProvider>() ?? TimeProvider.System).GetUtcNow());

    public static DateOnly TodayAt(DateTimeOffset now)
    {
        try
        {
            return DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, TimeZoneInfo.FindSystemTimeZoneById("Asia/Almaty")).DateTime);
        }
        catch (TimeZoneNotFoundException)
        {
            return DateOnly.FromDateTime(now.ToOffset(TimeSpan.FromHours(5)).DateTime);
        }
    }

    /// <summary>Дата госпитализации: обязательна, ISO, от сегодня до <see cref="RouteProgress.MaxPlannedDays"/> дней вперёд.</summary>
    public static (DateOnly? Date, IResult? Problem) PlannedDate(string? value, DateOnly today)
    {
        var errors = new ValidationErrors().Require("plannedAt", value);
        if (errors.Any)
        {
            return (null, errors.Problem());
        }

        if (!DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date))
        {
            return (null, errors.Add("plannedAt", "ожидается дата в формате ГГГГ-ММ-ДД").Problem());
        }

        if (date < today || date > today.AddDays(RouteProgress.MaxPlannedDays))
        {
            return (null, errors.Add("plannedAt",
                $"дата госпитализации — с {today:dd.MM.yyyy} по {today.AddDays(RouteProgress.MaxPlannedDays):dd.MM.yyyy}").Problem());
        }

        return (date, null);
    }

    /// <summary>409: действие не подходит к текущему состоянию маршрута (детали — для человека; status — для клиента).</summary>
    public static IResult Conflict(string title, string detail, RouteProgress progress) => Results.Problem(
        statusCode: StatusCodes.Status409Conflict, title: title, detail: detail,
        extensions: new Dictionary<string, object?> { ["status"] = progress.Status });

    /// <summary>Кто может прочитать маршрут пациента: больница из рефа (где он стоял в очереди) и, после подтверждённого
    /// перевода, принимающая больница — она теперь отвечает за пациента.</summary>
    public static IEnumerable<string> ReaderOrganizations(RouteProgress progress)
    {
        yield return progress.OriginMoCode;
        if (progress.TransferConfirmed)
        {
            yield return progress.ResponsibleMoCode;
        }
    }

    /// <summary>Повтор запроса с тем же Idempotency-Key (двойной клик, повтор после обрыва связи): 200 с уже записанным
    /// решением — до проверок состояния, которое эта же запись могла изменить.</summary>
    public static async Task<IResult?> ReplayAsync(HttpContext http, IDecisionRepository decisions, CancellationToken ct) =>
        DecisionRecording.IdempotencyKey(http) is { } key && await decisions.FindByIdempotencyKeyAsync(key, ct) is { } existing
            ? Results.Ok(new DecisionCreatedDto(existing.DecisionId, existing.RecordedAt))
            : null;

    public static string? TrimOrNull(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    /// <summary>Названия организаций по точному коду из справочника (без привязки к региону: mo_code уникален глобально) —
    /// для второй стороны перевода, которой может не быть в очередях текущего региона.</summary>
    public static async Task<Dictionary<string, string>> OrganizationNamesAsync(
        Darumen.Modules.RefData.IRefDataRepository refData, IEnumerable<string> codes, CancellationToken ct)
    {
        var names = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var code in codes.Where(c => !string.IsNullOrWhiteSpace(c)).Distinct(StringComparer.Ordinal))
        {
            var found = await refData.OrganizationsAsync(null, code, null, 1, ct);
            if (found.FirstOrDefault(o => o.MoCode == code) is { } org)
            {
                names[code] = org.Name;
            }
        }

        return names;
    }

    /// <summary>Открытый сигнал гражданина по проекции (для строки рабочего списка): вид, больница из просьбы, комментарий.</summary>
    public static PatientSignalDto? OpenSignal(IReadOnlyList<DecisionDto> decisions, RouteProgress progress, IReadOnlyDictionary<string, string> names)
    {
        if (progress.OpenSignalId is not { } id || decisions.FirstOrDefault(d => d.DecisionId == id) is not { } signal)
        {
            return null;
        }

        var e = RouteEvents.Parse(signal);
        return new PatientSignalDto(e.Value ?? RouteSignals.RequestRedirect, e.MoCode, e.MoCode is null ? null : names.GetValueOrDefault(e.MoCode, e.MoCode),
            signal.Reason, signal.RecordedAt);
    }

    /// <summary>409 «действие не подходит к состоянию» с понятным человеку объяснением, почему нельзя.</summary>
    public static IResult NotAllowed(string action, RouteProgress progress, DateOnly today)
    {
        var (title, detail) = progress.Status switch
        {
            RouteStatuses.Closed => ("Маршрут завершён", "по этому направлению больше нельзя действовать: маршрут закрыт"),
            RouteStatuses.WithdrawalRequested => ("Пациент больше не ждёт", "пациент просит снять его с листа ожидания — сначала нужно подтвердить снятие или дождаться, что он передумает"),
            RouteStatuses.TransferPendingConsent when action == RouteActions.Confirm =>
                ("Пациент ещё не согласился", "нельзя подтвердить приём, пока пациент не принял перевод"),
            RouteStatuses.TransferPendingConsent => ("Ждём ответа пациента", "по маршруту есть перевод, на который пациент ещё не ответил"),
            RouteStatuses.TransferPendingConfirmation => ("Ждём подтверждения больницы", "пациент согласился на перевод, принимающая больница ещё не ответила"),
            RouteStatuses.Transferred when action == RouteActions.Confirm => ("Уже подтверждено", "это направление уже подтверждено, дата назначена"),
            RouteStatuses.Transferred when action is RouteActions.Admit or RouteActions.Discharge or RouteActions.NoShow =>
                ("Дата госпитализации ещё не наступила", $"назначенная дата — {progress.Transfer?.PlannedAt:dd.MM.yyyy}, сегодня {today:dd.MM.yyyy}"),
            RouteStatuses.Transferred => ("Пациент уже переведён", "перевод подтверждён, направление закреплено за принимающей больницей"),
            RouteStatuses.Admitted => ("Пациент уже госпитализирован", "остаётся только выписка"),
            _ when action is RouteActions.Confirm or RouteActions.Reject or RouteActions.Discharge or RouteActions.Admit or RouteActions.NoShow
                or RouteActions.Reschedule or RouteActions.CancelTransfer => ("Перевода нет", "по маршруту нет активного перевода"),
            _ => ("Действие недоступно", "это действие сейчас недоступно для вас по этому маршруту"),
        };
        return Conflict(title, detail, progress);
    }
}

/// <summary>Состояние маршрута для клиентов (<see cref="RouteProgress"/>): что сейчас происходит, кто отвечает, перевод и
/// чем закончилась последняя попытка, что может сделать именно этот пользователь (Allowed) — экраны показывают только эти
/// действия и сами правил не вычисляют.</summary>
public sealed record RouteProgressDto(
    string Status, string OriginMoCode, string ResponsibleMoCode, string ResponsibleMoName, RouteTransferDto? Transfer,
    RouteTransferAttemptDto? LastAttempt, bool PrefersCurrent, string? ClosedReason, DateTimeOffset? ClosedAt, bool Overdue,
    IReadOnlyList<string> Allowed, IReadOnlyList<string> BlockedMoCodes, string Side);

public sealed record RouteTransferDto(
    Guid DecisionId, string ToMoCode, string ToMoName, bool Severe, string? Reason, DateTimeOffset ProposedAt, DateTimeOffset? ConsentAt,
    DateTimeOffset? ConfirmedAt, string? PlannedAt, DateTimeOffset? AdmittedAt);

public sealed record RouteTransferAttemptDto(string Outcome, string ToMoCode, string ToMoName, DateTimeOffset At, string? Reason);

/// <summary>Одна запись хроники маршрута — всё, что сделали люди, по порядку: запросы и ответы гражданина, решения врачей,
/// ответы принимающей больницы. Kind — машинный код (<see cref="RouteJournalKinds"/>), подписи RU/KK — на клиентах.</summary>
public sealed record RouteJournalEntryDto(
    Guid Id, DateTimeOffset At, string Kind, string Role, string? MoCode, string? MoName, string? Reason, string? PlannedAt, bool Severe);

public static class RouteJournalKinds
{
    public const string Request = "request";
    public const string PreferCurrent = "prefer_current";
    public const string StillWaiting = "still_waiting";
    public const string Withdraw = "withdraw";
    public const string TreatedElsewhere = "treated_elsewhere";
    public const string Keep = "keep";
    public const string Redirect = "redirect";
    public const string ConsentAccepted = "consent_accepted";
    public const string ConsentDeclined = "consent_declined";
    public const string Confirm = "confirm";
    public const string Reject = "reject";
    public const string Reschedule = "reschedule";
    public const string Admit = "admit";
    public const string NoShow = "no_show";
    public const string Discharge = "discharge";
    public const string Cancel = "cancel";
    public const string Close = "close";

    /// <summary>Хроника маршрута из журнала; гражданину не показываются флаг тяжести и текст эпикриза (это для врачей).</summary>
    public static IReadOnlyList<RouteJournalEntryDto> Build(
        IReadOnlyList<DecisionDto> decisions, string originMoCode, IReadOnlyDictionary<string, string> names, bool citizen)
    {
        var transfers = new Dictionary<Guid, string>();
        var rows = new List<RouteJournalEntryDto>();
        foreach (var e in RouteEvents.Ordered(decisions))
        {
            string? mo = e.MoCode;
            string? planned = e.PlannedAt is { } date ? RouteEvents.Format(date) : null;
            string? kind = e.Kind switch
            {
                RouteEventKind.Signal => e.Value switch
                {
                    RouteSignals.RequestRedirect => Request,
                    RouteSignals.PreferCurrent => PreferCurrent,
                    RouteSignals.StillWaiting => StillWaiting,
                    RouteSignals.Withdraw => Withdraw,
                    RouteSignals.TreatedElsewhere => TreatedElsewhere,
                    _ => null,
                },
                RouteEventKind.DoctorDecision => string.Equals(mo, originMoCode, StringComparison.OrdinalIgnoreCase) ? Keep : Redirect,
                RouteEventKind.Consent => e.Value == RouteConsent.Accepted ? ConsentAccepted : ConsentDeclined,
                RouteEventKind.Confirm => Confirm,
                RouteEventKind.Reject => Reject,
                RouteEventKind.Reschedule => Reschedule,
                RouteEventKind.Admit => Admit,
                RouteEventKind.NoShow => NoShow,
                RouteEventKind.Discharge => Discharge,
                RouteEventKind.CancelTransfer => Cancel,
                RouteEventKind.Close => Close,
                _ => null,
            };
            if (kind is null)
            {
                continue;
            }

            if (kind == Redirect)
            {
                transfers[e.Source.DecisionId] = mo!;
            }
            else if (mo is null && e.Target is { } target && transfers.TryGetValue(target, out var to))
            {
                mo = to; // согласие и отмена относятся к переводу в эту больницу
            }

            // текст эпикриза — медицинский документ для врачей; гражданин видит только факт выписки
            var reason = kind == Discharge ? (citizen ? null : e.Value) : e.Reason;
            rows.Add(new RouteJournalEntryDto(e.Source.DecisionId, e.At, kind, e.Source.Role, mo, mo is null ? null : names.GetValueOrDefault(mo, mo),
                reason, planned, !citizen && e.Severe));
        }

        rows.Reverse();
        return rows;
    }
}
