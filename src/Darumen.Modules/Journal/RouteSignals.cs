using System.Text.Json;
using Darumen.Shared.Api;

namespace Darumen.Modules.Journal;

/// <summary>Сигналы гражданина по своему маршруту — цифровая валидация листа ожидания («Вы ещё ждёте?», как DrDoctor
/// и NECU в NHS: 3–27 % пациентов снимаются с листа одним вопросом) и просьба рассмотреть организацию быстрее.
/// Хранятся в journal.decisions с subject route, роль citizen, chosen = {"signal": kind, "moCode"?}; решение врача
/// (redirect или keep) после сигнала закрывает его. Ничего медицинского: ни причин, ни диагнозов.</summary>
public static class RouteSignals
{
    public const string StillWaiting = "still_waiting";
    public const string TreatedElsewhere = "treated_elsewhere";
    public const string Withdraw = "withdraw";
    public const string RequestRedirect = "request_redirect";

    /// <summary>Гражданин сам сообщает, что хочет остаться в текущей больнице: система перестаёт предлагать ему перевод.</summary>
    public const string PreferCurrent = "prefer_current";
    public const string CitizenRole = "citizen";

    /// <summary>Через сколько дней без подтверждения гражданину снова задаётся вопрос «Вы ещё ждёте?».</summary>
    public const int ValidationIntervalDays = 30;

    public static readonly IReadOnlySet<string> Kinds = new HashSet<string>(StringComparer.Ordinal) { StillWaiting, TreatedElsewhere, Withdraw, RequestRedirect, PreferCurrent };

    private static readonly IReadOnlySet<string> Confirmations = new HashSet<string>(StringComparer.Ordinal) { StillWaiting, TreatedElsewhere, Withdraw, PreferCurrent };

    public static string Json(string kind, string? toMoCode) =>
        toMoCode is null ? JsonSerializer.Serialize(new { signal = kind }) : JsonSerializer.Serialize(new { signal = kind, moCode = toMoCode });

    /// <summary>Вид сигнала из chosen решения; null — это решение врача, а не сигнал.</summary>
    public static string? Kind(JsonElement? json) =>
        json is { ValueKind: JsonValueKind.Object } element && element.TryGetProperty("signal", out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    /// <summary>Сигналы по одному маршруту, свежие первыми; Open — после сигнала не было решения врача.</summary>
    public static IReadOnlyList<RouteSignalDto> FromDecisions(IReadOnlyList<DecisionDto> decisions, IReadOnlyDictionary<string, string> names)
    {
        var lastAnswer = decisions.Where(d => Kind(d.Chosen) is null).Select(d => (DateTimeOffset?)d.RecordedAt).DefaultIfEmpty(null).Max();
        var rows = new List<RouteSignalDto>();
        foreach (var decision in decisions)
        {
            var kind = Kind(decision.Chosen);
            if (kind is null)
            {
                continue;
            }

            var to = MoCode(decision.Chosen);
            rows.Add(new RouteSignalDto(
                decision.DecisionId, decision.RecordedAt, kind, to, to is null ? null : names.GetValueOrDefault(to, to), decision.Reason,
                lastAnswer is null || decision.RecordedAt > lastAnswer));
        }

        return rows.OrderByDescending(r => r.RecordedAt).ToList();
    }

    /// <summary>Нет подтверждения ожидания за <see cref="ValidationIntervalDays"/> дней — карточка «Вы ещё ждёте?» показывается снова.</summary>
    public static bool ValidationDue(IReadOnlyList<RouteSignalDto> signals, DateTimeOffset now) =>
        !signals.Any(s => Confirmations.Contains(s.Kind) && s.RecordedAt > now.AddDays(-ValidationIntervalDays));

    /// <summary>Открытые сигналы по всем маршрутам региона для рабочего списка: реф → самый свежий сигнал без ответа врача.</summary>
    public static IReadOnlyDictionary<string, PatientSignalDto> Open(IReadOnlyList<DecisionDto> routeDecisions, IReadOnlyDictionary<string, string> names)
    {
        var result = new Dictionary<string, PatientSignalDto>(StringComparer.Ordinal);
        foreach (var group in routeDecisions.GroupBy(d => d.SubjectId))
        {
            var latest = FromDecisions(group.ToList(), names).FirstOrDefault(s => s.Open);
            if (latest is not null)
            {
                result[group.Key] = new PatientSignalDto(latest.Kind, latest.ToMoCode, latest.ToMoName, latest.Comment, latest.RecordedAt);
            }
        }

        return result;
    }

    public static string? MoCode(JsonElement? json) =>
        json is { ValueKind: JsonValueKind.Object } element && element.TryGetProperty("moCode", out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
}
