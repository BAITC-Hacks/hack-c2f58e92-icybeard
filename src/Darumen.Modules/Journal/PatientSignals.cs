using System.Security.Cryptography;
using System.Text;

namespace Darumen.Modules.Journal;

/// <summary>Что сделали пациенты моей больницы (для колокольчика врача): попросили рассмотреть другую больницу,
/// решили остаться, ждут, больше не нуждаются, ответили на перевод или на запрос записи приёма.</summary>
public sealed record PatientEventDto(Guid Id, string PatientRef, string Kind, string? MoCode, string? MoName, string? Comment, DateTimeOffset At);

public static class PatientSignals
{
    public const string ScribeGranted = "scribe_granted";
    public const string ScribeDeclined = "scribe_declined";
    public const string ScribeWithdrawn = "scribe_withdrawn";

    /// <summary>Сколько последних дней и сколько штук показывать: колокольчик — про свежие события, история — в маршруте.</summary>
    public const int Days = 30;
    public const int Limit = 30;

    private static readonly HashSet<string> RouteKinds = new(StringComparer.Ordinal)
    {
        RouteJournalKinds.Request, RouteJournalKinds.PreferCurrent, RouteJournalKinds.StillWaiting, RouteJournalKinds.Withdraw,
        RouteJournalKinds.TreatedElsewhere, RouteJournalKinds.ConsentAccepted, RouteJournalKinds.ConsentDeclined,
    };

    public static List<PatientEventDto> From(
        IReadOnlyDictionary<string, (IReadOnlyList<DecisionDto> Decisions, RouteProgress Progress)> routes,
        IEnumerable<DecisionDto> scribeDecisions, string moCode, DateTimeOffset since, DateOnly today)
    {
        var result = new List<PatientEventDto>();
        var empty = new Dictionary<string, string>();
        foreach (var (reference, route) in routes)
        {
            if (!string.Equals(route.Progress.OriginMoCode, moCode, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            result.AddRange(RouteJournalKinds.Build(route.Decisions, route.Progress.OriginMoCode, empty, citizen: false)
                .Where(e => e.Role == "citizen" && RouteKinds.Contains(e.Kind) && e.At >= since)
                .Select(e => new PatientEventDto(e.Id, reference, e.Kind, e.MoCode, null, e.Reason, e.At)));
        }

        foreach (var patient in scribeDecisions.GroupBy(d => d.SubjectId, StringComparer.Ordinal))
        {
            // по записи приёма врачу важен последний ответ пациента, а не история всех запросов: свежие — первыми, берём один
            foreach (var c in ScribeConsents.From(patient.ToList(), today).Where(c => c.AnsweredAt is not null && c.Status != ScribeConsentStatuses.Cancelled).Take(1))
            {
                // ответ пациента (а не отмена врачом) — у согласия есть время ответа; после начала записи статус уже не «granted»
                var kind = c.Status switch
                {
                    ScribeConsentStatuses.Granted or ScribeConsentStatuses.Recording or ScribeConsentStatuses.Completed
                        or ScribeConsentStatuses.Discarded when c.AnsweredAt is not null => ScribeGranted,
                    ScribeConsentStatuses.Declined => ScribeDeclined,
                    ScribeConsentStatuses.Withdrawn => ScribeWithdrawn,
                    _ => null,
                };
                if (kind is null || c.AnsweredAt is not { } at || at < since
                    || !string.Equals(c.MoCode, moCode, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                result.Add(new PatientEventDto(StableId(c.RequestId, kind), c.PatientRef, kind, null, null, null, at));
            }
        }

        return result.OrderByDescending(s => s.At).Take(Limit).ToList();
    }

    /// <summary>Свой id на каждый ответ по одному запросу: «согласился», а потом «отозвал» — два разных уведомления.</summary>
    private static Guid StableId(Guid requestId, string kind) =>
        new(MD5.HashData(Encoding.UTF8.GetBytes($"{requestId}:{kind}")));
}
