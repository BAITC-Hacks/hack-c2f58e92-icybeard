<#ftl output_format="plainText">
darumen · ${msg("dmEvLockoutTitle")}

${msg("dmEvLockoutText", (user.email)!(user.username)!'')}
${msg("dmEvTime")} · ${event.date?datetime?string("dd.MM.yyyy, HH:mm")}
${msg("dmEvIp")} · ${(event.ipAddress)!'—'}

${msg("dmEvLockoutNotYou")}

--
${msg("dmFooterSecurity")} · ${msg("dmFooterAuto")} · help@darumen.kz
