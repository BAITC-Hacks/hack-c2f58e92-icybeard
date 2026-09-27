<#-- Действия, назначенные администратором (execute-actions-email: смена пароля, настройка аутентификатора и т. п.). -->
<#outputformat "plainText">
<#assign requiredActionsText><#if requiredActions??><#list requiredActions><#items as reqActionItem>${msg("requiredAction.${reqActionItem}")}<#sep>, </#sep></#items></#list></#if></#assign>
</#outputformat>
<#import "template.ftl" as layout>
<#assign dmName = layout.greetName()>
<@layout.emailLayout title=msg("dmActionsTitle") footer=msg("dmFooterAdmin")>
<@layout.p><#if dmName?has_content>${msg("dmHelloName", dmName)}<#else>${msg("dmHello")}</#if> ${msg("dmActionsRequested")}</@layout.p>
<@layout.p weight=500>${requiredActionsText}</@layout.p>
<@layout.p muted=true>${msg("dmActionsExpiry", linkExpirationFormatter(linkExpiration))}</@layout.p>
<@layout.button href=link label=msg("dmActionsButton")/>
<@layout.fallback href=link/>
</@layout.emailLayout>
