# Keycloak Pro con PostgreSQL externo

## Alcance

- Proyecto Compose: `keycloak-pro`.
- Servicio y contenedor: `keycloak-pro`.
- Imagen: `keycloak-rni-pro:26.7.3`, construida con el Dockerfile del proyecto.
- No declara PostgreSQL local ni depende de `keycloak_db`.
- No reemplaza `keycloak_service`, ni ocupa su puerto 443.
- Publicacion provisional: `127.0.0.1:8444` hacia HTTPS 8443 del contenedor.
  No queda accesible remotamente sin un proxy o un tunel expresamente configurado.

Esta configuracion es independiente: no combinarla con docker-compose.yml.
Ejecutar `docker compose up` sin seleccionar archivo utiliza el Compose habitual,
que declara PostgreSQL 15 local y los nombres antiguos.

## Destino externo informado

| Parametro | Valor informado |
| --- | --- |
| Host | `prerni-db-org01` |
| IP | `172.16.1.14` |
| Motor | PostgreSQL 18.6 |
| Cluster | `18/org` |
| Base | `keycloak_pre` |
| Usuario | `kc_db_user` |

**Pendiente de confirmar el ambiente:** el despliegue fue solicitado para PRO,
pero el host y la base informados sugieren PRE. No iniciar el servicio hasta
confirmar expresamente que esta es la base autorizada para el despliegue.

La plantilla utiliza el nombre DNS para verificar la identidad TLS. Comprobar
su resolucion y coincidencia con el certificado; si requiere FQDN, actualizar
`PG_HOST`. No sustituir por la IP a menos que el certificado la incluya como
IP SAN. El puerto 5432 es provisional: el identificador de cluster `18/org`
no determina el puerto de escucha. El cluster no es parte del nombre de la base.
Estos datos fueron proporcionados por el usuario, no verificados contra el servidor.

## Preparacion en el servidor

Los archivos creados en el workspace local deben transferirse o incorporarse al
repositorio del servidor antes de usarlos. No se transfieren automaticamente.

1. Situarse en la carpeta `~/Docker/Keycloak%20Pro` (el `%20` es literal).
2. Copiar `.env.pro.example` a `.env.pro`, completar sus valores directamente en
   el servidor y restringir sus permisos al personal autorizado.
3. Confirmar que `PG_HOST` es el DNS de PostgreSQL externo y coincide con el
   certificado del servidor. `PG_DATABASE` debe identificar la base autorizada.
4. Usar rutas absolutas para `PG_CA_FILE`, `KC_HTTPS_CERT_FILE` y
   `KC_HTTPS_KEY_FILE`. Deben existir, ser archivos y ser legibles para Keycloak
   dentro del contenedor. No ampliar indiscriminadamente permisos de la clave.
5. Si un secreto contiene `$`, usar comillas simples en el archivo de entorno.
   No imprimir el archivo, usar `source`, ni incluir claves en comandos o chats.
6. Confirmar que el puerto local 8444 y el nombre `keycloak-pro` estan libres.

Las variables exportadas en la sesion tienen prioridad sobre el archivo pasado
con `--env-file`; evitar valores heredados de otros ambientes.

## Validar y construir sin iniciar servicios

El usuario `operaciones` no tiene acceso directo al socket Docker. Un operador
autorizado puede ejecutar los siguientes comandos en su terminal; cualquier
contrasena de sudo se escribe directamente alli y nunca se comparte con el agente.
No cambiar permisos de docker.sock ni agregar usuarios al grupo docker sin la
aprobacion del administrador (ese acceso equivale practicamente a root).

```bash
cd "$HOME/Docker/Keycloak%20Pro"
sudo docker compose --env-file .env.pro -f docker-compose.pro.yml config --quiet
```

Solo si el comando anterior termina con codigo 0:

```bash
sudo docker compose --env-file .env.pro -f docker-compose.pro.yml build keycloak-pro
```

No ejecutar `config` sin `--quiet`, `config --environment`, ni `up` en esta fase.
La validacion de Compose no comprueba conectividad, credenciales, certificados,
estado de la base ni compatibilidad de los plugins.

Antes de construir, revisar tambien el Dockerfile real del servidor: no incluir
secretos como argumentos de build, instrucciones de imagen ni archivos copiados.

## Condiciones antes del inicio y del cambio a produccion

- Respaldo reciente de PostgreSQL con restauracion comprobada y autorizacion
  explicita para cambios de esquema.
- Version real del servidor PostgreSQL confirmada: Keycloak 26.7.3 declara
  soporte para PostgreSQL 18.x, que incluye 18.6; no sustituye pruebas funcionales.
- Ensayo sobre una copia aislada de la base y pruebas de plugins, temas y login.
- Plan de migracion y retorno coordinado con el Keycloak existente. Nunca dar
  por supuesto que una imagen antigua puede volver a usar un esquema actualizado.
- Plan de corte del proxy/DNS/puerto 443 y ventana de mantenimiento aprobados.
  No apuntar dos versiones incompatibles a la misma base productiva.

Como defensa adicional, el Compose utiliza estrategia de esquema `validate` e
`initialize-empty=false`: una base vacia o que requiera migracion debe causar un
fallo de inicio en lugar de una actualizacion automatica. Esto NO convierte a
Keycloak en solo lectura: al arrancar puede realizar escrituras operativas.
No se debe iniciar contra produccion como una simple prueba de conexion.
No cambiar la estrategia a `update` sin respaldo y aprobacion.

Fuente de compatibilidad versionada:
[Bases soportadas por Keycloak 26.7.3](https://github.com/keycloak/keycloak/blob/26.7.3/docs/guides/server/templates/databases.adoc)
