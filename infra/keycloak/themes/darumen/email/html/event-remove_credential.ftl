<#-- Уведомление безопасности: удалён способ входа (обычно приложение-аутентификатор). -->
<#import "template.ftl" as layout>
<#assign ct = (event.getDetail("credential_type"))!''>
<#assign kind = (ct == "otp")?then("OtpRemoved", "CredRemoved")>
<@layout.emailLayout title=msg("dmEv${kind}Title") footer=msg("dmFooterSecurity")>
<@layout.p>${msg("dmEv${kind}Text", (user.email)!(user.username)!'')}</@layout.p>
<@layout.facts rows=[[msg("dmEvTime"), event.date?datetime?string("dd.MM.yyyy, HH:mm")], [msg("dmEvIp"), (event.ipAddress)!'—']]/>
<@layout.p weight=500>${msg("dmEvNotYou")}</@layout.p>
</@layout.emailLayout>
