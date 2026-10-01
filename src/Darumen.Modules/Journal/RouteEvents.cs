using System.Globalization;
using System.Text.Json;

namespace Darumen.Modules.Journal;

/// <summary>Вид события маршрута в journal.decisions (subject = route, subject_id = реф пациента). Журнал — единственный
/// источник правды о маршруте: каждое действие человека — новая запись, ничего не правится и не удаляется.</summary>
public enum RouteEventKind
{
    /// <summary>Сигнал гражданина: {"signal": kind, "moCode"?}.</summary>
    Signal,

    /// <summary>Решение врача больницы, где пациент ждёт: {"moCode", "severe"?}; moCode = своя организация — «оставить», иначе — перевод.</summary>
    DoctorDecision,

    /// <summary>Ответ гражданина на предложенный перевод: {"consent": accepted|declined, "decisionId"}.</summary>
    Consent,

    /// <summary>Принимающая больница подтвердила приём и назначила дату: {"moCode", "confirms", "plannedAt"}.</summary>
    Confirm,

    /// <summary>Принимающая больница отказала в приёме: {"moCode", "rejects"}.</summary>
    Reject,

    /// <summary>Принимающая больница перенесла дату: {"moCode", "reschedules", "plannedAt"}.</summary>
    Reschedule,

    /// <summary>Принимающая больница отметила госпитализацию: {"moCode", "admits"}.</summary>
    Admit,

    /// <summary>Пациент не явился в назначенную дату: {"moCode", "noShow"}.</summary>
    NoShow,

    /// <summary>Выписка с эпикризом: {"moCode", "discharges", "summary"}.</summary>
    Discharge,

    /// <summary>Врач отменил ещё не подтверждённый перевод: {"cancels"}.</summary>
    CancelTransfer,

    /// <summary>Ответственная больница сняла пациента с листа ожидания по его просьбе: {"closes": withdrawn|treated_elsewhere}.</summary>
    Close,

    /// <summary>Запись не про маршрут (например, будущая форма chosen) — проекция её пропускает.</summary>
    Unknown,
}

/// <summary>Разобранное событие маршрута: одно место, где форма chosen превращается в смысл. Раньше эти проверки были
/// разбросаны по эндпоинтам и построителю маршрута («есть поле moCode, нет поля signal, нет поля confirms…»), и каждое
/// новое событие с полем moCode рисковало стать фиктивным «решением врача».</summary>
public sealed record RouteEvent(
    DecisionDto Source, RouteEventKind Kind, string? MoCode = null, Guid? Target = null, string? Value = null, DateOnly? PlannedAt = null,
    bool Severe = false)
{
    public DateTimeOffset At => Source.RecordedAt;
    public string? Reason => Source.Reason;
}

public static class RouteEvents
{
    public const string ClosedWithdrawn = "withdrawn";
    public const string ClosedTreatedElsewhere = "treated_elsewhere";
    private const string DateFormat = "yyyy-MM-dd";

    public static RouteEvent Parse(DecisionDto decision)
    {
        if (decision.Chosen is not { ValueKind: JsonValueKind.Object } chosen)
        {
            return new RouteEvent(decision, RouteEventKind.Unknown);
        }

        var moCode = Text(chosen, "moCode");
        if (Text(chosen, "signal") is { } signal)
        {
            return new RouteEvent(decision, RouteEventKind.Signal, moCode, Value: signal);
        }

        if (Text(chosen, "consent") is { } consent && Id(chosen, "decisionId") is { } consentTarget)
        {
            return new RouteEvent(decision, RouteEventKind.Consent, Target: consentTarget, Value: consent);
        }

        if (Id(chosen, "confirms") is { } confirms)
        {
            return new RouteEvent(decision, RouteEventKind.Confirm, moCode, confirms, PlannedAt: Date(chosen, "plannedAt"));
        }

        if (Id(chosen, "rejects") is { } rejects)
        {
            return new RouteEvent(decision, RouteEventKind.Reject, moCode, rejects);
        }

        if (Id(chosen, "reschedules") is { } reschedules)
        {
            return new RouteEvent(decision, RouteEventKind.Reschedule, moCode, reschedules, PlannedAt: Date(chosen, "plannedAt"));
        }

        if (Id(chosen, "admits") is { } admits)
        {
            return new RouteEvent(decision, RouteEventKind.Admit, moCode, admits);
        }

        if (Id(chosen, "noShow") is { } noShow)
        {
            return new RouteEvent(decision, RouteEventKind.NoShow, moCode, noShow);
        }

        if (Id(chosen, "discharges") is { } discharges)
        {
            return new RouteEvent(decision, RouteEventKind.Discharge, moCode, discharges, Text(chosen, "summary"));
        }

        if (Id(chosen, "cancels") is { } cancels)
        {
            return new RouteEvent(decision, RouteEventKind.CancelTransfer, Target: cancels);
        }

        if (Text(chosen, "closes") is { } closes)
        {
            return new RouteEvent(decision, RouteEventKind.Close, Value: closes);
        }

        if (moCode is not null)
        {
            var severe = chosen.TryGetProperty("severe", out var flag) && flag.ValueKind == JsonValueKind.True;
            return new RouteEvent(decision, RouteEventKind.DoctorDecision, moCode, Severe: severe);
        }

        return new RouteEvent(decision, RouteEventKind.Unknown);
    }

    /// <summary>События одного маршрута по времени: журнал отдаёт свежие первыми, проекции нужен порядок «как было».</summary>
    public static IReadOnlyList<RouteEvent> Ordered(IEnumerable<DecisionDto> decisions) =>
        decisions.OrderBy(d => d.RecordedAt).Select(Parse).Where(e => e.Kind != RouteEventKind.Unknown).ToList();

    public static string ConfirmJson(string moCode, Guid transfer, DateOnly plannedAt) =>
        JsonSerializer.Serialize(new { moCode, confirms = transfer.ToString(), plannedAt = Format(plannedAt) });

    public static string RejectJson(string moCode, Guid transfer) => JsonSerializer.Serialize(new { moCode, rejects = transfer.ToString() });

    public static string RescheduleJson(string moCode, Guid transfer, DateOnly plannedAt) =>
        JsonSerializer.Serialize(new { moCode, reschedules = transfer.ToString(), plannedAt = Format(plannedAt) });

    public static string AdmitJson(string moCode, Guid transfer) => JsonSerializer.Serialize(new { moCode, admits = transfer.ToString() });

    public static string NoShowJson(string moCode, Guid transfer) => JsonSerializer.Serialize(new { moCode, noShow = transfer.ToString() });

    public static string CancelJson(Guid transfer) => JsonSerializer.Serialize(new { cancels = transfer.ToString() });

    public static string CloseJson(string reason) => JsonSerializer.Serialize(new { closes = reason });

    public static string Format(DateOnly date) => date.ToString(DateFormat, CultureInfo.InvariantCulture);

    private static string? Text(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static Guid? Id(JsonElement element, string name) => Guid.TryParse(Text(element, name), out var id) ? id : null;

    private static DateOnly? Date(JsonElement element, string name) =>
        DateOnly.TryParseExact(Text(element, name), DateFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) ? date : null;
}
