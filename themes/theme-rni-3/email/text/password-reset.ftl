<#ftl output_format="plainText">
<#assign subject = "Restablecimiento de contraseña – Registro Nacional de Inmunización">
Hola,

Ha recibido este mensaje desde el sistema Registro Nacional de Inmunización.

Hemos recibido una solicitud para restablecer la contraseña de su cuenta. Si usted realizó esta solicitud, por favor copie y pegue el siguiente enlace en su navegador para continuar con el proceso de actualización de su contraseña:
${link}

<#if linkExpiration??>
<#assign minutos = linkExpiration?replace(",", "")?number>
<#assign horas = (minutos / 60)?round>
Este enlace estará disponible por ${horas} hora<#if horas != 1>s</#if>.
</#if>

Si usted no solicitó este cambio, puede ignorar este correo.

Saludos cordiales,
Equipo de Soporte