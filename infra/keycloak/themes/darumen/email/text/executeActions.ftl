<#ftl output_format="plainText">
<#assign requiredActionsText><#if requiredActions??><#list requiredActions><#items as reqActionItem>${msg("requiredAction.${reqActionItem}")}<#sep>, </#sep></#items></#list></#if></#assign>
<#assign dmName><#if (user.firstName)?has_content && (user.lastName)?has_content>${user.firstName?substring(0, 1)}. ${user.lastName}<#else>${(user.username)!''}</#if></#assign>
darumen · ${msg("dmActionsTitle")}

<#if dmName?has_content>${msg("dmHelloName", dmName)}<#else>${msg("dmHello")}</#if> ${msg("dmActionsRequested")}
${requiredActionsText}

${msg("dmActionsExpiry", linkExpirationFormatter(linkExpiration))}

${msg("dmActionsButton")}: ${link}

--
${msg("dmFooterAdmin")} · ${msg("dmFooterAuto")} · help@darumen.kz
