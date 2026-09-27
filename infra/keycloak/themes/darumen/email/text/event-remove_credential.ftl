<#ftl output_format="plainText">
<#assign ct = (event.getDetail("credential_type"))!''>
<#assign kind = (ct == "otp")?then("OtpRemoved", "CredRemoved")>
darumen · ${msg("dmEv${kind}Title")}

${msg("dmEv${kind}Text", (user.email)!(user.username)!'')}
${msg("dmEvTime")} · ${event.date?datetime?string("dd.MM.yyyy, HH:mm")}
${msg("dmEvIp")} · ${(event.ipAddress)!'—'}

${msg("dmEvNotYou")}

--
${msg("dmFooterSecurity")} · ${msg("dmFooterAuto")} · help@darumen.kz
