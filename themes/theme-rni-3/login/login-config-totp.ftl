<#import "template-reset.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
<div class="container">
       <#-- ESTA ES LA BARRA SENCILLA -->
    <div class="barra-azul-rni">RNI</div> 
        <div class="container-totp-password totp-container">
            <div class="totp-icon">
                <i data-lucide="smartphone"></i>
            </div>
            <h2 class="reset-title">${msg("loginTotpTitle")}</h2>
            <p class="reset-subtitle">${msg("configureTotpMessage")}</p>

            <!-- Pasos de configuración -->
            <div class="totp-steps">
                <!-- Paso 1: Instalar app -->
                <div class="totp-step">
                    <div class="totp-step-number">1</div>
                    <div class="totp-step-content">
                        <p class="totp-step-title">${msg("loginTotpStep1")}</p>
                        <div class="totp-apps">
                            <#if totp.policy.supportedApplications??>
                                <#list totp.policy.supportedApplications as app>
                                    <span class="totp-app-badge">${app}</span>
                                </#list>
                            <#else>
                                <span class="totp-app-badge">Google Authenticator</span>
                                <span class="totp-app-badge">Microsoft Authenticator</span>
                                <span class="totp-app-badge">FreeOTP</span>
                            </#if>
                        </div>
                    </div>
                </div>

                <!-- Paso 2: Escanear QR o código manual -->
                <div class="totp-step">
                    <div class="totp-step-number">2</div>
                    <div class="totp-step-content">
                        <#if mode?? && mode = "manual">
                            <p class="totp-step-title">${msg("loginTotpManualStep2")}</p>
                            <div class="totp-secret-key">
                                <code id="kc-totp-secret-key">${totp.totpSecretEncoded}</code>
                            </div>
                            <a href="${totp.qrUrl}" class="totp-toggle-link">
                                <i data-lucide="qr-code"></i>
                                <span>${msg("loginTotpScanBarcode")}</span>
                            </a>
                            <div class="totp-manual-details">
                                <ul>
                                    <li>${msg("loginTotpType")}: ${msg("loginTotp." + totp.policy.type)}</li>
                                    <li>${msg("loginTotpAlgorithm")}: ${totp.policy.getAlgorithmKey()}</li>
                                    <li>${msg("loginTotpDigits")}: ${totp.policy.digits}</li>
                                    <#if totp.policy.type = "totp">
                                        <li>${msg("loginTotpInterval")}: ${totp.policy.period}</li>
                                    <#elseif totp.policy.type = "hotp">
                                        <li>${msg("loginTotpCounter")}: ${totp.policy.initialCounter}</li>
                                    </#if>
                                </ul>
                            </div>
                        <#else>
                            <p class="totp-step-title">${msg("loginTotpStep2")}</p>
                            <div class="totp-qr-wrapper">
                                <img id="kc-totp-secret-qr-code" src="data:image/png;base64, ${totp.totpSecretQrCode}" alt="Código QR"/>
                            </div>
                            <a href="${totp.manualUrl}" class="totp-toggle-link">
                                <i data-lucide="keyboard"></i>
                                <span>${msg("loginTotpUnableToScan")}</span>
                            </a>
                        </#if>
                    </div>
                </div>

                <!-- Paso 3: Ingresar código -->
                <div class="totp-step">
                    <div class="totp-step-number">3</div>
                    <div class="totp-step-content">
                        <p class="totp-step-title">${msg("loginTotpStep3")}</p>
                    </div>
                </div>
            </div>

            <!-- Formulario -->
            <form action="${url.loginAction}" id="kc-totp-settings-form" method="post">
                <div class="form-group">
                    <label for="totp">${msg("authenticatorCode")} <span class="required-mark">*</span></label>
                    <input type="text" id="totp" name="totp" autocomplete="off"
                           aria-invalid="<#if messagesPerField.existsError('totp')>true</#if>"
                    />
                    <#if messagesPerField.existsError('totp')>
                        <span class="kc-input-error-message" aria-live="polite">
                            ${kcSanitize(messagesPerField.get('totp'))?no_esc}
                        </span>
                    </#if>
                </div>

                <div class="form-group">
                    <label for="userLabel">${msg("loginTotpDeviceName")} <#if totp.otpCredentials?size gte 1><span class="required-mark">*</span></#if></label>
                    <input type="text" id="userLabel" name="userLabel" autocomplete="off"
                           aria-invalid="<#if messagesPerField.existsError('userLabel')>true</#if>"
                    />
                    <#if messagesPerField.existsError('userLabel')>
                        <span class="kc-input-error-message" aria-live="polite">
                            ${kcSanitize(messagesPerField.get('userLabel'))?no_esc}
                        </span>
                    </#if>
                </div>

                <input type="hidden" id="totpSecret" name="totpSecret" value="${totp.totpSecret}" />
                <#if mode??><input type="hidden" id="mode" name="mode" value="${mode}"/></#if>

                <#if isAppInitiatedAction??>
                    <button type="submit" class="btn-primary" id="saveTOTPBtn">GUARDAR</button>
                    <button type="submit" name="cancel-aia" value="true" class="btn-primary btn-secondary" id="cancelTOTPBtn">${msg("doCancel")}</button>
                <#else>
                    <button type="submit" class="btn-primary" id="saveTOTPBtn">GUARDAR</button>
                </#if>
            </form>

            <div class="back-to-login">
                <a href="${url.loginRestartFlowUrl}">
                    <i data-lucide="arrow-left"></i>
                    <span>Reiniciar inicio de sesión</span>
                </a>
            </div>
        </div>
</div>
        <script src="https://unpkg.com/lucide@0.474.0/dist/umd/lucide.min.js"></script>
        <script>
            lucide.createIcons();
        </script>

</@layout.registrationLayout>
