using System.Text.Json;

namespace Darumen.Modules.Journal;

/// <summary>Подтверждение приёма принимающей организацией направления-redirect (задача 4 плана прозрачности):
/// ещё одна запись в том же journal.decisions (subject = route, тот же subject_id — реф маршрута отправителя),
/// chosen = {"moCode": принимающая организация, "confirms": id решения redirect}. В отличие от согласия пациента
/// (<see cref="RouteConsent"/>, тоже отдельная запись по тому же decisionId) это ответ ДРУГОЙ стороны — принимающей
/// организации, а не пациента. Подтвердить можно только направление, которое пациент уже принял (RouteConsent.Accepted) —
/// human-in-the-loop с обеих сторон: без согласия пациента принимающая организация не готовит место.</summary>
public static class ReferralConfirmation
{
    public static string Json(string moCode, Guid redirectDecisionId) =>
        JsonSerializer.Serialize(new { moCode, confirms = redirectDecisionId.ToString() });

    /// <summary>DecisionId решения redirect, которое подтверждает эта запись; null — это не запись подтверждения
    /// (например, сам redirect, сигнал гражданина или ответ на согласие).</summary>
    public static Guid? Confirms(JsonElement? json)
    {
        if (json is not { ValueKind: JsonValueKind.Object } element
            || !element.TryGetProperty("confirms", out var value) || value.ValueKind != JsonValueKind.String
            || !Guid.TryParse(value.GetString(), out var id))
        {
            return null;
        }

        return id;
    }

    /// <summary>Подтверждён ли редирект хотя бы одной записью-подтверждением; время последнего подтверждения, если есть.</summary>
    public static DateTimeOffset? ConfirmedAt(Guid redirectDecisionId, IReadOnlyList<DecisionDto> decisions) =>
        decisions.Where(d => Confirms(d.Chosen) == redirectDecisionId).Select(d => (DateTimeOffset?)d.RecordedAt)
            .OrderByDescending(x => x).FirstOrDefault();

    /// <summary>Клинический флаг тяжести из chosen решения redirect (RouteRedirectRequestDto.Severe) — та же форма JSON,
    /// что и приватный RouteBuilder.Severe: продублировано здесь намеренно, чтобы не расширять публичную поверхность
    /// RouteBuilder ради одного поля.</summary>
    public static bool Severe(JsonElement? json) =>
        json is { ValueKind: JsonValueKind.Object } element && element.TryGetProperty("severe", out var value)
        && value.ValueKind == JsonValueKind.True;
}
