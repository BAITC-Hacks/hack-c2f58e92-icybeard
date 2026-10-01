using System.Net.Http.Json;
using System.Text.Json;

namespace Darumen.Modules.Journal;

/// <summary>Статусы запроса согласия на запись приёма (AI-скрайб).</summary>
public static class ScribeConsentStatuses
{
    /// <summary>Врач отправил запрос, пациент ещё не ответил.</summary>
    public const string Pending = "pending";

    /// <summary>Пациент согласился: врач может начать одну запись сегодня.</summary>
    public const string Granted = "granted";

    public const string Declined = "declined";

    /// <summary>Пациент отозвал согласие до начала записи.</summary>
    public const string Withdrawn = "withdrawn";

    /// <summary>Врач отменил запрос.</summary>
    public const string Cancelled = "cancelled";

    /// <summary>День закончился, а запись не начата.</summary>
    public const string Expired = "expired";

    /// <summary>Запись начата, памятка ещё не утверждена (врач может продолжить её в тот же день).</summary>
    public const string Recording = "recording";

    /// <summary>Врач отменил начатую и не утверждённую запись: аудио и черновик удалены.</summary>
    public const string Discarded = "discarded";

    /// <summary>Врач утвердил запись, памятка у пациента.</summary>
    public const string Completed = "completed";

    public static readonly IReadOnlySet<string> Answers = new HashSet<string>(StringComparer.Ordinal) { Granted, Declined, Withdrawn, Cancelled };
}

/// <summary>Один запрос согласия и всё, что с ним случилось: ответ пациента, сессия записи, утверждённая памятка.</summary>
public sealed record ScribeConsent(
    Guid RequestId, string PatientRef, string? MoCode, string RequestedBy, string RequestedRole, DateTimeOffset RequestedAt, DateOnly Day,
    string? Comment, string Status, DateTimeOffset? AnsweredAt, string? SessionId, string? LeafletToken, DateTimeOffset? ApprovedAt);

public sealed record ScribeConsentDto(
    Guid RequestId, string PatientRef, string? MoCode, string? MoName, string RequestedRole, DateTimeOffset RequestedAt, string Day, string? Comment,
    string Status, DateTimeOffset? AnsweredAt, string? SessionId, string? LeafletToken, DateTimeOffset? ApprovedAt);

public sealed record ScribeConsentRequestDto(string? PatientRef, string? Comment);

public sealed record ScribeConsentAnswerDto(bool Granted);

public sealed record ScribeSessionRequestDto(Guid? ConsentId, string? Language);

public sealed record ScribeSessionCreatedDto(string SessionId, Guid ConsentId, string PatientRef);

public sealed record ScribeSectionDto(string Name, string Text);

public sealed record ScribeApproveRequestDto(IReadOnlyList<ScribeSectionDto>? Sections, string? PatientLeaflet);

public sealed record ScribeApprovedDto(string LeafletToken, bool AudioDeleted, Guid? ConsentId);

/// <summary>Журнал согласий на запись приёма: subject = scribe, subject_id = реф пациента. Формы chosen:
/// {"scribeConsent":"requested","moCode"} — врач запросил; {"scribeConsent":"granted|declined|withdrawn|cancelled","requestId"} —
/// ответ пациента или отмена врачом; {"scribeSession","requestId"} — запись начата; {"scribeLeaflet","requestId","sessionId"} —
/// запись утверждена. Согласие действует на один приём и только в день запроса (Asia/Almaty).</summary>
public static class ScribeConsents
{
    public const string Requested = "requested";

    public static string RequestJson(string? moCode) => JsonSerializer.Serialize(new { scribeConsent = Requested, moCode });

    public static string AnswerJson(string answer, Guid requestId) => JsonSerializer.Serialize(new { scribeConsent = answer, requestId = requestId.ToString() });

    public static string SessionJson(string sessionId, Guid requestId) => JsonSerializer.Serialize(new { scribeSession = sessionId, requestId = requestId.ToString() });

    public static string LeafletJson(string token, Guid requestId, string sessionId) =>
        JsonSerializer.Serialize(new { scribeLeaflet = token, requestId = requestId.ToString(), sessionId });

