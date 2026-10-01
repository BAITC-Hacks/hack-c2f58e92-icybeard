<#-- Обёртка всех страниц темы входа Darumen (доски W-Auth-*): шапка со знаком и RU/KK, карточка 420 px,
     под карточкой «Поддержка» и сноска про синтетические данные. Ссылки «Сроки ожидания без входа»
     с досок здесь нет: гостевой режим убран (docs/rbac.md). -->

<#-- Корень сайта: client.baseUrl клиентов darumen-* (из DARUMEN_WEB_URL при импорте realm); для служебных клиентов
     Keycloak (account при выходе без client_id и т. п.) и без клиента — dmSiteUrl из theme.properties. С «/» на конце. -->
<#function site>
    <#local u = "">
    <#if (client.clientId)?? && client.clientId?starts_with("darumen") && (client.baseUrl)?has_content>
        <#local u = client.baseUrl>
    <#elseif (properties.dmSiteUrl)?has_content && !properties.dmSiteUrl?starts_with("$")>
        <#local u = properties.dmSiteUrl>
    <#else>
        <#local u = "/">
    </#if>
    <#return u?ends_with("/")?then(u, u + "/")>
</#function>

<#-- Иконки 24×24 с досок (обводка 1.75, currentColor) -->
<#macro icon name>
<svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><#switch name><#case "mail"><path d="M3.5 6h17v12h-17z"/><path d="M3.5 6.5l8.5 6.5 8.5-6.5"/><#break><#case "check"><path d="M20 6 9 17l-5-5"/><#break><#case "clock"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/><#break><#case "lock"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/><#break><#case "refresh"><path d="M20 12a8 8 0 1 1-2.5-5.8"/><path d="M20 4v4h-4"/><#break><#case "shield"><path d="M12 3l7 3v6c0 4.2-2.9 7.3-7 8.4-4.1-1.1-7-4.2-7-8.4V6z"/><#break><#case "phone"><rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/><#break><#case "sms"><path d="M4 5h16v11H9l-5 4z"/><path d="M8 10h8"/><#break><#case "qr"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><path d="M14 14h3v3h-3zM18 18h3v3h-3zM18 14h3M14 18v3"/><#break><#case "logout"><path d="M9 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h3"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/><#break><#case "alert"><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5"/><path d="M12 16.3v.2"/><#break><#default><circle cx="12" cy="12" r="9"/><path d="M12 11v5.5"/><path d="M12 7.8v0.2"/></#switch></svg>
</#macro>

<#macro alert type text>
    <#local ic = (type == "success")?then("check", (type == "error")?then("alert", (type == "warning")?then("clock", "info")))>
    <div class="dm-alert ${type}" role="${(type == 'error')?then('alert','status')}"><@icon name=ic/><span>${kcSanitize(text)?no_esc}</span></div>
</#macro>

<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false centered=false>
<!DOCTYPE html>
<html class="dm"<#if realm.internationalizationEnabled> lang="${locale.currentLanguageTag}"</#if>>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <meta name="theme-color" content="#F5F6F8">
    <title>${msg("loginTitle",(realm.displayName!'Darumen Health'))}</title>
    <link rel="icon" href="${url.resourcesPath}/img/favicon.svg" type="image/svg+xml">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
    <#if properties.stylesCommon?has_content>
        <#list properties.stylesCommon?split(' ') as style>
            <link href="${url.resourcesCommonPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <#if properties.styles?has_content>
        <#list properties.styles?split(' ') as style>
            <link href="${url.resourcesPath}/${style}" rel="stylesheet" />
        </#list>
    </#if>
    <script src="${url.resourcesPath}/js/darumen.js" defer></script>
    <script type="module">
        import { startSessionPolling } from "${url.resourcesPath}/js/authChecker.js";
        startSessionPolling("${url.ssoLoginInOtherTabsUrl?no_esc}");
    </script>
</head>
<body class="dm ${bodyClass}">
<#assign dmHeader><#nested "header"></#assign>
<#assign dmLead><#nested "lead"></#assign>
<#assign dmIcon><#nested "icon"></#assign>
<header class="dm-top">
    <a class="dm-brand" href="${site()}" aria-label="Darumen Health">
        <svg viewBox="20 20 63 60" width="28" height="27" aria-hidden="true"><path class="dm-mark-block" d="M30 22h19v56H30a8 8 0 0 1-8-8V30a8 8 0 0 1 8-8z"/><path class="dm-mark-arc" d="M53 25a25 25 0 0 1 25 25" fill="none" stroke-width="6" stroke-linecap="round"/><path class="dm-mark-sector" d="M53 50h28a28 28 0 0 1-28 28z"/></svg>
        <span>darumen</span>
    </a>
    <#if realm.internationalizationEnabled && locale.supported?size gt 1>
        <nav class="dm-locale" aria-label="${msg("languages")}">
            <#list locale.supported?sort_by("languageTag")?reverse as l>
                <a href="${l.url}" hreflang="${l.languageTag}" lang="${l.languageTag}"<#if l.languageTag == locale.currentLanguageTag> class="on" aria-current="true"</#if>>${l.languageTag?upper_case}</a>
            </#list>
        </nav>
    </#if>
</header>
<main class="dm-main">
    <div class="dm-col">
        <section class="dm-card<#if centered> center</#if>" aria-labelledby="kc-page-title">
            <div class="dm-head">
                <#if dmIcon?markup_string?trim?has_content>${dmIcon}</#if>
                <h1 class="dm-title" id="kc-page-title">${dmHeader}</h1>
                <#if dmLead?markup_string?trim?has_content><p class="dm-lead">${dmLead}</p></#if>
                <#if auth?has_content && auth.showUsername() && !auth.showResetCredentials()>
                    <#nested "show-username">
                    <p class="dm-lead" id="kc-username">${msg("dmSignedAs")} <strong>${auth.attemptedUsername}</strong> · <a id="reset-login" href="${url.loginRestartFlowUrl}">${msg("dmOtherAccount")}</a></p>
                </#if>
            </div>
            <#if displayRequiredFields>
                <p class="dm-hint"><span class="dm-required">*</span> ${msg("requiredFields")}</p>
            </#if>
            <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
                <@alert type=message.type text=message.summary/>
            </#if>
            <#nested "form">
            <#if auth?has_content && auth.showTryAnotherWayLink()>
                <form id="kc-select-try-another-way-form" action="${url.loginAction}" method="post" novalidate>
                    <input type="hidden" name="tryAnotherWay" value="on"/>
                    <button type="submit" id="try-another-way" class="dm-btn secondary">${msg("doTryAnotherWay")}</button>
                </form>
            </#if>
            <#nested "socialProviders">
            <#if displayInfo>
                <div id="kc-info" class="dm-foot-line"><#nested "info"></div>
            </#if>
        </section>
        <nav class="dm-meta" aria-label="${msg("dmMetaNav")}">
            <span>${msg("dmSupport")}: <a href="mailto:help@darumen.kz">help@darumen.kz</a></span>
        </nav>
        <p class="dm-note">${msg("dmNote")}</p>
    </div>
</main>
</body>
</html>
</#macro>
