using System.Security.Cryptography;
using System.Text;

namespace Darumen.Modules.Access.Services;

/// <summary>Случайные токены (приглашение, статус заявки) и коды почты; в базе только SHA-256.</summary>
public static class Tokens
{
    private const int TokenBytes = 32;
    private const int CodeRange = 1_000_000;

    public static string New() => Base64Url(RandomNumberGenerator.GetBytes(TokenBytes));

    /// <summary>Шестизначный код подтверждения почты.</summary>
    public static string NewCode() => RandomNumberGenerator.GetInt32(0, CodeRange).ToString("D6");

    public static string Hash(string value) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)));

    /// <summary>Сравнение хешей за постоянное время.</summary>
    public static bool Matches(string value, string? expectedHash) =>
        expectedHash is not null && CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(Hash(value)), Encoding.ASCII.GetBytes(expectedHash));

    private static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
