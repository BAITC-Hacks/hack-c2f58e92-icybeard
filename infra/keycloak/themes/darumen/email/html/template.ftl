<#-- Письма Darumen по доске W-Mail: белая карточка на #F5F6F8, знак и «darumen», заголовок 20/500, текст 15 px,
     кнопка #5B5BD6 radius 12, «Кнопка не работает? Скопируйте ссылку», подвал 12 px с help@darumen.kz.
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

<#macro p muted=false size=15 weight=400>
<p style="margin:0 0 12px;font-family:${dmFont};font-size:${size}px;line-height:1.45;font-weight:${weight};color:<#if muted>#535768<#else>#333333</#if>;"><#nested></p>
</#macro>

<#macro button href label color="#5B5BD6">
<table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:4px 0 16px;border-collapse:separate;"><tr>
<td style="border-radius:12px;background:${color};" bgcolor="${color}">
<a href="${href}" target="_blank" style="display:inline-block;padding:12px 24px;font-family:${dmFont};font-size:15px;font-weight:500;line-height:20px;color:#FFFFFF;text-decoration:none;border-radius:12px;">${label}</a>
</td></tr></table>
</#macro>

<#macro fallback href>
<p style="margin:0 0 12px;font-family:${dmFont};font-size:13px;line-height:1.45;color:#535768;">${msg("dmButtonFallback")} <a href="${href}" target="_blank" style="color:#4646B8;word-break:break-all;">${href}</a></p>
</#macro>

<#macro facts rows>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 12px;background:#EAECF2;border-radius:12px;" bgcolor="#EAECF2">
<tr><td style="padding:12px 16px;font-family:${dmFont};font-size:14px;line-height:1.6;color:#333333;">
<#list rows as row><span style="color:#535768;">${row[0]} · </span>${row[1]}<#sep><br></#sep></#list>
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
<table role="presentation" width="560" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:560px;background:#FFFFFF;border-radius:16px;border-collapse:separate;" bgcolor="#FFFFFF">
<tr><td style="padding:20px 24px 12px;">
    <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin:0 0 16px;"><tr>
        <td style="width:10px;height:22px;background:#333333;border-radius:5px 0 0 5px;font-size:0;line-height:0;" bgcolor="#333333">&nbsp;</td>
        <td style="width:3px;font-size:0;line-height:0;">&nbsp;</td>
        <td style="width:11px;height:22px;vertical-align:bottom;font-size:0;line-height:0;"><div style="width:11px;height:11px;background:#5B5BD6;border-radius:0 0 11px 0;font-size:0;line-height:0;">&nbsp;</div></td>
        <td style="padding-left:10px;font-family:${dmFont};font-size:20px;font-weight:600;letter-spacing:-0.02em;color:#333333;">darumen</td>
    </tr></table>
    <#if title?has_content>
    <h1 style="margin:0 0 12px;font-family:${dmFont};font-size:20px;font-weight:500;letter-spacing:-0.01em;line-height:1.3;color:#333333;">${title}</h1>
    </#if>
    <#nested>
    <p style="margin:8px 0 8px;font-family:${dmFont};font-size:12px;line-height:1.45;color:#535768;"><#if footer?has_content>${footer} · </#if>${msg("dmFooterAuto")} · <a href="mailto:help@darumen.kz" style="color:#535768;">help@darumen.kz</a></p>
</td></tr>
</table>
<p style="margin:16px 0 0;font-family:${dmFont};font-size:12px;line-height:1.45;color:#535768;">${msg("dmFooterStand")}</p>
</td></tr>
</table>
</body>
</html>
</#macro>
