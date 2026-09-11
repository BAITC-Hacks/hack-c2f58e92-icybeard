namespace Darumen.Api;

/// <summary>Читает KEY=VALUE из ближайшего .env (текущая папка и до четырёх уровней вверх) и кладёт в переменные
/// окружения, не перекрывая уже заданные. Нужен для ключей моделей при локальном запуске.</summary>
public static class DotEnv
{
    public const string FileName = ".env";
    private const int MaxLevels = 4;

    public static string? Load(string? start = null)
    {
        var directory = new DirectoryInfo(start ?? Directory.GetCurrentDirectory());
        for (var level = 0; level <= MaxLevels && directory is not null; level++, directory = directory.Parent)
        {
            var file = Path.Combine(directory.FullName, FileName);
            if (!File.Exists(file))
            {
                continue;
            }

            foreach (var line in File.ReadAllLines(file))
            {
                var trimmed = line.Trim();
                var separator = trimmed.IndexOf('=');
                if (trimmed.Length == 0 || trimmed.StartsWith('#') || separator <= 0)
                {
                    continue;
                }

                var key = trimmed[..separator].Trim();
                var value = trimmed[(separator + 1)..].Trim().Trim('"');
                if (value.Length > 0 && string.IsNullOrEmpty(Environment.GetEnvironmentVariable(key)))
                {
                    Environment.SetEnvironmentVariable(key, value);
                }
            }

            return file;
        }

        return null;
    }
}