    /// <summary>Свёртка журнала одного пациента: запросы, свежие первыми.</summary>
    public static IReadOnlyList<ScribeConsent> From(IEnumerable<DecisionDto> decisions, DateOnly today)
    {
        var requests = new Dictionary<Guid, ScribeConsent>();
        foreach (var d in decisions.OrderBy(d => d.RecordedAt))
        {
            if (d.Chosen is not { ValueKind: JsonValueKind.Object } chosen)
            {
                continue;
            }

            var target = Guid.TryParse(Text(chosen, "requestId"), out var id) ? id : (Guid?)null;
            if (Text(chosen, "scribeConsent") is { } consent)
            {
                if (consent == Requested)
                {
                    requests[d.DecisionId] = new ScribeConsent(d.DecisionId, d.SubjectId, Text(chosen, "moCode"), d.Actor, d.Role, d.RecordedAt,
                        RouteJournal.TodayAt(d.RecordedAt), d.Reason, ScribeConsentStatuses.Pending, null, null, null, null);
                }
                else if (target is { } t && requests.TryGetValue(t, out var r))
                {
                    if (consent == ScribeConsentStatuses.Discarded && r.Status == ScribeConsentStatuses.Recording)
                    {
                        requests[t] = r with { Status = ScribeConsentStatuses.Discarded };
                    }
                    else if (consent != ScribeConsentStatuses.Discarded && r.SessionId is null
                             && r.Status is ScribeConsentStatuses.Pending or ScribeConsentStatuses.Granted)
                    {
                        requests[t] = r with { Status = consent, AnsweredAt = d.RecordedAt };
                    }
                }
            }
            else if (Text(chosen, "scribeSession") is { } session && target is { } st && requests.TryGetValue(st, out var rs)
                     && rs.Status == ScribeConsentStatuses.Granted)
            {
                requests[st] = rs with { Status = ScribeConsentStatuses.Recording, SessionId = session };
            }
            else if (Text(chosen, "scribeLeaflet") is { } token && target is { } lt && requests.TryGetValue(lt, out var rl)
                     && rl.Status == ScribeConsentStatuses.Recording)
            {
                requests[lt] = rl with { Status = ScribeConsentStatuses.Completed, LeafletToken = token, ApprovedAt = d.RecordedAt };
            }
        }

        // не использованное в свой день согласие, запрос без ответа и неутверждённая запись истекают с концом дня
        return requests.Values
            .Select(r => r.Status is ScribeConsentStatuses.Pending or ScribeConsentStatuses.Granted or ScribeConsentStatuses.Recording && today > r.Day
                ? r with { Status = ScribeConsentStatuses.Expired }
                : r)
            .OrderByDescending(r => r.RequestedAt)
            .ToList();
    }

    /// <summary>Действующий запрос (ждёт ответа или согласие дано, а запись не начата) — второй такой же не создаётся.
    /// Начатая, но не утверждённая запись новому запросу не мешает: согласие на неё уже израсходовано.</summary>
    public static ScribeConsent? Active(IEnumerable<ScribeConsent> consents) =>
        consents.FirstOrDefault(c => c.Status is ScribeConsentStatuses.Pending or ScribeConsentStatuses.Granted);

    public static ScribeConsentDto Dto(ScribeConsent c, IReadOnlyDictionary<string, string> names) => new(
        c.RequestId, c.PatientRef, c.MoCode, c.MoCode is null ? null : names.GetValueOrDefault(c.MoCode, c.MoCode), c.RequestedRole, c.RequestedAt,
        c.Day.ToString("yyyy-MM-dd"), c.Comment, c.Status, c.AnsweredAt, c.SessionId, c.LeafletToken, c.ApprovedAt);

    private static string? Text(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}

/// <summary>Сервис скрайба (Python, FastAPI): создать сессию и утвердить запись идут через API, чтобы проверить
/// согласие пациента и привязать памятку к нему; остальное (аудио, стенограмма, черновик) — напрямую через прокси.</summary>
public interface IScribeService
{
    Task<string> CreateSessionAsync(string language, string actor, string patientRef, CancellationToken ct);

    /// <summary>null — сессия не найдена (404); исключение ScribeServiceException — иной отказ сервиса.</summary>
    Task<string?> ApproveAsync(string sessionId, ScribeApproveRequestDto body, CancellationToken ct);

    /// <summary>Удалить аудио, стенограмму и черновик неутверждённой записи; сессии уже нет — тоже успех.</summary>
    Task DiscardAsync(string sessionId, CancellationToken ct);
}

public sealed class ScribeServiceException(int status, string detail) : Exception(detail)
{
    public int Status { get; } = status;
}

public sealed class ScribeHttpService(HttpClient http) : IScribeService
{
    public const string AddressKey = "ReverseProxy:Clusters:scribe:Destinations:local:Address";

    public async Task<string> CreateSessionAsync(string language, string actor, string patientRef, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, "scribe/sessions")
        {
            Content = JsonContent.Create(new { consent = true, language, patientRef }),
        };
        request.Headers.Add("X-Actor", actor);
        using var response = await http.SendAsync(request, ct);
        await EnsureAsync(response, ct);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>(ct);
        return body.GetProperty("sessionId").GetString()!;
    }

    public async Task<string?> ApproveAsync(string sessionId, ScribeApproveRequestDto body, CancellationToken ct)
    {
        using var response = await http.PostAsJsonAsync($"scribe/sessions/{Uri.EscapeDataString(sessionId)}/approve",
            new { sections = body.Sections, patientLeaflet = body.PatientLeaflet }, ct);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }

        await EnsureAsync(response, ct);
        var result = await response.Content.ReadFromJsonAsync<JsonElement>(ct);
        return result.GetProperty("leafletToken").GetString();
    }

    public async Task DiscardAsync(string sessionId, CancellationToken ct)
    {
        using var response = await http.DeleteAsync($"scribe/sessions/{Uri.EscapeDataString(sessionId)}", ct);
        if (response.StatusCode != System.Net.HttpStatusCode.NotFound)
        {
            await EnsureAsync(response, ct);
        }
    }

    private static async Task EnsureAsync(HttpResponseMessage response, CancellationToken ct)
    {
        if (!response.IsSuccessStatusCode)
        {
            throw new ScribeServiceException((int)response.StatusCode, await response.Content.ReadAsStringAsync(ct));
        }
    }
}
