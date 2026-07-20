<#import "template-reset.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "header">
        <!-- No mostramos título aquí, lo ponemos dentro del contenedor -->
    <#elseif section = "form">
      <div class="barra-azul-rni">RNI</div>
        <div class="container-update-password">
            <form id="kc-update-profile-form" class="${properties.kcFormClass!}" action="${url.loginAction}" method="post">

                <div class="update-password-icon">
                    <i data-lucide="user-pen"></i>
                </div>
                <h2 class="reset-title">${msg("loginProfileTitle","Actualizar cuenta")}</h2>
                <p class="reset-subtitle">Complete la información de su cuenta para continuar</p>

                <#if messagesPerField.existsError('global')>
                    <div class="alert-error" style="color: #d32f2f; background: #fdecea; border-radius: 6px; padding: 10px 14px; margin-bottom: 16px; font-size: 0.9rem;">
                        ${kcSanitize(messagesPerField.getFirstError('global'))?no_esc}
                    </div>
                </#if>

                <div class="${properties.kcFormGroupClass!}">
                    <label for="email" class="${properties.kcLabelClass!}">${msg("email")}</label>
                    <input type="text" id="email" name="email" value="${(user.email!'')}"
                           class="${properties.kcInputClass!}"
                           autofocus
                           aria-invalid="<#if messagesPerField.existsError('email')>true</#if>"
                    />
                    <#if messagesPerField.existsError('email')>
                        <span class="input-error" style="color: #d32f2f; font-size: 0.85rem;">
                            ${kcSanitize(messagesPerField.getFirstError('email'))?no_esc}
                        </span>
                    </#if>
                </div>

                <div class="${properties.kcFormGroupClass!}" style="margin-top: 12px;">
                    <label for="email-confirm" class="${properties.kcLabelClass!}">Confirmar correo electrónico</label>
                    <input type="text" id="email-confirm"
                           class="${properties.kcInputClass!}"
                           autocomplete="off"
                    />
                    <div class="password-requirements" id="email-requirements" style="margin-top: 8px;">
                        <div class="req req-fail" id="req-email-format"><i data-lucide="circle-x"></i> <span>Formato de correo válido</span></div>
                        <div class="req req-fail" id="req-email-match"><i data-lucide="circle-x"></i> <span>Los correos coinciden</span></div>
                    </div>
                </div>

                <div class="${properties.kcFormGroupClass!}" style="margin-top: 12px;">
                    <label for="firstName" class="${properties.kcLabelClass!}">${msg("firstName","Nombre")}</label>
                    <input type="text" id="firstName" name="firstName" value="${(user.firstName!'')}"
                           class="${properties.kcInputClass!}"
                           aria-invalid="<#if messagesPerField.existsError('firstName')>true</#if>"
                    />
                    <#if messagesPerField.existsError('firstName')>
                        <span class="input-error" style="color: #d32f2f; font-size: 0.85rem;">
                            ${kcSanitize(messagesPerField.getFirstError('firstName'))?no_esc}
                        </span>
                    </#if>
                </div>

                <div class="${properties.kcFormGroupClass!}" style="margin-top: 12px;">
                    <label for="lastName" class="${properties.kcLabelClass!}">${msg("lastName","Apellido")}</label>
                    <input type="text" id="lastName" name="lastName" value="${(user.lastName!'')}"
                           class="${properties.kcInputClass!}"
                           aria-invalid="<#if messagesPerField.existsError('lastName')>true</#if>"
                    />
                    <#if messagesPerField.existsError('lastName')>
                        <span class="input-error" style="color: #d32f2f; font-size: 0.85rem;">
                            ${kcSanitize(messagesPerField.getFirstError('lastName'))?no_esc}
                        </span>
                    </#if>
                </div>

                <div class="${properties.kcFormGroupClass!}" style="margin-top: 20px;">
                    <button type="submit" class="btn-primary" value="Submit">${msg("doSubmit")}</button>
                </div>
            </form>
        </div>

        <script src="https://unpkg.com/lucide@0.474.0/dist/umd/lucide.min.js"></script>
        <script>
            lucide.createIcons();

            const emailInput   = document.getElementById('email');
            const confirmInput = document.getElementById('email-confirm');
            const submitBtn    = document.querySelector('#kc-update-profile-form .btn-primary');
            const emailRegex   = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

            // Deshabilitar submit inicialmente
            submitBtn.disabled = true;
            submitBtn.style.opacity = '0.5';
            submitBtn.style.cursor = 'not-allowed';

            function updateReq(id, passed) {
                const el = document.getElementById(id);
                const icon = el.querySelector('svg') || el.querySelector('i');
                if (icon) {
                    const newIcon = document.createElement('i');
                    newIcon.dataset.lucide = passed ? 'circle-check' : 'circle-x';
                    icon.replaceWith(newIcon);
                }
                el.classList.toggle('req-pass', passed);
                el.classList.toggle('req-fail', !passed);
                lucide.createIcons();
            }

            function validateEmail() {
                const val     = emailInput.value.trim();
                const confVal = confirmInput.value.trim();
                const validFormat = emailRegex.test(val);
                const match       = val.length > 0 && val === confVal;

                updateReq('req-email-format', validFormat);
                updateReq('req-email-match', match);

                const allValid = validFormat && match;
                submitBtn.disabled = !allValid;
                submitBtn.style.opacity = allValid ? '1' : '0.5';
                submitBtn.style.cursor  = allValid ? 'pointer' : 'not-allowed';
            }

            emailInput.addEventListener('input', validateEmail);
            confirmInput.addEventListener('input', validateEmail);

            // Bloquear pegar en el campo de confirmación
            confirmInput.addEventListener('paste', function(e) {
                e.preventDefault();
            });
        </script>
    </#if>
</@layout.registrationLayout>
