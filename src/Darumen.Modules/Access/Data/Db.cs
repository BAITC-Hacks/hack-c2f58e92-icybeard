namespace Darumen.Modules.Access.Data;

/// <summary>timestamptz читается Dapper как DateTime (UTC), наружу — DateTimeOffset.</summary>
internal static class Db
{
    public static DateTimeOffset Utc(DateTime at) => new(DateTime.SpecifyKind(at, DateTimeKind.Utc));

    public static DateTimeOffset? Utc(DateTime? at) => at is { } value ? Utc(value) : null;

    public static DateTime? Raw(DateTimeOffset? at) => at?.UtcDateTime;
}
