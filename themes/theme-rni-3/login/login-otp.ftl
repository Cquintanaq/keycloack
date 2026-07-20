<#import "template-reset.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "header">
        <!-- No mostramos título aquí, lo ponemos dentro del contenedor -->
    <#elseif section = "form">
      <div class="barra-azul-rni">RNI</div>
        <div class="container-update-password">
            <form id="kc-otp-login-form" action="${url.loginAction}" method="post">
                <div class="update-password-icon">
                    <i data-lucide="shield-check"></i>
                </div>
                <h2 class="reset-title">Verificación en dos pasos</h2>
                <p class="reset-subtitle">Ingrese el código de verificación generado por su aplicación de autenticación.</p>

                <#if otpLogin.userOtpCredentials?size gt 1>
                    <div class="${properties.kcFormGroupClass!}">
                        <label for="selectedCredentialId">Dispositivo de autenticación</label>
                        <select id="selectedCredentialId" name="selectedCredentialId" class="${properties.kcInputClass!}">
                            <#list otpLogin.userOtpCredentials as otpCredential>
                                <option value="${otpCredential.id}" <#if otpCredential.id == otpLogin.selectedCredentialId>selected</#if>>${otpCredential.userLabel}</option>
                            </#list>
                        </select>
                    </div>
                </#if>

                <div class="${properties.kcFormGroupClass!}">
                    <label for="otp">Código de verificación</label>
                    <input type="text" id="otp" name="otp" autocomplete="one-time-code"
                           autofocus inputmode="numeric" pattern="[0-9]*" maxlength="6"
                           aria-invalid="<#if messagesPerField.existsError('totp')>true</#if>"
                    />
                    <#if messagesPerField.existsError('totp')>
                        <span class="kc-input-error-message" aria-live="polite">
                            ${kcSanitize(messagesPerField.get('totp'))?no_esc}
                        </span>
                    </#if>
                </div>

                <div class="${properties.kcFormGroupClass!}">
                    <button type="submit" class="btn-primary">VERIFICAR</button>
                </div>
            </form>

            <div class="back-to-login">
                <a href="${url.loginRestartFlowUrl}">
                    <i data-lucide="arrow-left"></i>
                    <span>Reiniciar inicio de sesión</span>
                </a>
            </div>
        </div>

        <script src="https://unpkg.com/lucide@0.474.0/dist/umd/lucide.min.js"></script>
        <script>
            lucide.createIcons();
        </script>
    </#if>
</@layout.registrationLayout>
