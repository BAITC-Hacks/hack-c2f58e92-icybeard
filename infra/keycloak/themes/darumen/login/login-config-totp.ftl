<#-- Настройка приложения-аутентификатора (required action CONFIGURE_TOTP, kc_action=CONFIGURE_TOTP из «Безопасности»):
     QR-код или ручной ключ, параметры политики realm (TOTP, 6 цифр, 30 с), код и название устройства. -->
<#import "template.ftl" as layout>
<#assign dmErrCode = messagesPerField.existsError('totp')>
<#assign dmErrLabel = messagesPerField.existsError('userLabel')>
<@layout.registrationLayout displayRequiredFields=false displayMessage=!messagesPerField.existsError('totp','userLabel'); section>
    <#if section = "header">
        ${msg("loginTotpTitle")}
    <#elseif section = "lead">
        ${msg("dmTotpLead")}
    <#elseif section = "form">
        <ol class="dm-steps" id="kc-totp-settings">
            <li><div>
                <p>${msg("loginTotpStep1")}</p>
                <ul class="dm-apps" id="kc-totp-supported-apps">
                    <#list totp.supportedApplications as app><li>${msg(app)}</li></#list>
                </ul>
            </div></li>
            <#if mode?? && mode = "manual">
                <li><div>
                    <p>${msg("loginTotpManualStep2")}</p>
                    <code class="dm-secret" id="kc-totp-secret-key">${totp.totpSecretEncoded}</code>
                    <ul class="dm-kv">
                        <li id="kc-totp-type">${msg("loginTotpType")}: ${msg("loginTotp." + totp.policy.type)}</li>
                        <li id="kc-totp-algorithm">${msg("loginTotpAlgorithm")}: ${totp.policy.getAlgorithmKey()}</li>
                        <li id="kc-totp-digits">${msg("loginTotpDigits")}: ${totp.policy.digits}</li>
                        <#if totp.policy.type = "totp">
                            <li id="kc-totp-period">${msg("loginTotpInterval")}: ${totp.policy.period}</li>
                        <#elseif totp.policy.type = "hotp">
                            <li id="kc-totp-counter">${msg("loginTotpCounter")}: ${totp.policy.initialCounter}</li>
                        </#if>
                    </ul>
                    <p style="margin-top:8px"><a class="dm-link" href="${totp.qrUrl}" id="mode-barcode">${msg("loginTotpScanBarcode")}</a></p>
                </div></li>
            <#else>
                <li><div>
                    <p>${msg("loginTotpStep2")}</p>
                    <img class="dm-qr" id="kc-totp-secret-qr-code" src="data:image/png;base64, ${totp.totpSecretQrCode}" alt="${msg("dmTotpQrAlt")}" width="180" height="180">
                    <a class="dm-link" href="${totp.manualUrl}" id="mode-manual">${msg("loginTotpUnableToScan")}</a>
                </div></li>
            </#if>
            <li><div><p>${msg("loginTotpStep3")}</p></div></li>
        </ol>

        <form action="${url.loginAction}" class="dm-form" id="kc-totp-settings-form" method="post" novalidate>
            <div class="dm-field">
                <label for="totp" class="dm-label">${msg("authenticatorCode")}</label>
                <input id="totp" name="totp" class="dm-input dm-otp-single" type="text" inputmode="numeric" pattern="[0-9]*" maxlength="${totp.policy.digits}"
                       autocomplete="one-time-code" required data-dm-otp="${totp.policy.digits}" data-digit-label="${msg("dmOtpDigit")}"
                       aria-invalid="${dmErrCode?c}"<#if dmErrCode> aria-describedby="input-error-otp-code"</#if>/>
                <#if dmErrCode>
                    <p id="input-error-otp-code" class="dm-error" aria-live="polite">${kcSanitize(messagesPerField.get('totp'))?no_esc}</p>
                </#if>
                <input type="hidden" id="totpSecret" name="totpSecret" value="${totp.totpSecret}"/>
                <#if mode??><input type="hidden" id="mode" name="mode" value="${mode}"/></#if>
            </div>
            <div class="dm-field">
                <label for="userLabel" class="dm-label">${msg("loginTotpDeviceName")}<#if totp.otpCredentials?size gte 1> <span class="dm-required" aria-hidden="true">*</span></#if></label>
                <input id="userLabel" name="userLabel" class="dm-input" type="text" autocomplete="off" placeholder="${msg("dmTotpDevicePlaceholder")}"
                       aria-invalid="${dmErrLabel?c}"<#if dmErrLabel> aria-describedby="input-error-otp-label"</#if>/>
                <#if dmErrLabel>
                    <p id="input-error-otp-label" class="dm-error" aria-live="polite">${kcSanitize(messagesPerField.get('userLabel'))?no_esc}</p>
                <#else>
                    <p class="dm-hint">${msg("loginTotpStep3DeviceName")}</p>
                </#if>
            </div>
            <label class="dm-check" for="logout-sessions"><input type="checkbox" id="logout-sessions" name="logout-sessions" value="on" checked>${msg("logoutOtherSessions")}</label>
            <div class="dm-actions">
                <button class="dm-btn" type="submit" id="saveTOTPBtn">${msg("dmTotpSubmit")}</button>
                <#if isAppInitiatedAction??>
                    <button class="dm-btn secondary" type="submit" id="cancelTOTPBtn" name="cancel-aia" value="true" formnovalidate>${msg("doCancel")}</button>
                </#if>
            </div>
        </form>
    </#if>
</@layout.registrationLayout>
