<#-- W-Auth-2FA. Основной способ — код из приложения-аутентификатора (TOTP, 6 цифр, 30 с). Шесть полей по цифре
     строит resources/js/darumen.js поверх настоящего поля otp (без JS остаётся одно поле). При нескольких
     устройствах — выбор (selectedCredentialId). «Не спрашивать на этом устройстве 30 дней» и резервные коды
     в Keycloak 26.0 без расширений недоступны — на странице их нет; SMS — «после интеграции». -->
<#import "template.ftl" as layout>
<#assign dmErr = messagesPerField.existsError('totp')>
<@layout.registrationLayout displayMessage=!dmErr; section>
    <#if section = "header">
        ${msg("dmOtpTitle")}
    <#elseif section = "lead">
        ${msg("dmOtpLead")}
    <#elseif section = "form">
        <form id="kc-otp-login-form" class="dm-form" action="${url.loginAction}" method="post" novalidate>
            <#if otpLogin.userOtpCredentials?size gt 1>
                <fieldset class="dm-options" style="border:0;margin:0;padding:0">
                    <legend class="dm-label" style="margin-bottom:6px">${msg("dmOtpDevice")}</legend>
                    <#list otpLogin.userOtpCredentials as otpCredential>
                        <label class="dm-option" for="kc-otp-credential-${otpCredential?index}">
                            <input type="radio" id="kc-otp-credential-${otpCredential?index}" name="selectedCredentialId" value="${otpCredential.id}"<#if otpCredential.id == (otpLogin.selectedCredentialId!'')> checked</#if>>
                            <@layout.icon name="phone"/>
                            <span class="t"><b>${otpCredential.userLabel!msg("dmOtpApp")}</b><small>${msg("dmOtpAppHint")}</small></span>
                        </label>
                    </#list>
                </fieldset>
            <#else>
                <input id="selectedCredentialId" type="hidden" name="selectedCredentialId" value="${otpLogin.selectedCredentialId!''}">
            </#if>
            <div class="dm-field">
                <label for="otp" class="dm-label">${msg("loginOtpOneTime")}</label>
                <input id="otp" name="otp" class="dm-input dm-otp-single" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="6"
                       autocomplete="one-time-code" autofocus data-dm-otp="6" data-digit-label="${msg("dmOtpDigit")}"
                       aria-invalid="${dmErr?c}"<#if dmErr> aria-describedby="input-error-otp-code"</#if>/>
                <#if dmErr>
                    <p id="input-error-otp-code" class="dm-error" aria-live="polite">${kcSanitize(messagesPerField.get('totp'))?no_esc}</p>
                </#if>
            </div>
            <button class="dm-btn" name="login" id="kc-login" type="submit">${msg("dmOtpSubmit")}</button>
            <div class="dm-divider">${msg("dmOtherWays")}</div>
            <div class="dm-options">
                <div class="dm-option" aria-disabled="true" style="cursor:default">
                    <@layout.icon name="sms"/>
                    <span class="t"><b>${msg("dmOtpSms")}</b><small>${msg("dmOtpSmsSoon")}</small></span>
                </div>
            </div>
            <p class="dm-note">${msg("dmOtpLost")}</p>
        </form>
    </#if>
</@layout.registrationLayout>
