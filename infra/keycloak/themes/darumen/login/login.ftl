<#-- W-Auth-Login. Keycloak после отправки письма сброса возвращает на эту же страницу с emailSentMessage —
     тогда показываем состояние W-Auth-Sent «Проверьте почту» вместо формы. Блокировка администратором
     (accountDisabledMessage) и истёкшая попытка входа (loginTimeout) — карточки состояний W-Auth-Blocked. -->
<#import "template.ftl" as layout>
<#assign dmState = "">
<#if message?has_content>
    <#if message.summary == msg("emailSentMessage")>
        <#assign dmState = "sent">
    <#elseif message.summary == msg("accountDisabledMessage") || message.summary == msg("accountTemporarilyDisabledMessage")>
        <#assign dmState = "blocked">
    <#elseif message.summary == msg("loginTimeout") || message.summary == msg("expiredCodeMessage") || message.summary == msg("sessionNotActiveMessage")>
        <#assign dmState = "expired">
    </#if>
</#if>
<#assign dmFieldError = messagesPerField.existsError('username','password')>
<@layout.registrationLayout displayMessage=(dmState == "" && !dmFieldError) centered=(dmState == "sent"); section>
<#if dmState == "sent">
    <#if section = "icon">
        <span class="dm-icon"><@layout.icon name="mail"/></span>
    <#elseif section = "header">
        ${msg("dmSentTitle")}
    <#elseif section = "lead">
        ${msg("dmSentLead")}
    <#elseif section = "form">
        <div class="dm-alert" role="note"><@layout.icon name="info"/><span>${msg("dmSentSpam")}</span></div>
        <div class="dm-actions">
            <a class="dm-btn secondary" id="dm-resend" href="${url.loginResetCredentialsUrl}" data-dm-countdown="60"
               data-label="${msg("dmSentResend")}" data-wait="${msg("dmSentResendIn")}">${msg("dmSentResend")}</a>
            <div class="dm-links">
                <a href="${url.loginResetCredentialsUrl}">${msg("dmSentOtherEmail")}</a>
                <span class="sep" aria-hidden="true">·</span>
                <a href="${url.loginUrl}">${msg("dmBackToLogin")}</a>
            </div>
        </div>
    </#if>
<#else>
    <#if section = "header">
        ${msg("loginAccountTitle")}
    <#elseif section = "lead">
        ${msg("dmLoginLead")}
    <#elseif section = "form">
        <#if dmState == "blocked">
            <div class="dm-state" role="alert">
                <span class="dm-icon danger"><@layout.icon name="lock"/></span>
                <div>
                    <h2>${msg("dmBlockedTitle")}</h2>
                    <p>${msg("dmBlockedText")}</p>
                    <a class="dm-link" href="mailto:help@darumen.kz">${msg("dmWriteAdmin")}</a>
                </div>
            </div>
        <#elseif dmState == "expired">
            <div class="dm-state" role="status">
                <span class="dm-icon info"><@layout.icon name="clock"/></span>
                <div>
                    <h2>${msg("dmExpiredTitle")}</h2>
                    <p>${msg("dmExpiredLoginText")}</p>
                </div>
            </div>
        </#if>

        <#-- eGov mobile: интеграции нет, вход не имитируется — кнопка раскрывает пояснение -->
        <details class="dm-egov">
            <summary class="dm-btn" role="button"><@layout.icon name="qr"/>${msg("dmEgov")}</summary>
            <div class="dm-alert" role="note"><@layout.icon name="info"/><span>${msg("dmEgovSoon")}</span></div>
        </details>
        <div class="dm-divider">${msg("dmOrByLogin")}</div>

        <#if realm.password>
            <form id="kc-form-login" class="dm-form" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post" novalidate>
                <#if !usernameHidden??>
                    <div class="dm-field">
                        <label for="username" class="dm-label"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>
                        <input id="username" class="dm-input" name="username" value="${(login.username!'')}" type="text" autofocus
                               autocomplete="username" autocapitalize="none" spellcheck="false" dir="ltr"
                               aria-invalid="${dmFieldError?c}"<#if dmFieldError> aria-describedby="input-error"</#if>/>
                    </div>
                </#if>
                <div class="dm-field">
                    <label for="password" class="dm-label">${msg("password")}</label>
                    <div class="dm-pass">
                        <input id="password" class="dm-input" name="password" type="password" autocomplete="current-password" dir="ltr"
                               <#if usernameHidden??>autofocus</#if> aria-invalid="${dmFieldError?c}"<#if dmFieldError> aria-describedby="input-error"</#if>/>
                        <button class="dm-show" type="button" data-dm-toggle="password" aria-controls="password" aria-pressed="false"
                                data-show="${msg("dmShow")}" data-hide="${msg("dmHide")}">${msg("dmShow")}</button>
                    </div>
                    <#if dmFieldError>
                        <p id="input-error" class="dm-error" aria-live="polite">${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}</p>
                    </#if>
                </div>
                <div class="dm-row">
                    <#if realm.rememberMe && !usernameHidden??>
                        <label class="dm-check" for="rememberMe"><input id="rememberMe" name="rememberMe" type="checkbox"<#if login.rememberMe??> checked</#if>>${msg("rememberMe")}</label>
                    </#if>
                    <span class="dm-grow"></span>
                    <#if realm.resetPasswordAllowed>
                        <a class="dm-link" href="${url.loginResetCredentialsUrl}">${msg("doForgotPassword")}</a>
                    </#if>
                </div>
                <input type="hidden" id="id-hidden-input" name="credentialId"<#if auth.selectedCredential?has_content> value="${auth.selectedCredential}"</#if>/>
                <button class="dm-btn" name="login" id="kc-login" type="submit">${msg("doLogIn")}</button>
                <p class="dm-foot-line">${msg("dmNoAccount")} <a href="${layout.site()}signup">${msg("dmRegisterOrg")}</a></p>
            </form>
        </#if>
    </#if>
</#if>
</@layout.registrationLayout>
