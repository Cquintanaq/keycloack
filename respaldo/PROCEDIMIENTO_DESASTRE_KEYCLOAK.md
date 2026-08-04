# Procedimiento de Desastre: Keycloak RNI

Este documento define el procedimiento completo para recuperar e implementar Keycloak desde cero en caso de desastre.

Alcance:
- Recuperacion operativa del servicio Docker.
- Respaldo previo de base de datos y datos persistentes.
- Limpieza total de datos PostgreSQL.
- Reconstruccion de imagen Docker sin cache.
- Repoblado de grupos y usuarios.
- Verificacion final tecnica y funcional.

## 1. Datos del entorno

- Servidor: 172.16.0.55
- Ruta proyecto: /home/operaciones/Docker/keycloack
- Servicios esperados:
  - keycloak_service
  - keycloak_db
- Puerto HTTPS publicado: 443

## 2. Prerrequisitos

- Acceso SSH al servidor.
- Permisos para ejecutar Docker (root o usuario con grupo docker).
- Archivo .env valido en /home/operaciones/Docker/keycloack.
- Si se usara migration desde SQL:
  - Python 3
  - requests, python-dotenv, pyodbc
  - Driver ODBC SQL Server instalado
  - Conectividad al SQL origen

## 3. Conexion al servidor

Comando:

ssh operaciones@172.16.0.55

Validar contexto:

whoami
hostname
cd /home/operaciones/Docker/keycloack
pwd

## 4. Verificacion inicial del stack

Comandos:

docker compose ps
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

## 5. Respaldo obligatorio antes de limpiar

Importante: ejecutar en /home/operaciones/Docker/keycloack

set -a; . ./.env; set +a
TS=$(date +%F_%H%M%S)
mkdir -p respaldo

# Backup logico PostgreSQL
docker exec -t keycloak_db pg_dump -U "$DB_USER" "$DB_NAME" > "respaldo/pre_reset_${TS}.sql"

# Backup carpeta de datos (tolerante a WAL activo)
tar --warning=no-file-changed -czf "respaldo/postgres_data_pre_reset_${TS}.tgz" data/postgres_data || true

## 6. Limpieza total de datos + rebuild sin cache

Importante: esta etapa elimina datos persistentes de Keycloak/PostgreSQL.

Comandos:

