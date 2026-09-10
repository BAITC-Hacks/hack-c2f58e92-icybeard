using System.Text.Encodings.Web;
using System.Text.Json;

namespace Darumen.Shared.Api;

/// <summary>Каноническая запись сущности потока: та же строка, что пишет Python json.dumps(dict, ensure_ascii=False).</summary>
public static class EntityJson
{
    private static readonly JsonSerializerOptions Options = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    public static string Canonical(IEnumerable<string> orderedKeys, IReadOnlyDictionary<string, string> values) =>
        "{" + string.Join(", ", orderedKeys.Select(k => $"{JsonSerializer.Serialize(k, Options)}: {JsonSerializer.Serialize(values[k], Options)}")) + "}";

    public static IReadOnlyDictionary<string, string> Parse(string json) =>
        JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new Dictionary<string, string>();

    /// <summary>regionKato → region_kato; ключи уже в snake_case не меняются.</summary>
    public static string ToSnake(string key)
    {
        if (key.Contains('_'))
        {
            return key;
        }

        return string.Concat(key.Select((c, i) => char.IsUpper(c) ? (i > 0 ? "_" : string.Empty) + char.ToLowerInvariant(c) : c.ToString()));
    }
}
