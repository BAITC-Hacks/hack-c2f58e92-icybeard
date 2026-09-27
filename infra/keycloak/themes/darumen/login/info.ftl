<#-- Информационные страницы. W-Auth-Done «Пароль изменён» — когда ссылку из письма открыли в другом браузере
     (Keycloak завершает поток на info-странице с accountUpdatedMessage и не логинит; в том же браузере он сразу
     входит в приложение). Какое действие завершилось, Keycloak в шаблон не передаёт, поэтому сервер рисует общее
     «Готово», а darumen.js заменяет тексты на «Пароль изменён», если эта вкладка только что отправила форму нового
     пароля (метка в sessionStorage). Остальное — универсальный вид. -->
<#import "template.ftl" as layout>
<#assign dmText = (message.summary)!''>
<#assign dmKind = "info">
<#if dmText == msg("accountPasswordUpdatedMessage")>
    <#assign dmKind = "password">
<#elseif dmText == msg("accountUpdatedMessage")>
    <#assign dmKind = "updated">
<#elseif dmText == msg("emailVerifiedMessage")>
    <#assign dmKind = "verified">
<#elseif dmText == msg("successLogout")>
    <#assign dmKind = "logout">
<#elseif requiredActions??>
    <#assign dmKind = "actions">
</#if>
<#assign dmOk = (dmKind == "password" || dmKind == "updated" || dmKind == "verified" || dmKind == "logout")>
<@layout.registrationLayout displayMessage=false centered=dmOk; section>
    <#if section = "icon">
        <#if dmKind == "logout"><span class="dm-icon info"><@layout.icon name="logout"/></span>
        <#elseif dmOk><span class="dm-icon ok"><@layout.icon name="check"/></span><#else><span class="dm-icon info"><@layout.icon name="info"/></span></#if>
    <#elseif section = "header">
        <#if dmKind == "password">${msg("dmDoneTitle")}
        <#elseif dmKind == "updated"><span data-dm-if-password="${msg("dmDoneTitle")}">${msg("dmUpdatedTitle")}</span>
        <#elseif dmKind == "verified">${msg("dmVerifiedTitle")}
        <#elseif dmKind == "logout">${msg("dmLoggedOutTitle")}
        <#elseif messageHeader??>${kcSanitize(msg("${messageHeader}"))?no_esc}
        <#elseif dmKind == "actions">${msg("dmActionsTitle")}
        <#else>${msg("dmInfoTitle")}</#if>
    <#elseif section = "lead">
        <#if dmKind == "password">${msg("dmDoneLead")}
        <#elseif dmKind == "logout">${msg("dmLoggedOutLead")}
        <#elseif dmKind == "updated"><span data-dm-if-password="${msg("dmDoneLead")}">${kcSanitize(dmText)?no_esc}</span>
        <#elseif dmKind == "actions">${kcSanitize(dmText)?no_esc}<#list requiredActions>: <#items as reqActionItem><strong>${kcSanitize(msg("requiredAction.${reqActionItem}"))?no_esc}</strong><#sep>, </#items></#list>
        <#else>${kcSanitize(dmText)?no_esc}</#if>
    <#elseif section = "form">
        <div id="kc-info-message" class="dm-actions">
            <#if dmOk>
                <#assign dmNext = (pageRedirectUri?has_content)?then(pageRedirectUri!'', layout.site())>
                <a class="dm-btn" href="${dmNext}"<#if dmKind == "updated"> data-dm-if-password="${msg("doLogIn")}"</#if>>${msg((dmKind == "password")?then("doLogIn", (dmKind == "logout")?then("dmLoginAgain", "dmContinue")))}</a>
                <#if dmKind == "password" || dmKind == "updated">
                    <p class="dm-hint" style="text-align:center"<#if dmKind == "updated"> data-dm-show-if-password hidden</#if>>${msg("dmNotYou")} <a href="mailto:help@darumen.kz">${msg("dmWriteSupport")}</a>.</p>
                </#if>
            <#elseif skipLink??>
            <#elseif pageRedirectUri?has_content>
                <a class="dm-btn" href="${pageRedirectUri}">${msg("backToApplication")}</a>
            <#elseif actionUri?has_content>
                <a class="dm-btn" href="${actionUri}">${msg("proceedWithAction")}</a>
            <#elseif (client.baseUrl)?has_content>
                <a class="dm-btn secondary" href="${client.baseUrl}">${msg("backToApplication")}</a>
            </#if>
        </div>
    </#if>
</@layout.registrationLayout>
