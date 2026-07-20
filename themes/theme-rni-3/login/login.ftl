<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${msg("loginTitle", realm.displayName)!}</title>
    <link rel="stylesheet" href="${url.resourcesPath}/style.css">
    <script src="https://unpkg.com/lucide@0.474.0/dist/umd/lucide.min.js"></script>
</head>
<body>
    <div class="container">
        <!-- Panel izquierdo -->
        <div class="left-panel">
            <!-- Contenido para desktop -->
            <div class="desktop-content">
                <h2>Sistema RNI</h2>
                <p>Registro Nacional de Inmunizaciones</p>
                <ul>
                    <li><span class="check-icon"><i data-lucide="check"></i></span> Registro rápido y seguro</li>
                    <li><span class="check-icon"><i data-lucide="check"></i></span> Acceso al historial completo de pacientes</li>
                </ul>
            </div>

            <!-- Título para móvil -->
            <h2 class="mobile-title">RNI</h2>
        </div>

        <!-- Panel derecho: Formulario -->
        <div class="right-panel">
            <div class="container-login">
                <div class="header mobile-header">
                    <h2>RNI</h2>
                    <div class="underline"></div>
                    <br>
                </div>
                
                <h3>Bienvenido</h3>
                <p>Para acceder a su cuenta o crear un nuevo registro, por favor inicie sesión.</p>

                <#if message?has_content>
                    <div class="alert alert-${message.type}" id="login-alert">
                        <i data-lucide="triangle-alert" class="alert-icon"></i>
                        <span>${message.summary}</span>
                    </div>
                </#if>

                <form id="kc-form-login" action="${url.loginAction}" method="post">
                    <div class="form-group">
                        <label for="username">Usuario</label>
                        <input type="text" id="username" name="username" value="${(login.username!'')}" autocomplete="off" autofocus />
                    </div>

                    <div class="form-group">
                        <label for="password">Contraseña</label>
                            <div class="password-wrapper">
                                <input type="password" id="password" name="password" autocomplete="off" />
                                <span class="toggle-password">
                                    <i data-lucide="eye"></i>
                                </span>
                            </div>
                    </div>

                    <div class="form-group checkbox-row">
                        <div class="remember-me">
                            <input type="checkbox" id="rememberMe" name="rememberMe"<#if rememberMe?? && rememberMe> checked</#if> />
                            <label for="rememberMe">Recordar cuenta</label>
                        </div>
                        <a href="${url.loginResetCredentialsUrl}" class="forgot-link">¿Olvidaste tu contraseña?</a>
                    </div>

                    <div class="form-group">
                        <button type="submit" class="btn-primary">INICIAR SESION</button>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <script>
        lucide.createIcons();

        // Shake animation on error
        const loginAlert = document.getElementById('login-alert');
        if (loginAlert) {
            const form = document.getElementById('kc-form-login');
            if (form) {
                form.classList.add('shake');
                form.addEventListener('animationend', () => form.classList.remove('shake'));
            }
        }

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
    </script>

    <div id="resolution-error" style="display:none; position:fixed; top:0; left:0; width:100%; height:100%; background:#f5f5f5; display:flex; align-items:center; justify-content:center; font-family:Arial, sans-serif; color:#333; text-align:center; padding:20px; z-index:-1;">
        <div>
            <h2 style="font-size:18px; margin-bottom:10px;">Resolución mínima requerida</h2>
            <p style="font-size:14px; line-height:1.5;">
                Por favor, use un dispositivo con al menos:<br>
                <strong>320px de ancho</strong> y <strong>480px de alto</strong>.
            </p>
        </div>
    </div>
    
</body>
</html>