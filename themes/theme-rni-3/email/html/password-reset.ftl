<#ftl output_format="HTML">
<#-- Asunto personalizado para Keycloak -->
<#assign subject = "Restablecimiento de contraseña – Registro Nacional de Inmunización">
<div style="max-width:480px;margin:0 auto;padding:32px 24px 24px 24px;border:1px solid #e0e0e0;border-radius:8px;font-family:sans-serif;background:#fff;">
	<h2 style="color:#2c3e50;margin-top:0;">Hola,</h2>
	<p>Hemos recibido una solicitud para restablecer la contraseña de su cuenta. Si usted realizó esta solicitud, por favor haga clic en el siguiente botón para continuar con el proceso de actualización de su contraseña:</p>
	<div style="text-align:center;margin:32px 0;">
		<a href="${link}" style="background:#1976d2;color:#fff;padding:14px 32px;border-radius:6px;text-decoration:none;font-weight:bold;font-size:16px;display:inline-block;">Actualizar contraseña</a>
	</div>
	<#if linkExpiration??>
		<#assign minutos = linkExpiration?replace(",", "")?number>
		<#assign horas = (minutos / 60)?round>
		<p style="font-size:15px;color:#444;">Este enlace estará disponible por <b>${horas} hora<#if horas != 1>s</#if></b>.</p>
	</#if>
	<p style="color:#e67e22;font-size:14px;margin-top:32px;">Si usted no solicitó este cambio, puede ignorar este correo.</p>
	<hr style="margin:32px 0 16px 0;border:none;border-top:1px solid #eee;">
	<p style="font-size:15px;color:#555;">Saludos cordiales,<br>Equipo de Soporte</p>
</div>