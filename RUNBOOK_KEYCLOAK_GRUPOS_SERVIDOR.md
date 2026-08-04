# Runbook: Keycloak + Importacion de Grupos (comandos usados hoy)

Este documento resume los pasos y comandos usados para:

1. Conectarse al servidor con el servicio activo.
2. Validar estado de Keycloak/PostgreSQL.
3. Validar configuracion base (.env, compose, export de grupos).
4. Ejecutar el procedimiento del repositorio para crear grupos en Keycloak.
5. Actualizar repo en GitHub desde VS Code y bajar cambios al servidor.

## 0) Contexto

- Servidor: `172.16.0.55`
- Ruta de proyecto en servidor: `/home/operaciones/Docker/keycloack`
- Contenedores esperados:
  - `keycloak_service`
  - `keycloak_db`
- Archivo de grupos del repo: `realm-export.json`
- Script de grupos del repo: `scripts/import_keycloak_groups.py`

## 1) Conectarse por SSH al servidor

```bash
ssh operaciones@172.16.0.55
```

## 2) Entrar al proyecto y validar que todo este arriba

```bash
cd /home/operaciones/Docker/keycloack
pwd
ls -la

docker compose ps
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
```

Salida esperada (resumen):

- `keycloak_service` en estado `Up`
- `keycloak_db` en estado `Up (healthy)`

## 3) Validar .env sin exponer secretos

Comando usado para revisar variables clave enmascarando passwords/secrets:

```bash
awk -F= 'NF>=1 {k=$1; v=substr($0,length($1)+2); if(k ~ /PASS|PASSWORD|SECRET/) v="***"; print k"="v}' .env
```

## 4) Validar fuente de grupos del repositorio

Comando usado para confirmar realm y cantidad de grupos del JSON:

```bash
python3 - <<'PY'
import json
with open('realm-export.json','r',encoding='utf-8') as f:
    d=json.load(f)
print('realm_json=', d.get('realm'))
print('groups_json=', len(d.get('groups',[])))
PY
```

Referencia observada hoy:

- `realm_json= RNI-QA`
- `groups_json= 31`

## 5) Importar grupos en Keycloak con el procedimiento del repo

### 5.0 Crear realm RNI-PRE por API (si no existe)

Este paso evita errores de UI como `Could not create realm unable to read contents from stream`.

```bash
cd /home/operaciones/Docker/keycloack
source .env

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

payload=urllib.parse.urlencode({
  'client_id':'admin-cli',
  'grant_type':'password',
  'username':admin,
  'password':pwd
}).encode()

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
```

### 5.1 Nota importante sobre SSL

En este servidor, Keycloak esta expuesto con HTTPS interno y certificado no confiable para el contenedor Python temporal.

- `KEYCLOAK_URL=http://keycloak:8080` fallo por conexion rechazada.
- `KEYCLOAK_URL=https://keycloak:8443` fallo por verificacion SSL.

Por eso se uso el mismo script del repo con un wrapper temporal para desactivar verificacion SSL en esa corrida.

### 5.2 Comando ejecutado (exitoso)

```bash
cd /home/operaciones/Docker/keycloack
set -a; . ./.env; set +a

docker run --rm \
  --network keycloack_keycloak_network \
  -e KEYCLOAK_URL=https://keycloak:8443 \
  -e KEYCLOAK_ADMIN="$KEYCLOAK_ADMIN_USER" \
  -e KEYCLOAK_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD" \
  -e KEYCLOAK_REALM=RNI-QA \
  -v "$PWD":/work \
  -w /work \
  python:3.12-alpine \
  sh -lc "python - <<'PY'
import ssl, runpy, sys
ssl._create_default_https_context = ssl._create_unverified_context
sys.argv = ['scripts/import_keycloak_groups.py', '--file', 'realm-export.json', '--realm', 'RNI-QA']
runpy.run_path('scripts/import_keycloak_groups.py', run_name='__main__')
PY"
```

### 5.3 Comando recomendado para RNI-PRE en el servidor

```bash
cd /home/operaciones/Docker/keycloack
source .env

export KEYCLOAK_URL="https://keycloak-pre.saludteprotege.cl"
export KEYCLOAK_ADMIN="$KEYCLOAK_ADMIN_USER"
export KEYCLOAK_ADMIN_PASSWORD="$KEYCLOAK_ADMIN_PASSWORD"
export KEYCLOAK_REALM="RNI-PRE"

python - <<'PY'
import ssl, runpy, sys
ssl._create_default_https_context = ssl._create_unverified_context
sys.argv = ['scripts/import_keycloak_groups.py', '--file', 'realm-export.json', '--realm', 'RNI-PRE']
runpy.run_path('scripts/import_keycloak_groups.py', run_name='__main__')
PY
```

### 5.4 Validar cantidad de grupos creados en RNI-PRE

```bash
cd /home/operaciones/Docker/keycloack
source .env

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
```

Resultado observado hoy:

- multiples lineas `"[OK] Grupo creado"`
- multiples lineas `"[OK] Subgrupo creado"`

## 6) Validar estado git del servidor antes de pull

Comandos usados:

```bash
cd /home/operaciones/Docker/keycloack
git status --short --branch
git remote -v
```

## 7) Actualizar GitHub desde VS Code local

