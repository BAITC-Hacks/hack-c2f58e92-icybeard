namespace Darumen.Modules.Public;

/// <summary>Публичная витрина гостя: откуда берутся погода и новости. Источники внешние, поэтому всё настраиваемо
/// и любой сбой превращается в «раздел недоступен», а не в ошибку главной.</summary>
public sealed class PublicOptions
{
    public const string Section = "Public";

    /// <summary>Прогноз Open-Meteo (без ключа); пустая строка выключает погоду.</summary>
    public string WeatherBaseUrl { get; set; } = "https://api.open-meteo.com/v1/forecast";

    /// <summary>RSS-лента новостей; пустая строка выключает новости.</summary>
    public string NewsFeedUrl { get; set; } = "https://tengrinews.kz/news.rss";

    public string NewsSource { get; set; } = "Tengrinews";

    /// <summary>Регулярное выражение по заголовку и описанию: оставляем только материалы о здравоохранении.</summary>
    public string NewsKeywords { get; set; } = "здоров|медиц|больниц|вакцин|минздрав|врач|поликлиник|госпитал|грипп|орви|эпидем|лекарств|аптек|осмс|скорой помощи|санэпид|пациент|клиник|стационар|инфекц|онколог|диспансер|медсестр|фельдшер|пневмон|корь|менингит|отравлен|денсаулық|аурухана|дәрігер|емхана|науқас|вакцина";

    public int NewsLimit { get; set; } = 5;

    public int CacheMinutes { get; set; } = 30;

    public int TimeoutSeconds { get; set; } = 8;
}
