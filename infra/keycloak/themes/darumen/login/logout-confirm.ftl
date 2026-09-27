<#-- Подтверждение выхода (RP-initiated logout без id_token_hint). -->
<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=true centered=true; section>
    <#if section = "icon">
        <span class="dm-icon info"><@layout.icon name="logout"/></span>
    <#elseif section = "header">
        ${msg("logoutConfirmTitle")}
    <#elseif section = "lead">
        ${msg("logoutConfirmHeader")}
    <#elseif section = "form">
        <form class="dm-form" id="kc-logout-confirm" action="${url.logoutConfirmAction}" onsubmit="confirmLogout.disabled = true; return true;" method="POST">
            <input type="hidden" name="session_code" value="${logoutConfirm.code}">
            <div class="dm-actions">
                <button class="dm-btn" name="confirmLogout" id="kc-logout" type="submit">${msg("doLogout")}</button>
                <#if !logoutConfirm.skipLink && (client.baseUrl)?has_content>
                    <a class="dm-btn secondary" href="${client.baseUrl}">${msg("dmStay")}</a>
                </#if>
            </div>
        </form>
    </#if>
</@layout.registrationLayout>
