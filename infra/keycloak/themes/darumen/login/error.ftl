<#-- Ошибки с досок W-Auth-Blocked: «Ссылка устарела» (истёкший или использованный токен из письма),
     «Аккаунт заблокирован» (выключен администратором), «Сессия истекла» (протухшая страница/cookie);
     прочие ошибки Keycloak — универсальная карточка с текстом сервера. -->
<#import "template.ftl" as layout>
<#assign dmText = (message.summary)!''>
<#assign dmKind = "error">
<#if dmText == msg("expiredActionMessage") || dmText == msg("expiredActionTokenNoSessionMessage") || dmText == msg("expiredActionTokenSessionExistsMessage") || dmText == msg("invalidTokenRequiredActions")>
    <#assign dmKind = "link">
<#elseif dmText == msg("accountDisabledMessage") || dmText == msg("accountTemporarilyDisabledMessage")>
    <#assign dmKind = "blocked">
<#elseif dmText == msg("cookieNotFoundMessage") || dmText == msg("loginTimeout") || dmText == msg("expiredCodeMessage") || dmText == msg("sessionNotActiveMessage") || dmText == msg("staleCodeMessage") || dmText == msg("invalidCodeMessage")>
    <#assign dmKind = "session">
</#if>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "icon">
        <#if dmKind == "link"><span class="dm-icon warn"><@layout.icon name="clock"/></span>
        <#elseif dmKind == "blocked"><span class="dm-icon danger"><@layout.icon name="lock"/></span>
        <#elseif dmKind == "session"><span class="dm-icon info"><@layout.icon name="refresh"/></span>
        <#else><span class="dm-icon danger"><@layout.icon name="alert"/></span></#if>
    <#elseif section = "header">
        <#if dmKind == "link">${msg("dmLinkExpiredTitle")}
        <#elseif dmKind == "blocked">${msg("dmBlockedTitle")}
        <#elseif dmKind == "session">${msg("dmExpiredTitle")}
        <#else>${msg("errorTitle")}</#if>
    <#elseif section = "lead">
        <#if dmKind == "link">${msg("dmLinkExpiredText")}
        <#elseif dmKind == "blocked">${msg("dmBlockedText")}
        <#elseif dmKind == "session">${msg("dmExpiredText")}
        <#else><span id="kc-error-message">${kcSanitize(dmText)?no_esc}</span></#if>
    <#elseif section = "form">
        <div class="dm-actions">
            <#if dmKind == "link">
                <a class="dm-btn" href="${url.loginResetCredentialsUrl}">${msg("dmRequestNewLink")}</a>
            <#elseif dmKind == "blocked">
                <a class="dm-btn secondary" href="mailto:help@darumen.kz">${msg("dmWriteAdmin")}</a>
            <#elseif dmKind == "session">
                <a class="dm-btn" href="${layout.site()}">${msg("dmLoginAgain")}</a>
            <#elseif !skipLink?? && (client.baseUrl)?has_content>
                <a class="dm-btn secondary" id="backToApplication" href="${client.baseUrl}">${msg("backToApplication")}</a>
            </#if>
        </div>
    </#if>
</@layout.registrationLayout>
