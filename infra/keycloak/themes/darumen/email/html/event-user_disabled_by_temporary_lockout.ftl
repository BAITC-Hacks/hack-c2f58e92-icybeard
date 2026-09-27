<#-- Уведомление безопасности: вход временно заблокирован защитой от подбора (5 неудачных попыток, 15 минут).
     Страница входа об этом намеренно молчит (Keycloak не раскрывает блокировку), поэтому владелец узнаёт из письма. -->
<#import "template.ftl" as layout>
<@layout.emailLayout title=msg("dmEvLockoutTitle") footer=msg("dmFooterSecurity")>
<@layout.p>${msg("dmEvLockoutText", (user.email)!(user.username)!'')}</@layout.p>
<@layout.facts rows=[[msg("dmEvTime"), event.date?datetime?string("dd.MM.yyyy, HH:mm")], [msg("dmEvIp"), (event.ipAddress)!'—']]/>
<@layout.p weight=500>${msg("dmEvLockoutNotYou")}</@layout.p>
</@layout.emailLayout>
