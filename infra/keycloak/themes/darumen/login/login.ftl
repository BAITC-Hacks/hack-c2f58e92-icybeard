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
<#-- Повторная проверка перед важным действием (смена пароля, настройка второго фактора): Keycloak уже знает
     пользователя (usernameHidden) и просит только пароль. Показываем это как «Подтвердите, что это вы», а не как
     обычный вход: без eGov, «Запомнить меня» и регистрации организации. -->
<#assign dmReauth = usernameHidden??>
<#-- «Please re-authenticate to continue» от Keycloak дублирует наш подзаголовок — в этом режиме его не показываем -->
<#assign dmReauthNote = dmReauth && message?has_content && message.summary == msg("reauthenticate")>
<@layout.registrationLayout displayMessage=(dmState == "" && !dmFieldError && !dmReauthNote) centered=(dmState == "sent"); section>
<#if dmState == "sent">
    <#if section = "icon">
        <span class="dm-icon"><@layout.icon name="mail"/></span>
    <#elseif section = "header">
        ${msg("dmSentTitle")}
    <#elseif section = "lead">
        ${msg("dmSentLead")}
    <#elseif section = "form">
        <div class="dm-alert" role="note"><@layout.icon name="info"/><span>${msg("dmSentSpam")}</span></div>
        <#-- скрыто; показывается, только если API сайта отвечает email.available: false (js/darumen.js) -->
        <div class="dm-alert warning" role="status" data-dm-service-status="${layout.site()}api/v1/public/service-status" hidden><@layout.icon name="mail"/><span>${msg("dmEmailDownSent")}</span></div>
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
        <#if dmReauth>${msg("dmReauthTitle")}<#else>${msg("loginAccountTitle")}</#if>
    <#elseif section = "lead">
        <#if dmReauth>${msg("dmReauthLead")}<#else>${msg("dmLoginLead")}</#if>
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

        <#if !dmReauth>
        <#-- eGov mobile: адрес сервиса (Smart Bridge) не предоставлен, вход не имитируется — кнопка раскрывает пояснение -->
        <details class="dm-egov">
            <summary class="dm-btn secondary" role="button"><@layout.icon name="qr"/>${msg("dmEgov")}</summary>
            <div class="dm-alert" role="note"><@layout.icon name="info"/><span>${msg("dmEgovSoon")}</span></div>
        </details>
        <div class="dm-divider">${msg("dmOrByLogin")}</div>
        </#if>

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
                <button class="dm-btn" name="login" id="kc-login" type="submit"><#if dmReauth>${msg("dmReauthSubmit")}<#else>${msg("doLogIn")}</#if></button>
                <#if !dmReauth><p class="dm-foot-line">${msg("dmNoAccount")} <a href="${layout.site()}signup" data-dm-site="signup">${msg("dmRegisterOrg")}</a></p></#if>
            </form>
        </#if>
    </#if>
</#if>
</@layout.registrationLayout>
