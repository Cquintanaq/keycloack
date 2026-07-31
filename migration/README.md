# Migration de Keycloak

Esta carpeta contiene utilitarios para migrar grupos y usuarios hacia Keycloak.

## Resumen de scripts

- migracion-grupos-keycloak-rni.py
  - Lee estructura de organizaciones desde SQL Server y crea/arbola grupos en Keycloak.
  - Requiere conectividad a SQL Server y pyodbc.

- migracion-usuarios-keycloak-rni.py
  - Migra usuarios desde SQL Server, crea credenciales hash y asigna grupos por nodo/rol.
  - Genera usuarios_nodos_log.csv para rollback.

- rollback-usuarios-keycloak-rni.py
  - Rollback seguro por lista de usernames desde usuarios_nodos_log.csv.

- Rollback.py
  - Rollback alternativo por RUT.
  - Riesgo: si RUTS_PILOTO queda vacio, elimina todos los usuarios del realm.

- listar_grupos_keycloak.py
  - Lista grupos/subgrupos del realm para validacion.

## Recomendacion para recrear grupos (flujo sugerido)

Si tu objetivo principal es reconstruir grupos otra vez en Keycloak, usa primero el importador del repo:

1. Definir variables de entorno:

```powershell
$env:KEYCLOAK_URL="https://<host-keycloak>"
$env:KEYCLOAK_ADMIN="<admin>"
$env:KEYCLOAK_ADMIN_PASSWORD="<password>"
$env:KEYCLOAK_REALM="RNI-QA"
```

2. Ejecutar import desde el export del realm:

```powershell
python scripts/import_keycloak_groups.py --file realm-export.json --realm RNI-QA
```

3. Verificar grupos:

```powershell
python migration/listar_grupos_keycloak.py
```

## Cuándo usar migracion-grupos-keycloak-rni.py

Usalo solo si necesitas reconstruir grupos desde SQL Server (NOD_NODO), no desde realm-export.json.

## Dependencias Python

```powershell
pip install -r migration/requirements.txt
```

## Advertencias importantes

- No ejecutar Rollback.py en productivo sin revisar RUTS_PILOTO.
- Validar realm destino antes de correr cualquier script.
- Evitar secretos reales hardcodeados en codigo; usar solo .env local no versionado.
