namespace Darumen.Modules.Journal;

/// <summary>Реф синтетического пациента рабочего списка и маршрута: SYN-{регион}-{организация}-{профиль}-{NN}.
/// Профиль входит в реф, потому что у одной организации очереди по нескольким профилям, и без него номера
/// пациентов разных очередей совпадали бы. По рефу маршрут (/route/{patientRef}) регенерирует ровно ту же
/// строку рабочего списка: WorklistBuilder детерминирован по организации, профилю и номеру.</summary>
public sealed record RoutePatientRef(string RegionKato, string MoCode, string ProfileCode, int Index)
{
    public const string Prefix = "SYN";

    public string Format() => $"{Prefix}-{RegionKato}-{MoCode}-{ProfileCode}-{Index:00}";

    public static bool TryParse(string? value, out RoutePatientRef? parsed)
    {
        parsed = null;
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        var parts = value.Trim().Split('-');
        if (parts.Length != 5 || parts[0] != Prefix || !int.TryParse(parts[4], out var index) || index < 1)
        {
            return false;
        }

        if (parts[1].Length == 0 || parts[2].Length == 0 || parts[3].Length == 0)
        {
            return false;
        }

        parsed = new RoutePatientRef(parts[1], parts[2], parts[3], index);
        return true;
    }
}
