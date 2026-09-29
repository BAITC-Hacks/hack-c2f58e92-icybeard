<#-- Письма Darumen по доске mail-new («синяя гамма», handoff/tokens.css): белая карточка на #F5F6F8 с радиусом 20,
     знак и «darumen» (16/800), заголовок 20/800 #1B2440, текст 14 px, кнопка-pill #2F6FE4, подложка ссылки #F4F7FD,
     «Кнопка не работает? Скопируйте ссылку», подвал 12 px с help@darumen.kz.
     Только таблицы и инлайн-стили: почтовые клиенты режут <style>, SVG и data:-картинки. Шаблоны родителя base
     (события, тестовое письмо и т. п.) тоже рендерятся в этой обёртке с тем, что пришло в <#nested>. -->
<#assign dmFont = "Manrope,'Segoe UI',Roboto,Arial,sans-serif">

<#function greetName>
    <#if user?? && (user.firstName)?has_content && (user.lastName)?has_content>
        <#return user.firstName?substring(0, 1) + ". " + user.lastName>
    <#elseif user?? && (user.firstName)?has_content>
        <#return user.firstName>
    <#elseif user?? && (user.username)?has_content>
        <#return user.username>
    </#if>
    <#return "">
</#function>

<#macro p muted=false size=14 weight=400>
<p style="margin:0 0 12px;font-family:${dmFont};font-size:${size}px;line-height:1.55;font-weight:${weight};color:<#if muted>#48536D<#else>#1B2440</#if>;"><#nested></p>
</#macro>

<#macro button href label color="#2F6FE4">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:4px 0 16px;border-collapse:separate;"><tr>
<td style="border-radius:999px;background:${color};" bgcolor="${color}">
<a href="${href}" target="_blank" style="display:inline-block;padding:12px 24px;font-family:${dmFont};font-size:14px;font-weight:700;line-height:20px;color:#FFFFFF;text-decoration:none;border-radius:999px;">${label}</a>
</td></tr></table>
</#macro>

<#macro fallback href>
<p style="margin:0 0 12px;padding:12px 14px;background:#F4F7FD;border-radius:12px;font-family:${dmFont};font-size:12px;line-height:1.5;color:#48536D;">${msg("dmButtonFallback")} <a href="${href}" target="_blank" style="color:#1E4FB8;font-weight:700;word-break:break-all;">${href}</a></p>
</#macro>

<#macro facts rows>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 12px;background:#F4F7FD;border-radius:12px;" bgcolor="#F4F7FD">
<tr><td style="padding:12px 14px;font-family:${dmFont};font-size:13px;line-height:1.6;color:#1B2440;font-weight:700;">
<#list rows as row><span style="color:#48536D;font-weight:400;">${row[0]} · </span>${row[1]}<#sep><br></#sep></#list>
</td></tr></table>
</#macro>

<#macro emailLayout title="" footer="">
<!DOCTYPE html>
<html lang="${(locale.language)!'ru'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>${title}</title>
</head>
<body style="margin:0;padding:0;background:#F5F6F8;" bgcolor="#F5F6F8">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#F5F6F8;" bgcolor="#F5F6F8">
<tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:560px;background:#FFFFFF;border-radius:20px;border-collapse:separate;" bgcolor="#FFFFFF">
<tr><td style="padding:22px 26px 14px;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;"><tr>
        <td style="width:10px;height:22px;background:#1B2440;border-radius:5px 0 0 5px;font-size:0;line-height:0;" bgcolor="#1B2440">&nbsp;</td>
        <td style="width:3px;font-size:0;line-height:0;">&nbsp;</td>
        <td style="width:11px;height:22px;vertical-align:bottom;font-size:0;line-height:0;"><div style="width:11px;height:11px;background:#2F6FE4;border-radius:0 0 11px 0;font-size:0;line-height:0;">&nbsp;</div></td>
        <td style="padding-left:10px;font-family:${dmFont};font-size:16px;font-weight:800;letter-spacing:-0.02em;color:#1B2440;">darumen</td>
    </tr></table>
    <#if title?has_content>
    <h1 style="margin:0 0 12px;font-family:${dmFont};font-size:20px;font-weight:800;letter-spacing:-0.01em;line-height:1.3;color:#1B2440;">${title}</h1>
    </#if>
    <#nested>
    <p style="margin:8px 0 8px;padding-top:14px;border-top:1px solid #E1E8F5;font-family:${dmFont};font-size:12px;line-height:1.5;color:#76819A;"><#if footer?has_content>${footer} · </#if>${msg("dmFooterAuto")} · <a href="mailto:help@darumen.kz" style="color:#76819A;">help@darumen.kz</a></p>
</td></tr>
</table>
<p style="margin:16px 0 0;font-family:${dmFont};font-size:12px;line-height:1.5;color:#76819A;">${msg("dmFooterStand")}</p>
</td></tr>
</table>
</body>
</html>
</#macro>
