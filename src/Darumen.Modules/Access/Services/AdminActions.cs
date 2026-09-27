using System.Text.Json;
using Darumen.Contracts.V1;
using Darumen.Modules.Journal;
using Darumen.Shared.Api;
using Darumen.Shared.Auth;
using Darumen.Shared.Messaging;

namespace Darumen.Modules.Access.Services;

/// <summary>Решения администраторов (ТЗ §10.1): запись в журнал решений с событием decision.recorded и строка аудита с пояснением.</summary>
public sealed class AdminActions(IDecisionRepository decisions, AuditQueue audit)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    public async Task RecordAsync(HttpContext http, string subject, string subjectId, object? recommended, object chosen, string? reason, CancellationToken cancellationToken)
    {
        var user = CurrentUser.From(http);
        var recommendedJson = recommended is null ? null : JsonSerializer.Serialize(recommended, Json);
        var chosenJson = JsonSerializer.Serialize(chosen, Json);
        await decisions.RecordAsync(
            new NewDecision(user.Actor, user.Role, subject, subjectId, recommendedJson, chosenJson, reason, null, user.MoCode),
            dto => new DecisionRecorded
            {
                Meta = Events.Meta(),
                DecisionId = dto.DecisionId.ToString(),
                ActorRole = user.Role,
                Subject = subject,
                Recommended = recommendedJson ?? string.Empty,
                Chosen = chosenJson,
                Reason = reason ?? string.Empty,
            },
            cancellationToken);
        Audit(http, subject, $"{subjectId} {chosenJson}");
    }

    /// <summary>Строка аудита без записи в журнал решений (запрос доступа, приглашение, удаление аккаунта).</summary>
    public void Audit(HttpContext http, string action, string detail) => audit.Record(http, action, detail);
}
