<#-- Уведомление безопасности (слушатель событий email): сменён пароль или подключён аутентификатор.
     Аналог письма «Новое устройство» с доски W-Mail в пределах того, что Keycloak умеет без расширений. -->
<#import "template.ftl" as layout>
<#assign ct = (event.getDetail("credential_type"))!''>
<#assign kind = (ct == "password")?then("Password", (ct == "otp")?then("OtpAdded", "Cred"))>
<@layout.emailLayout title=msg("dmEv${kind}Title") footer=msg("dmFooterSecurity")>
<@layout.p>${msg("dmEv${kind}Text", (user.email)!(user.username)!'')}</@layout.p>
<@layout.facts rows=[[msg("dmEvTime"), event.date?datetime?string("dd.MM.yyyy, HH:mm")], [msg("dmEvIp"), (event.ipAddress)!'—']]/>
<@layout.p weight=500>${msg("dmEvNotYou")}</@layout.p>
</@layout.emailLayout>
