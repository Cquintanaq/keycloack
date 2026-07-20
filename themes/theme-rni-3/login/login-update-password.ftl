<#import "template-reset.ftl" as layout>
<@layout.registrationLayout displayMessage=false; section>
    <#if section = "header">
        <!-- No mostramos título aquí, lo ponemos dentro del contenedor -->
    <#elseif section = "form">
      <div class="barra-azul-rni">RNI</div> 
        <div class="container-update-password">
            <form id="kc-passwd-update-form" class="${properties.kcFormClass!}" action="${url.loginAction}" method="post">
                <div class="update-password-icon">
                    <i data-lucide="lock-keyhole"></i>
                </div>
                <h2 class="reset-title">${msg("updatePasswordTitle")}</h2>
                <p class="reset-subtitle">Ingrese su nueva contraseña para continuar</p>

                <input type="text" id="username" name="username" value="${username}" autocomplete="username"
                       readonly="readonly" style="display:none;"/>

                <div class="${properties.kcFormGroupClass!}">
                    <label for="password-new" class="${properties.kcLabelClass!}">${msg("passwordNew")}</label>
                    <div class="password-wrapper">
                        <input type="password" id="password-new" name="password-new" class="${properties.kcInputClass!}"
                               autofocus autocomplete="new-password"
                               aria-invalid="<#if messagesPerField.existsError('password','password-confirm')>true</#if>"
                        />
                      
                        <span class="toggle-password">
                            <i data-lucide="eye"></i>
                        </span>
                    </div>
                      </br>
                     <label for="password-confirm" class="${properties.kcLabelClass!}">${msg("passwordConfirm")}</label>
                    <div class="password-wrapper">
                        <input type="password" id="password-confirm" name="password-confirm"
                               class="${properties.kcInputClass!}"
                               autocomplete="new-password"
                               aria-invalid="<#if messagesPerField.existsError('password-confirm')>true</#if>"
                        />
                        <span class="toggle-password">
                            <i data-lucide="eye"></i>
                        </span>
                    </div>

                    <div class="password-requirements" id="password-requirements">
                        <div class="req" id="req-length"><i data-lucide="circle-x"></i> <span>Mínimo 12 caracteres</span></div>
                        <div class="req" id="req-upper"><i data-lucide="circle-x"></i> <span>Al menos 1 mayúscula</span></div>
                        <div class="req" id="req-lower"><i data-lucide="circle-x"></i> <span>Al menos 1 minúscula</span></div>
                        <div class="req" id="req-number"><i data-lucide="circle-x"></i> <span>Al menos 1 número</span></div>
                        <div class="req" id="req-special"><i data-lucide="circle-x"></i> <span>Al menos 1 símbolo especial</span></div>
                        <div class="req" id="req-match"><i data-lucide="circle-x"></i> <span>Las contraseñas coinciden</span></div>
                    </div>
                </div>

            

                <#if isAppInitiatedAction??>
                    <div class="checkbox-row" style="margin-bottom: 15px;">
                        <div class="remember-me">
                            <input type="checkbox" id="logout-sessions" name="logout-sessions" value="on" checked />
                            <label for="logout-sessions">${msg("logoutOtherSessions")}</label>
                        </div>
                    </div>
                </#if>

                <div class="${properties.kcFormGroupClass!}">
                    <#if isAppInitiatedAction??>
                        <button type="submit" class="btn-primary">ACTUALIZAR CONTRASEÑA</button>
                        <button type="submit" name="cancel-aia" value="true" class="btn-primary" style="background-color: #666; margin-top: 10px;">${msg("doCancel")}</button>
                    <#else>
                        <button type="submit" class="btn-primary">ACTUALIZAR CONTRASEÑA</button>
                    </#if>
                </div>
            </form>
        </div>

        <script src="https://unpkg.com/lucide@0.474.0/dist/umd/lucide.min.js"></script>
        <script>
            lucide.createIcons();

            // Toggle password visibility
            document.querySelectorAll('.toggle-password').forEach(el => {
                el.addEventListener('click', function() {
                    const input = this.closest('.password-wrapper').querySelector('input');
                    if (input.type === 'password') {
                        input.type = 'text';
                        this.innerHTML = '<i data-lucide="eye-off"></i>';
                    } else {
                        input.type = 'password';
                        this.innerHTML = '<i data-lucide="eye"></i>';
                    }
                    lucide.createIcons();
                });
            });

            // Password requirements validation
            const passwordInput = document.getElementById('password-new');
            const confirmInput = document.getElementById('password-confirm');

            const rules = [
                { id: 'req-length', test: v => v.length >= 12 },
                { id: 'req-upper', test: v => /[A-Z]/.test(v) },
                { id: 'req-lower', test: v => /[a-z]/.test(v) },
                { id: 'req-number', test: v => /[0-9]/.test(v) },
                { id: 'req-special', test: v => /[^A-Za-z0-9]/.test(v) },
            ];

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

            function validatePassword() {
                const val = passwordInput.value;
                rules.forEach(r => updateReq(r.id, r.test(val)));
            }

            function validateMatch() {
                const match = passwordInput.value.length > 0 && passwordInput.value === confirmInput.value;
                updateReq('req-match', match);
            }

            passwordInput.addEventListener('input', () => { validatePassword(); validateMatch(); });
            confirmInput.addEventListener('input', validateMatch);
        </script>
    </#if>
</@layout.registrationLayout>
