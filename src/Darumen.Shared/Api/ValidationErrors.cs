using System.Globalization;
using Microsoft.AspNetCore.Http;

namespace Darumen.Shared.Api;

/// <summary>Накопитель ошибок валидации; отдаёт RFC 9457 problem с кодом 422.</summary>
public sealed class ValidationErrors
{
    private readonly Dictionary<string, List<string>> _errors = new();

    public bool Any => _errors.Count > 0;

    public ValidationErrors Require(string field, string? value, string message = "обязательное поле")
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            Add(field, message);
        }

        return this;
    }

    public ValidationErrors Date(string field, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value) && !DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _))
        {
            Add(field, "ожидается дата YYYY-MM-DD");
        }

        return this;
    }

    public ValidationErrors Kato(string field, string? value)
    {
        if (!string.IsNullOrWhiteSpace(value) && (value.Length != 2 || !value.All(char.IsAsciiDigit)))
        {
            Add(field, "ожидается двузначный код КАТО региона");
        }

        return this;
    }

    public ValidationErrors Add(string field, string message)
    {
        if (!_errors.TryGetValue(field, out var list))
        {
            list = [];
            _errors[field] = list;
        }

        list.Add(message);
        return this;
    }

    public IResult Problem() => Results.ValidationProblem(
        _errors.ToDictionary(kv => kv.Key, kv => kv.Value.ToArray()),
        statusCode: StatusCodes.Status422UnprocessableEntity,
        title: "Ошибка валидации");
}