docker compose down
rm -rf data/postgres_data/*
docker compose build --no-cache
docker compose up -d
docker compose ps

## 7. Verificacion tecnica post-reinicio

Comandos:

curl -k -s -o /dev/null -w "HTTP %{http_code}\n" https://localhost/realms/master/.well-known/openid-configuration

Resultado esperado:
- HTTP 200

## 8. Opciones de repoblado de informacion

### Opcion A: Repoblar grupos desde export del repositorio (JSON)

Fuente:
- realm-export.json
- scripts/import_keycloak_groups.py

Paso previo recomendado: crear realm RNI-PRE por API si no existe.

set -a; . ./.env; set +a

export KEYCLOAK_URL="https://keycloak-pre.saludteprotege.cl"
export KEYCLOAK_ADMIN="$KEYCLOAK_ADMIN_USER"
export KEYCLOAK_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD"

python - <<'PY'
import ssl, urllib.request, urllib.parse, json, os
ssl._create_default_https_context = ssl._create_unverified_context
base=os.environ['KEYCLOAK_URL'].rstrip('/')
admin=os.environ['KEYCLOAK_ADMIN']
pwd=os.environ['KEYCLOAK_ADMIN_PASSWORD']
realm='RNI-PRE'
payload=urllib.parse.urlencode({'client_id':'admin-cli','grant_type':'password','username':admin,'password':pwd}).encode()
req=urllib.request.Request(f'{base}/realms/master/protocol/openid-connect/token', data=payload, method='POST')
req.add_header('Content-Type','application/x-www-form-urlencoded')
with urllib.request.urlopen(req) as r:
  tok=json.loads(r.read().decode())['access_token']
req2=urllib.request.Request(f'{base}/admin/realms/{urllib.parse.quote(realm)}', method='GET')
req2.add_header('Authorization', f'Bearer {tok}')
try:
  with urllib.request.urlopen(req2) as r:
    print('realm_exists', realm, r.status)
except urllib.error.HTTPError as e:
  if e.code == 404:
    body=json.dumps({'realm':realm,'enabled':True}).encode()
    req3=urllib.request.Request(f'{base}/admin/realms', data=body, method='POST')
    req3.add_header('Authorization', f'Bearer {tok}')
    req3.add_header('Content-Type','application/json')
    with urllib.request.urlopen(req3) as r:
      print('realm_created', realm, r.status)
  else:
    raise
PY

Comando recomendado para entorno con certificado interno:

set -a; . ./.env; set +a

docker run --rm \
  --network keycloack_keycloak_network \
  -e KEYCLOAK_URL=https://keycloak:8443 \
  -e KEYCLOAK_ADMIN="$KEYCLOAK_ADMIN_USER" \
  -e KEYCLOAK_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD" \
  -e KEYCLOAK_REALM=RNI-PRE \
  -v "$PWD":/work \
  -w /work \
  python:3.12-alpine \
  sh -lc "python - <<'PY'
import ssl, runpy, sys
ssl._create_default_https_context = ssl._create_unverified_context
sys.argv = ['scripts/import_keycloak_groups.py', '--file', 'realm-export.json', '--realm', 'RNI-PRE']
runpy.run_path('scripts/import_keycloak_groups.py', run_name='__main__')
PY"

Validacion posterior de grupos creados:

set -a; . ./.env; set +a
export KEYCLOAK_URL="https://keycloak-pre.saludteprotege.cl"
export KEYCLOAK_ADMIN="$KEYCLOAK_ADMIN_USER"
export KEYCLOAK_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD"

python - <<'PY'
import ssl, urllib.request, urllib.parse, json, os
ssl._create_default_https_context = ssl._create_unverified_context
base=os.environ['KEYCLOAK_URL'].rstrip('/')
admin=os.environ['KEYCLOAK_ADMIN']
pwd=os.environ['KEYCLOAK_ADMIN_PASSWORD']
realm='RNI-PRE'
payload=urllib.parse.urlencode({'client_id':'admin-cli','grant_type':'password','username':admin,'password':pwd}).encode()
req=urllib.request.Request(f'{base}/realms/master/protocol/openid-connect/token', data=payload, method='POST')
req.add_header('Content-Type','application/x-www-form-urlencoded')
with urllib.request.urlopen(req) as r:
  tok=json.loads(r.read().decode())['access_token']
q=urllib.parse.urlencode({'first':0,'max':2000})
req2=urllib.request.Request(f'{base}/admin/realms/{urllib.parse.quote(realm)}/groups?{q}', method='GET')
req2.add_header('Authorization', f'Bearer {tok}')
req2.add_header('Accept','application/json')
with urllib.request.urlopen(req2) as r:
  groups=json.loads(r.read().decode())
print('realm', realm)
print('top_level_groups', len(groups))
print('sample', ', '.join(g.get('name','') for g in groups[:10]))
PY

### Opcion B: Repoblar usando migration desde SQL (grupos + usuarios)

Scripts:
- migration/migracion-grupos-keycloak-rni.py
- migration/listar_grupos_keycloak.py
- migration/migracion-usuarios-keycloak-rni.py

Preparacion:

cp migration/.env.example migration/.env
# editar migration/.env con valores reales

python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install requests python-dotenv pyodbc

Orden de ejecucion:

python migration/migracion-grupos-keycloak-rni.py
python migration/listar_grupos_keycloak.py
python migration/migracion-usuarios-keycloak-rni.py

Notas de seguridad:
- migracion-usuarios-keycloak-rni.py agrega un usuario de prueba hardcodeado.
- Revisar y quitar ese bloque antes de corrida productiva.
- Validar realm destino y credenciales antes de ejecutar.

## 9. Verificacion funcional web

1. Abrir: https://keycloak-pre.saludteprotege.cl
2. Iniciar sesion en Admin Console.
3. Seleccionar realm objetivo.
4. Revisar:
- Groups (jerarquia esperada)
- Users (si se ejecuto migracion de usuarios)

## 10. Validacion de recuperacion completa

Checklist:
- Docker daemon activo.
- keycloak_db en healthy.
- keycloak_service en Up.
- Endpoint OIDC responde HTTP 200.
- Grupos creados en realm esperado.
- Usuarios creados (si aplica).

## 11. Rollback de emergencia

Si la nueva corrida falla:

1. Detener stack:

docker compose down

2. Restaurar carpeta de datos:

tar -xzf respaldo/postgres_data_pre_reset_<TIMESTAMP>.tgz

3. Levantar stack:

docker compose up -d

Opcional: restaurar dump SQL en BD limpia segun necesidad operacional.

## 12. Registro de ejecucion recomendada

Registrar en cada intervencion:
- Fecha/hora
- Responsable
- Commit desplegado
- Nombre de backups generados
- Resultado de verificacion tecnica (HTTP 200)
- Resultado de verificacion funcional (Groups/Users)
