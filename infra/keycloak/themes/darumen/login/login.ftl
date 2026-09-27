<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('username','password') displayInfo=false; section>
    <#if section = "header">
        ${msg("loginAccountTitle")}
    <#elseif section = "form">
        <p class="dm-lead">${msg("dmLead")}</p>
        <#if realm.password>
            <form id="kc-form-login" class="dm-form" onsubmit="login.disabled = true; return true;" action="${url.loginAction}" method="post">
                <#if !usernameHidden??>
                    <div class="dm-field">
                        <label for="username" class="dm-label"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>
                        <input tabindex="1" id="username" class="dm-input" name="username" value="${(login.username!'')}" type="text" autofocus autocomplete="username" placeholder="citizen1"
                               aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>" dir="ltr"/>
                    </div>
                </#if>
                <div class="dm-field">
                    <label for="password" class="dm-label">${msg("password")}</label>
                    <div class="dm-pass" dir="ltr">
                        <input tabindex="2" id="password" class="dm-input" name="password" type="password" autocomplete="current-password"
                               aria-invalid="<#if messagesPerField.existsError('username','password')>true</#if>"/>
                        <button class="dm-eye" type="button" id="dm-eye" aria-label="${msg("showPassword")}" aria-controls="password" data-show="${msg('showPassword')}" data-hide="${msg('hidePassword')}" tabindex="3">
                            <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>
                        </button>
                    </div>
                    <#if messagesPerField.existsError('username','password')>
                        <p id="input-error" class="dm-error" aria-live="polite">${kcSanitize(messagesPerField.getFirstError('username','password'))?no_esc}</p>
                    </#if>
                </div>
                <input type="hidden" id="id-hidden-input" name="credentialId" <#if auth.selectedCredential?has_content>value="${auth.selectedCredential}"</#if>/>
                <button tabindex="4" class="dm-btn" name="login" id="kc-login" type="submit">${msg("doLogIn")}</button>
                <p class="dm-note">${msg("dmNote")}</p>
                <#if client?? && client.baseUrl?has_content>
                    <div class="dm-links"><a href="${client.baseUrl}">${msg("dmBack")}</a></div>
                </#if>
            </form>
        </#if>
        <script>
            (function () {
                var b = document.getElementById('dm-eye'), p = document.getElementById('password');
                if (!b || !p) return;
                b.addEventListener('click', function () {
                    var show = p.type === 'password';
                    p.type = show ? 'text' : 'password';
                    b.setAttribute('aria-label', show ? b.dataset.hide : b.dataset.show);
                    b.style.color = show ? '#0F2C59' : '';
                });
            })();
        </script>
    </#if>
</@layout.registrationLayout>
