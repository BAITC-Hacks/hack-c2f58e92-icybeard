using System.Text.Json;
using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

/// <summary>Согласие гражданина на решение врача о переносе (redirect) в другую организацию: раньше решение
/// вступало в силу сразу, без ответа пациента. Хранится в journal.decisions той же записью, что и сигналы
/// (subject route, роль citizen), chosen = {"consent": "accepted"|"declined", "decisionId": "&lt;id решения врача&gt;"}.
/// Пока согласия нет — статус pending, виден и пациенту, и врачу на одном и том же RouteDecisionDto.PatientConsent.</summary>
public static class RouteConsent
{
    public const string Pending = "pending";
    public const string Accepted = "accepted";
    public const string Declined = "declined";

    public static string Json(bool accepted, Guid decisionId) =>
        JsonSerializer.Serialize(new { consent = accepted ? Accepted : Declined, decisionId = decisionId.ToString() });

    /// <summary>Ответ гражданина из chosen решения, если это ответ на согласие (а не решение врача и не сигнал); иначе null.</summary>
    public static (string DecisionId, string Answer)? Response(JsonElement? json)
    {
        if (json is not { ValueKind: JsonValueKind.Object } element
            || !element.TryGetProperty("consent", out var answer) || answer.ValueKind != JsonValueKind.String
            || !element.TryGetProperty("decisionId", out var id) || id.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        return (id.GetString()!, answer.GetString()!);
    }

    /// <summary>Статус согласия по конкретному решению-redirect: самый свежий ответ на него, иначе pending.</summary>
    public static string StatusFor(Guid redirectDecisionId, IReadOnlyList<DecisionDto> decisions)
    {
        var id = redirectDecisionId.ToString();
        var answer = decisions
            .Select(d => (Response: Response(d.Chosen), d.RecordedAt))
            .Where(x => x.Response is { } response && response.DecisionId == id)
            .OrderByDescending(x => x.RecordedAt)
            .Select(x => x.Response!.Value.Answer)
            .FirstOrDefault();

        return answer ?? Pending;
    }
}
