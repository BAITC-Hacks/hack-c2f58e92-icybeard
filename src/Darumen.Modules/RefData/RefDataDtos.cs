namespace Darumen.Modules.RefData;

public sealed record RegionDto(string RegionKato, string Name, string Capital, double? Lat, double? Lon, int? PopulationThousands);

public sealed record OrganizationItemDto(string MoCode, string Name, string RegionKato, string? MoType, string? SizeBucket, double? Lat, double? Lon);

public sealed record ProfileDto(string ProfileCode, string Name, bool IsDayHospital, long Referrals);
