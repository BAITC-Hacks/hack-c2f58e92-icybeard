namespace Darumen.Shared.Api;

/// <summary>ИИН наружу только маской (ТЗ §10.2): видны две первые и две последние цифры, ИИН не логируется.</summary>
public static class IinMask
{
    private const int Visible = 2;
    private const char Dot = '•';

    public static string? Mask(string? iin)
    {
        if (string.IsNullOrWhiteSpace(iin))
        {
            return null;
        }

        var value = iin.Trim();
        return value.Length <= Visible * 2
            ? new string(Dot, value.Length)
            : string.Concat(value.AsSpan(0, Visible), new string(Dot, value.Length - Visible * 2), value.AsSpan(value.Length - Visible));
    }
}
