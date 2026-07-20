<#import "template-reset.ftl" as layout>
<@layout.registrationLayout>
    <div class="container"> 
    <div class="barra-azul-rni">RNI</div> 
        <div class="right-panel">
            <div class=container-login-password>
                <!-- Eliminado header mobile-header duplicado para evitar doble título en mobile -->
                 
                <form id="kc-reset-password-form" class="${properties.kcFormClass!}" action="${url.loginAction}" method="post">
                    <div class="reset-password-icon">
                        <i data-lucide="mail"></i>
                    </div>
                    <h2 class="reset-title">¿Has olvidado tu contraseña?</h2>
                    <p class="reset-subtitle">Te enviaremos un enlace para restablecer tu contraseña</p>
                    <div class="${properties.kcFormGroupClass!}">
                        <div class="${properties.kcLabelWrapperClass!}">
                            <label for="username" class="${properties.kcLabelClass!}"><#if !realm.loginWithEmailAllowed>${msg("username")}<#elseif !realm.registrationEmailAsUsername>${msg("usernameOrEmail")}<#else>${msg("email")}</#if></label>
                        </div>
                        <div class="${properties.kcInputWrapperClass!}">
                            <input type="text" id="username" name="username" class="${properties.kcInputClass!}" autofocus value="${(auth.attemptedUsername!'')}" aria-invalid="<#if messagesPerField.existsError('username')>true</#if>" dir="ltr"/>
                            <#if messagesPerField.existsError('username')>
                                <span id="input-error-username" class="${properties.kcInputErrorMessageClass!}" aria-live="polite">
                                    ${kcSanitize(messagesPerField.get('username'))?no_esc}
                                </span>
                            </#if>
                        </div>
                    </div>
                    <div class="${properties.kcFormGroupClass!}">
                        <button type="submit" class="btn-primary">ENVIAR</button>
                    </div>
                    <div class="back-to-login">
                        <a href="${url.loginUrl}">
                            <i data-lucide="arrow-left"></i>
                            <span>${msg("backToLogin")}</span>
                        </a>
                    </div>
                </form>
                </div>
            </div>
    </div>
    <script src="https://unpkg.com/lucide@0.474.0/dist/umd/lucide.min.js"></script>
    <script>
        lucide.createIcons();
    </script>
</@layout.registrationLayout>