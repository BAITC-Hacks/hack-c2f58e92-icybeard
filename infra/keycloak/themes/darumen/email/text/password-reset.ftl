<#ftl output_format="plainText">
<#assign dmName><#if (user.firstName)?has_content && (user.lastName)?has_content>${user.firstName?substring(0, 1)}. ${user.lastName}<#else>${(user.username)!''}</#if></#assign>
darumen · ${msg("dmResetTitle")}

<#if dmName?has_content>${msg("dmHelloName", dmName)}<#else>${msg("dmHello")}</#if> ${msg("dmResetRequested", (user.email)!(user.username)!'')}

${msg("dmResetExpiry", linkExpiration?c)}

${msg("dmResetButton")}: ${link}

--
${msg("dmFooterAccount")} · ${msg("dmFooterAuto")} · help@darumen.kz
