using Microsoft.AspNetCore.Http;

namespace Darumen.Shared.Api;

/// <summary>Язык ответа по Accept-Language: ru по умолчанию, kk (или kz) для казахского.</summary>
public static class Locale
{
    public const string Ru = "ru";
    public const string Kk = "kk";

    public static string From(HttpRequest request)
    {
        var header = request.Headers.AcceptLanguage.ToString();
        return header.StartsWith("kk", StringComparison.OrdinalIgnoreCase) || header.StartsWith("kz", StringComparison.OrdinalIgnoreCase)
            ? Kk
            : Ru;
    }
}
