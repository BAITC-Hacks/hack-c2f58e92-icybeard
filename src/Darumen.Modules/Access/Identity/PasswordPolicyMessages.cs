namespace Darumen.Modules.Access.Identity;

/// <summary>Понятный текст нарушения политики паролей реалма (length(12), upperCase, lowerCase, digits, notUsername,
/// passwordHistory(5)) на русском и казахском по ключу сообщения Keycloak.</summary>
public static class PasswordPolicyMessages
{
    private static readonly Dictionary<string, (string Ru, string Kk)> Messages = new(StringComparer.OrdinalIgnoreCase)
    {
        ["invalidPasswordMinLengthMessage"] = ("Пароль должен быть не короче {0} символов", "Құпиясөз кемінде {0} таңбадан тұруы керек"),
        ["invalidPasswordMaxLengthMessage"] = ("Пароль должен быть не длиннее {0} символов", "Құпиясөз {0} таңбадан аспауы керек"),
        ["invalidPasswordMinUpperCaseCharsMessage"] = ("Нужна хотя бы {0} заглавная буква", "Кемінде {0} бас әріп қажет"),
        ["invalidPasswordMinLowerCaseCharsMessage"] = ("Нужна хотя бы {0} строчная буква", "Кемінде {0} кіші әріп қажет"),
        ["invalidPasswordMinDigitsMessage"] = ("Нужна хотя бы {0} цифра", "Кемінде {0} цифр қажет"),
        ["invalidPasswordMinSpecialCharsMessage"] = ("Нужен хотя бы {0} специальный символ", "Кемінде {0} арнайы таңба қажет"),
        ["invalidPasswordNotUsernameMessage"] = ("Пароль не должен совпадать с логином", "Құпиясөз логинмен сәйкес келмеуі керек"),
        ["invalidPasswordNotEmailMessage"] = ("Пароль не должен совпадать с почтой", "Құпиясөз поштамен сәйкес келмеуі керек"),
        ["invalidPasswordHistoryMessage"] = ("Пароль не должен совпадать с последними {0} паролями", "Құпиясөз соңғы {0} құпиясөзбен сәйкес келмеуі керек"),
        ["invalidPasswordBlacklistedMessage"] = ("Этот пароль слишком распространён", "Бұл құпиясөз тым кең таралған"),
        ["invalidPasswordRegexPatternMessage"] = ("Пароль не соответствует требованиям", "Құпиясөз талаптарға сай емес"),
    };

    private const string GenericRu = "Пароль не соответствует политике: не короче 12 символов, заглавная и строчная буквы, цифра, не совпадает с логином";
    private const string GenericKk = "Құпиясөз саясатқа сай емес: кемінде 12 таңба, бас және кіші әріп, цифр, логинмен сәйкес келмейді";

    public static (string Ru, string Kk) For(string code, IReadOnlyList<string> parameters)
    {
        if (!Messages.TryGetValue(code, out var message))
        {
            return (GenericRu, GenericKk);
        }

        var value = parameters.Count > 0 ? parameters[0] : "1";
        return (message.Ru.Replace("{0}", value), message.Kk.Replace("{0}", value));
    }
}
