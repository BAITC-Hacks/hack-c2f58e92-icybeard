using System.Text.Json.Nodes;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Analytics;

/// <summary>Каталог lakehouse с отчётами моделей; в контейнере монтируется read-only.</summary>
public sealed class QualityOptions
{
    public const string Section = "Quality";
    public string LakehouseDir { get; set; } = "lakehouse";
}

/// <summary>Качество моделей: отчёты make train / make eval из lakehouse/models как единый JSON.
/// Ничего не пересчитывает — отдаёт то, что зафиксировано обучением, чтобы страница качества
/// и презентация цитировали один и тот же источник.</summary>
public sealed class QualityService(IOptions<QualityOptions> options)
{
    public IResult Report()
    {
        var root = Path.Combine(options.Value.LakehouseDir, "models");
        if (!Directory.Exists(root))
        {
            return Results.Problem(statusCode: StatusCodes.Status404NotFound, title: "Отчёты моделей недоступны",
                detail: $"каталог {root} не найден: обучение ещё не выполнялось или lakehouse не примонтирован");
        }

        var wait = ReadJson(Path.Combine(root, "wait", "report.json"));
        var waitMeta = ReadJson(Path.Combine(root, "wait", "metadata.json"));
        if (wait is not null && waitMeta is not null)
        {
            wait["trainedThrough"] = waitMeta["trained_through"]?.DeepClone();
            wait["trainRows"] = waitMeta["train_rows"]?.DeepClone();
        }

        var response = new JsonObject
        {
            ["wait"] = wait,
            ["forecasts"] = ReadPerStream(Path.Combine(root, "forecast")),
            ["anomalies"] = ReadPerStream(Path.Combine(root, "anomaly")),
            ["simulate"] = ReadJson(Path.Combine(root, "simulate", "counterfactual_q1.json")),
        };
        return Results.Json(response);
    }

    private static JsonObject ReadPerStream(string directory)
    {
        var result = new JsonObject();
        if (!Directory.Exists(directory))
        {
            return result;
        }

        foreach (var stream in Directory.EnumerateDirectories(directory).OrderBy(d => d, StringComparer.Ordinal))
        {
            if (ReadJson(Path.Combine(stream, "report.json")) is { } report)
            {
                result[Path.GetFileName(stream)] = report;
            }
        }

        return result;
    }

    private static JsonObject? ReadJson(string path)
    {
        if (!File.Exists(path))
        {
            return null;
        }

        try
        {
            return JsonNode.Parse(File.ReadAllText(path)) as JsonObject;
        }
        catch (Exception)
        {
            // повреждённый отчёт не должен ронять страницу качества
            return null;
        }
    }
}
