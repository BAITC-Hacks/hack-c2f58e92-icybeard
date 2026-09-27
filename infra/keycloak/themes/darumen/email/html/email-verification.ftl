<#-- Подтверждение почты (required action VERIFY_EMAIL). -->
<#import "template.ftl" as layout>
<@layout.emailLayout title=msg("dmVerifyTitle") footer=msg("dmFooterVerify")>
<@layout.p>${msg("dmVerifyText", (user.email)!'')}</@layout.p>
<@layout.p muted=true>${msg("dmVerifyExpiry", linkExpirationFormatter(linkExpiration))}</@layout.p>
<@layout.button href=link label=msg("dmVerifyButton")/>
<@layout.fallback href=link/>
</@layout.emailLayout>
