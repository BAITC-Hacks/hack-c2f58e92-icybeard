<#-- W-Auth-Forgot. Состояние ошибки поля — пустая или неверная строка (missingUsernameMessage и т. п.).
     «Почта не найдена» Keycloak не сообщает намеренно (защита от перебора аккаунтов): для неизвестной почты
     он показывает то же «Проверьте почту», что и для существующей. Предупреждение «Почтовый сервер недоступен»
     скрыто и появляется, только если API сайта отвечает email.available: false (GET /api/v1/public/service-status,
     обработчик [data-dm-service-status] в js/darumen.js); без ответа API страница работает как раньше. -->
<#import "template.ftl" as layout>
<#assign dmErr = messagesPerField.existsError('username')>
<@layout.registrationLayout displayInfo=false displayMessage=!dmErr; section>
    <#if section = "header">
        ${msg("emailForgotTitle")}
    <#elseif section = "lead">
        ${msg("dmForgotLead")}
    <#elseif section = "form">
        <div class="dm-alert warning" role="status" data-dm-service-status="${layout.site()}api/v1/public/service-status" hidden><@layout.icon name="mail"/><span>${msg("dmEmailDown")}</span></div>
        <form id="kc-reset-password-form" class="dm-form" action="${url.loginAction}" method="post" novalidate>
            <div class="dm-field">
                <label for="username" class="dm-label"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>
                <input id="username" name="username" class="dm-input" type="text" value="${(auth.attemptedUsername)!''}" autofocus
                       autocomplete="username" autocapitalize="none" spellcheck="false" dir="ltr"
                       aria-invalid="${dmErr?c}"<#if dmErr> aria-describedby="input-error-username"</#if>/>
                <#if dmErr>
                    <p id="input-error-username" class="dm-error" aria-live="polite">${kcSanitize(messagesPerField.get('username'))?no_esc}</p>
                </#if>
            </div>
            <button class="dm-btn" id="kc-form-buttons" type="submit">${msg("dmSendLink")}</button>
            <div class="dm-links"><a href="${url.loginUrl}">${msg("dmBackToLogin")}</a></div>
            <p class="dm-note">${msg("dmLinkLifetime")}</p>
        </form>
    </#if>
</@layout.registrationLayout>
