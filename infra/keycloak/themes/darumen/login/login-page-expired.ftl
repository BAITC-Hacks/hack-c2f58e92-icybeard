<#-- «Сессия истекла» (W-Auth-Blocked): вкладку входа открыли повторно или вернулись «назад» по устаревшей странице. -->
<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "icon">
        <span class="dm-icon info"><@layout.icon name="refresh"/></span>
    <#elseif section = "header">
        ${msg("pageExpiredTitle")}
    <#elseif section = "lead">
        ${msg("dmPageExpiredText")}
    <#elseif section = "form">
        <div class="dm-actions">
            <a class="dm-btn" id="loginRestartLink" href="${url.loginRestartFlowUrl}">${msg("dmLoginAgain")}</a>
            <a class="dm-btn secondary" id="loginContinueLink" href="${url.loginAction}">${msg("dmContinueLogin")}</a>
        </div>
    </#if>
</@layout.registrationLayout>
