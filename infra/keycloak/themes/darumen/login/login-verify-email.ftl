<#-- Подтверждение почты (required action VERIFY_EMAIL). В демо-realm verifyEmail выключен — страница для приглашённых
     пользователей, которым администратор назначил подтверждение почты. -->
<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true centered=true; section>
    <#if section = "icon">
        <span class="dm-icon"><@layout.icon name="mail"/></span>
    <#elseif section = "header">
        ${msg("emailVerifyTitle")}
    <#elseif section = "lead">
        ${msg("emailVerifyInstruction1", (user.email)!'')}
    <#elseif section = "form">
        <div class="dm-alert" role="note"><@layout.icon name="info"/><span>${msg("dmSentSpam")}</span></div>
        <div class="dm-actions">
            <a class="dm-btn secondary" href="${url.loginAction}">${msg("dmResendEmail")}</a>
        </div>
    </#if>
</@layout.registrationLayout>
