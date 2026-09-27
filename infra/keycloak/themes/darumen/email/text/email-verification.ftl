<#ftl output_format="plainText">
darumen · ${msg("dmVerifyTitle")}

${msg("dmVerifyText", (user.email)!'')}

${msg("dmVerifyExpiry", linkExpirationFormatter(linkExpiration))}

${msg("dmVerifyButton")}: ${link}

--
${msg("dmFooterVerify")} · ${msg("dmFooterAuto")} · help@darumen.kz
