<#import "template-reset.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "header">
        <!-- No mostramos título aquí, lo ponemos dentro del contenedor -->
    <#elseif section = "form">
        <div class="container-error-password">
            <div class="expired-icon">
                <i data-lucide="circle-alert"></i>
            </div>
            <h2 class="reset-title">${msg("errorTitle")}</h2>
            <#if message?has_content && message.summary?has_content>
                <p class="reset-subtitle">${kcSanitize(message.summary)?no_esc}</p>
            </#if>

            <div class="back-to-login">
                <a href="${url.loginUrl}">
                    <i data-lucide="arrow-left"></i>
                    <span>${msg("backToLogin")}</span>
                </a>
            </div>
        </div>

        <script src="https://unpkg.com/lucide@0.474.0/dist/umd/lucide.min.js"></script>
        <script>
            lucide.createIcons();
        </script>
    </#if>
</@layout.registrationLayout>
