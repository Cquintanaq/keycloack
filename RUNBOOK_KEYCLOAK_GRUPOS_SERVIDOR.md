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
