using System.Text.RegularExpressions;
using System.Xml.Linq;
using Microsoft.Extensions.Options;

namespace Darumen.Modules.Public;

public interface INewsSource
{
    /// <summary>Последние материалы о здравоохранении; null, если лента недоступна или выключена.</summary>
    Task<IReadOnlyList<NewsItemDto>?> LatestAsync(CancellationToken cancellationToken);
}

/// <summary>RSS-лента общего новостного сайта с фильтром по ключевым словам о здравоохранении. Ленты МЗ РК на gov.kz
/// отвечают 500 (проверено 26.09.2026), поэтому источник настраиваемый.</summary>
public sealed partial class RssNewsClient(HttpClient http, IOptions<PublicOptions> options) : INewsSource
{
    public async Task<IReadOnlyList<NewsItemDto>?> LatestAsync(CancellationToken cancellationToken)
    {
        var o = options.Value;
        if (string.IsNullOrWhiteSpace(o.NewsFeedUrl))
        {
            return null;
        }

        using var response = await http.GetAsync(o.NewsFeedUrl, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            return null;
        }

        var xml = await response.Content.ReadAsStringAsync(cancellationToken);
        return Parse(xml, o.NewsKeywords, o.NewsSource, o.NewsLimit);
    }

    /// <summary>Разбор RSS 2.0: заголовок, ссылка, дата; оставляем материалы, где ключевые слова есть в заголовке
    /// (по описанию проходили новости о ранениях и ДТП с упоминанием врачей).</summary>
    public static IReadOnlyList<NewsItemDto> Parse(string xml, string keywords, string source, int limit)
    {
        var filter = new Regex(keywords, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        var items = new List<NewsItemDto>();
        XDocument doc;
        try
        {
            doc = XDocument.Parse(xml);
        }
        catch (System.Xml.XmlException)
        {
            return items;
        }

        foreach (var item in doc.Descendants("item"))
        {
            var title = Spaces().Replace(item.Element("title")?.Value ?? "", " ").Trim();
            var url = item.Element("link")?.Value?.Trim() ?? "";
            if (title.Length == 0 || url.Length == 0 || !filter.IsMatch(title))
            {
                continue;
            }

            DateTimeOffset? published = DateTimeOffset.TryParse(item.Element("pubDate")?.Value, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var dt) ? dt : null;
            items.Add(new(title, url, published, source));
            if (items.Count >= limit)
            {
                break;
            }
        }

        return items;
    }

    [GeneratedRegex(@"\s+")]
    private static partial Regex Spaces();
}
