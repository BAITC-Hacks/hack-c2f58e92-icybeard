<#-- W-Mail «Смена пароля». linkExpiration — минуты (realm actionTokenGeneratedByUserLifespan = 3600 с). -->
<#import "template.ftl" as layout>
<#assign dmName = layout.greetName()>
<@layout.emailLayout title=msg("dmResetTitle") footer=msg("dmFooterAccount")>
<@layout.p><#if dmName?has_content>${msg("dmHelloName", dmName)}<#else>${msg("dmHello")}</#if> ${msg("dmResetRequested", (user.email)!(user.username)!'')}</@layout.p>
<@layout.p muted=true>${msg("dmResetExpiry", linkExpiration?c)}</@layout.p>
<@layout.button href=link label=msg("dmResetButton")/>
<@layout.fallback href=link/>
</@layout.emailLayout>
