<#import "template-reset.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "header">
        <!-- No mostramos título aquí, lo ponemos dentro del contenedor -->
    <#elseif section = "form">
        <div class="container-error-password">
            <div class="expired-icon">
                <i data-lucide="clock-alert"></i>
            </div>
            <h2 class="reset-title">${msg("pageExpiredTitle")}</h2>
            <p class="reset-subtitle">El enlace que utilizaste ya no es válido</p>

            <div class="expired-actions">
                <p class="expired-msg">${msg("pageExpiredMsg1")}  
                    <a id="loginRestartLink" href="${url.loginRestartFlowUrl}">haz clic aquí</a>
                </p>
                <p class="expired-msg">${msg("pageExpiredMsg2")}  
                    <a id="loginContinueLink" href="${url.loginAction}">haz clic aquí</a>
                </p>
            </div>

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
