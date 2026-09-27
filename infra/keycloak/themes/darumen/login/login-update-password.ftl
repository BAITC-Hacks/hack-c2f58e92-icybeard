<#-- W-Auth-Reset. Правила берутся из политики realm (passwordPolicies), шкала и чек-лист считаются в браузере
     (resources/js/darumen.js, без внешних скриптов); «не совпадает с прошлыми N» проверяет только сервер.
     После смены пароля завершаются сессии на других устройствах (logout-sessions=on). -->
<#import "template.ftl" as layout>
<#assign dmUser = (username)!((auth.attemptedUsername)!'')>
<#assign dmMin = (passwordPolicies.length)!12>
<#assign dmUpper = (passwordPolicies.upperCase)!0>
<#assign dmLower = (passwordPolicies.lowerCase)!0>
<#assign dmDigits = (passwordPolicies.digits)!0>
<#assign dmHistory = (passwordPolicies.passwordHistory)!0>
<#assign dmNotUser = (passwordPolicies.notUsername)!false>
<#assign dmErrNew = messagesPerField.existsError('password')>
<#assign dmErrConfirm = messagesPerField.existsError('password-confirm')>
<#-- Нарушение политики Keycloak возвращает общим сообщением (не по полю) — подсвечиваем поле нового пароля -->
<#assign dmInvalidNew = dmErrNew || (message?has_content && message.type == 'error' && !dmErrConfirm)>
<@layout.registrationLayout displayMessage=(!messagesPerField.existsError('password','password-confirm') && !(message?has_content && message.type == 'warning')); section>
    <#if section = "header">
        ${msg("updatePasswordTitle")}
    <#elseif section = "lead">
        <#if dmUser?has_content>${msg("dmResetFor", dmUser)}<#else>${msg("dmResetLead")}</#if>
    <#elseif section = "form">
        <form id="kc-passwd-update-form" class="dm-form" action="${url.loginAction}" method="post" novalidate data-dm-password-form>
            <input type="text" name="username" value="${dmUser}" autocomplete="username" readonly hidden>
            <div class="dm-field">
                <label for="password-new" class="dm-label">${msg("passwordNew")}</label>
                <div class="dm-pass">
                    <input id="password-new" name="password-new" class="dm-input" type="password" autocomplete="new-password" autofocus dir="ltr"
                           data-dm-strength aria-describedby="dm-rules<#if dmErrNew> input-error-password</#if>" aria-invalid="${dmInvalidNew?c}"/>
                    <button class="dm-show" type="button" data-dm-toggle="password-new" aria-controls="password-new" aria-pressed="false"
                            data-show="${msg("dmShow")}" data-hide="${msg("dmHide")}">${msg("dmShow")}</button>
                </div>
                <#if dmErrNew>
                    <p id="input-error-password" class="dm-error" aria-live="polite">${kcSanitize(messagesPerField.get('password'))?no_esc}</p>
                </#if>
            </div>
            <div class="dm-meter" data-level="0" aria-live="polite">
                <div class="dm-meter-bars" aria-hidden="true"><span></span><span></span><span></span><span></span></div>
                <span class="dm-meter-label" data-labels="${msg("dmStrengthEmpty")}|${msg("dmStrength1")}|${msg("dmStrength2")}|${msg("dmStrength3")}|${msg("dmStrength4")}">${msg("dmStrengthEmpty")}</span>
            </div>
            <ul class="dm-rules" id="dm-rules" data-min="${dmMin?c}" data-upper="${dmUpper?c}" data-lower="${dmLower?c}" data-digits="${dmDigits?c}" data-user="${dmUser}">
                <li data-rule="length">${msg("dmRuleLength", dmMin?c)}</li>
                <#if dmUpper gt 0 || dmLower gt 0><li data-rule="case">${msg("dmRuleCase")}</li></#if>
                <#if dmDigits gt 0><li data-rule="digit">${msg("dmRuleDigit")}</li></#if>
                <#if dmNotUser><li data-rule="user">${msg("dmRuleNotUser")}</li></#if>
                <#if dmHistory gt 0><li class="server">${msg("dmRuleHistory", dmHistory?c)}</li></#if>
            </ul>
            <div class="dm-field">
                <label for="password-confirm" class="dm-label">${msg("passwordConfirm")}</label>
                <input id="password-confirm" name="password-confirm" class="dm-input" type="password" autocomplete="new-password" dir="ltr"
                       data-dm-confirm="password-new" data-mismatch="${msg("notMatchPasswordMessage")}"
                       aria-invalid="${dmErrConfirm?c}" aria-describedby="input-error-password-confirm"/>
                <p id="input-error-password-confirm" class="dm-error" aria-live="polite"<#if !dmErrConfirm> hidden</#if>><#if dmErrConfirm>${kcSanitize(messagesPerField.get('password-confirm'))?no_esc}</#if></p>
            </div>
            <input type="hidden" name="logout-sessions" value="on">
            <div class="dm-actions">
                <button class="dm-btn" type="submit">${msg("dmSavePassword")}</button>
                <#if isAppInitiatedAction??>
                    <button class="dm-btn secondary" type="submit" name="cancel-aia" value="true" formnovalidate>${msg("doCancel")}</button>
                </#if>
            </div>
            <p class="dm-note">${msg("dmResetSessionsNote")}</p>
        </form>
    </#if>
</@layout.registrationLayout>
