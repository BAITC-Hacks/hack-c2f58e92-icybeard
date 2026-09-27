<#macro registrationLayout bodyClass="" displayInfo=false displayMessage=true displayRequiredFields=false>
<!DOCTYPE html>
<html class="dm"<#if realm.internationalizationEnabled> lang="${locale.currentLanguageTag}"</#if>>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <meta name="theme-color" content="#0F2C59">
    <title>${msg("loginTitle",(realm.displayName!''))}</title>
    <link rel="icon" href="${url.resourcesPath}/img/favicon.svg" type="image/svg+xml">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600&display=swap" rel="stylesheet">
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
    <script type="module">
        import { startSessionPolling } from "${url.resourcesPath}/js/authChecker.js";
        startSessionPolling("${url.ssoLoginInOtherTabsUrl?no_esc}");
    </script>
</head>
<body class="dm ${bodyClass}">
<header class="dm-top">
    <a class="dm-brand" href="<#if client?? && client.baseUrl?has_content>${client.baseUrl}<#else>/</#if>">
        <svg viewBox="20 20 63 60" width="28" height="27" aria-hidden="true"><path d="M30 22h19v56H30a8 8 0 0 1-8-8V30a8 8 0 0 1 8-8z" fill="#0F2C59"/><path d="M53 25a25 25 0 0 1 25 25" fill="none" stroke="#FF7F50" stroke-width="6" stroke-linecap="round"/><path d="M53 50h28a28 28 0 0 1-28 28z" fill="#FF7F50"/></svg>
        <span>darumen</span>
    </a>
    <#if realm.internationalizationEnabled && locale.supported?size gt 1>
        <nav class="dm-locale" aria-label="${msg("languages")}">
            <#list locale.supported as l>
                <a href="${l.url}"<#if l.languageTag == locale.currentLanguageTag> class="on" aria-current="true"</#if>>${l.label}</a>
            </#list>
        </nav>
    </#if>
</header>
<main class="dm-main">
    <section class="dm-card">
        <#if displayRequiredFields>
            <p class="dm-note"><span class="required">*</span> ${msg("requiredFields")}</p>
        </#if>
        <#if !(auth?has_content && auth.showUsername() && !auth.showResetCredentials())>
            <h1 class="dm-title" id="kc-page-title"><#nested "header"></h1>
        <#else>
            <#nested "show-username">
            <p class="dm-lead" id="kc-attempted-username">${auth.attemptedUsername} · <a id="reset-login" href="${url.loginRestartFlowUrl}">${msg("restartLoginTooltip")}</a></p>
        </#if>
        <#if displayMessage && message?has_content && (message.type != 'warning' || !isAppInitiatedAction??)>
            <div class="dm-alert ${message.type}" role="alert">${kcSanitize(message.summary)?no_esc}</div>
        </#if>
        <#nested "form">
        <#if auth?has_content && auth.showTryAnotherWayLink()>
            <form id="kc-select-try-another-way-form" action="${url.loginAction}" method="post" class="dm-links">
                <input type="hidden" name="tryAnotherWay" value="on"/>
                <a href="#" id="try-another-way" onclick="document.forms['kc-select-try-another-way-form'].requestSubmit();return false;">${msg("doTryAnotherWay")}</a>
            </form>
        </#if>
        <#nested "socialProviders">
        <#if displayInfo>
            <div id="kc-info" class="dm-lead"><#nested "info"></div>
        </#if>
    </section>
</main>
<footer class="dm-foot">Darumen Health · GovTech Camp 2026 · ${msg("dmNote")}</footer>
</body>
</html>
</#macro>
