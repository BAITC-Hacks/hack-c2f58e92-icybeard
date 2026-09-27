<#-- «Другие способы входа» (Try another way): список доступных пользователю способов из потока realm. -->
<#import "template.ftl" as layout>
<@layout.registrationLayout displayInfo=false; section>
    <#if section = "header">
        ${msg("loginChooseAuthenticator")}
    <#elseif section = "form">
        <div class="dm-options" role="list">
            <#list auth.authenticationSelections as authenticationSelection>
                <form id="kc-select-credential-form-${authenticationSelection?index}" action="${url.loginAction}" method="post" role="listitem" style="margin:0">
                    <input type="hidden" name="authenticationExecution" value="${authenticationSelection.authExecId}">
                    <button type="submit" class="dm-option">
                        <@layout.icon name=(authenticationSelection.displayName?contains("otp"))?then("phone", "lock")/>
                        <span class="t"><b>${msg('${authenticationSelection.displayName}')}</b><small>${msg('${authenticationSelection.helpText}')}</small></span>
                    </button>
                </form>
            </#list>
        </div>
    </#if>
</@layout.registrationLayout>