En tu maquina local (VS Code), para subir cambios del repo:

```powershell
cd C:\Users\cquintana\Videos\Docker\keycloack
git status
git add .
git commit -m "Actualizar runbook y ajustes de despliegue/importacion de grupos"
git push origin main
```

## 8) Bajar cambios al servidor

En el servidor:

```bash
cd /home/operaciones/Docker/keycloack
git pull origin main
```

Si hay cambios locales en servidor y quieres protegerlos antes del pull:

```bash
git stash push -m update-local
git pull origin main
git stash pop
```

## 9) Repetir solo importacion de grupos (sin tocar BD)

No necesitas borrar base de datos para recrear grupos del repo.

Ejecuta nuevamente la seccion 5.2 cuando necesites sincronizar grupos desde `realm-export.json`.

## 10) Comandos de troubleshooting usados hoy

### Ver contenedores rapidos

```bash
docker compose ps
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
```

### Si falla por HTTP refused

- Revisa si Keycloak solo escucha HTTPS interno y usa:
- `KEYCLOAK_URL=https://keycloak:8443`

### Si falla por SSL verify failed

- Usa wrapper temporal de Python (seccion 5.2) para cert interno/self-signed.

---

## Resumen ejecutivo

- El servicio de Keycloak estaba activo.
- El procedimiento de grupos del repositorio se ejecuto y creo subestructura de grupos en `RNI-QA`.
- No fue necesario eliminar la base de datos para este objetivo.
- Queda recomendado mantener este runbook como referencia operativa para futuras reimportaciones.

---

## 11) Si quieres reconstruir desde cero para usar scripts de migration

Objetivo de esta seccion: limpiar el estado actual de Keycloak y volver a poblar con:

- `migration/listar_grupos_keycloak.py` (solo lectura/validacion)
- `migration/migracion-grupos-keycloak-rni.py` (crea grupos desde SQL)
- `migration/migracion-usuarios-keycloak-rni.py` (crea usuarios y asigna grupos)

### 11.1 Que borrar: base de datos o imagen Docker

Recomendacion:

1. Para iniciar limpio de datos, borra datos de PostgreSQL (volumen/carpeta persistente).
2. No necesitas borrar la imagen Docker para limpiar datos.
3. Solo borra/reconstruye imagen si cambiaste Dockerfile, plugins o version de Keycloak.

En este proyecto, la persistencia de PostgreSQL esta en `data/postgres_data/`.

### 11.2 Respaldo obligatorio antes de limpiar

```bash
cd /home/operaciones/Docker/keycloack

# Backup logico de DB (si el contenedor existe)
docker exec -t keycloak_db pg_dump -U "$DB_USER" "$DB_NAME" > respaldo/pre_reset_$(date +%F_%H%M).sql

# Backup de carpeta persistente
tar -czf respaldo/postgres_data_pre_reset_$(date +%F_%H%M).tgz data/postgres_data
```

### 11.3 Limpieza de datos (reinicio real)

```bash
cd /home/operaciones/Docker/keycloack
docker compose down

# elimina datos persistentes de PostgreSQL
rm -rf data/postgres_data/*

# opcional: reconstruir imagen si cambiaste Dockerfile/plugins
docker compose build --no-cache

# levantar limpio
docker compose up -d
docker compose ps
```

### 11.4 Preparar variables para scripts migration

Los scripts de `migration` usan su propio `.env` (en carpeta `migration`) o variables de entorno.

```bash
cd /home/operaciones/Docker/keycloack
cp migration/.env.example migration/.env
vi migration/.env
```

Variables clave a completar en `migration/.env`:

- `KC_URL`
- `KC_REALM_DESTINO`
- `KC_CLIENT_ID`
- `KC_CLIENT_SECRET`
- `DB_SERVER`
- `DB_DATABASE`
- `DB_USER`
- `DB_PASSWORD`

### 11.5 Instalar dependencias para migration

```bash
cd /home/operaciones/Docker/keycloack
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install requests python-dotenv pyodbc
```

Nota: `pyodbc` requiere driver ODBC en servidor. Si falta, instala Microsoft ODBC Driver 17/18 para SQL Server.

### 11.6 Ejecutar migration (orden recomendado)

```bash
cd /home/operaciones/Docker/keycloack
. .venv/bin/activate

# 1) crear grupos desde SQL
python migration/migracion-grupos-keycloak-rni.py

# 2) listar grupos para validar jerarquia creada
python migration/listar_grupos_keycloak.py

# 3) crear usuarios y asignarlos a grupos
python migration/migracion-usuarios-keycloak-rni.py
```

### 11.7 Verificacion web final

1. Abrir `https://keycloak-pre.saludteprotege.cl`
2. Ingresar a Admin Console
3. Cambiar a realm objetivo
4. Revisar `Groups` y `Users`

### 11.8 Diferencia clave con `scripts/import_keycloak_groups.py`

`scripts/import_keycloak_groups.py`:

- Usa `realm-export.json` como fuente.
- Crea/actualiza solo grupos del JSON.

`migration/migracion-grupos-keycloak-rni.py` + `migration/migracion-usuarios-keycloak-rni.py`:

- Usan SQL Server como fuente.
- Construyen grupos en base a nodos/roles de BD.
- Crean usuarios y asignaciones de grupo.
