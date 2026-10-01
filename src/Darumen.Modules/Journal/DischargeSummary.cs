using System.Text.Json;

namespace Darumen.Modules.Journal;

/// <summary>Выписка/эпикриз обратно направившему врачу (задача 11 плана прозрачности): ещё одна запись в том же
/// journal.decisions (subject = route, тот же subject_id — реф маршрута отправителя), chosen = {"moCode": принимающая
/// организация, "discharges": id решения redirect, "summary": текст эпикриза}. Как и подтверждение приёма — ответ
/// принимающей стороны, а не пациента; возможна только после подтверждения приёма (событие Confirm в RouteEvents),
/// иначе будет выписка без факта госпитализации.</summary>
public static class DischargeSummary
{
    public static string Json(string moCode, Guid redirectDecisionId, string summary) =>
        JsonSerializer.Serialize(new { moCode, discharges = redirectDecisionId.ToString(), summary });

    /// <summary>DecisionId решения redirect, которое выписывает эта запись; null — это не запись выписки.</summary>
    public static Guid? Discharges(JsonElement? json)
    {
        if (json is not { ValueKind: JsonValueKind.Object } element
            || !element.TryGetProperty("discharges", out var value) || value.ValueKind != JsonValueKind.String
            || !Guid.TryParse(value.GetString(), out var id))
        {
            return null;
        }

        return id;
    }

    public static string? Summary(JsonElement? json) =>
        json is { ValueKind: JsonValueKind.Object } element && element.TryGetProperty("summary", out var value)
        && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}
