import os
import logging
import pyodbc
import requests
import json
from dotenv import load_dotenv

# --- Keycloak helpers ---
class KeycloakToken:
    def __init__(self):
        self._token = None
        self._expires_at = 0

    def _fetch(self):
        url = f"{KC_URL}/realms/{KC_REALM_DESTINO}/protocol/openid-connect/token"
        data = {
            "client_id": KC_CLIENT_ID,
            "client_secret": KC_CLIENT_SECRET,
            "grant_type": "client_credentials",
        }
        resp = requests.post(url, data=data, headers={"Content-Type": "application/x-www-form-urlencoded"}, timeout=15, verify=False)
        resp.raise_for_status()
        payload = resp.json()
        self._token = payload["access_token"]
        expires_in = int(payload.get("expires_in", 300))
        import time
        self._expires_at = time.time() + expires_in - 30

    @property
    def value(self):
        import time
        if not self._token or time.time() >= self._expires_at:
            self._fetch()
        return self._token

def kc_headers(token):
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

def get_top_level_groups(token_mgr):
    """Obtiene solo los grupos raíz del realm."""
    url = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups"
    resp = requests.get(url, headers=kc_headers(token_mgr.value), timeout=30, verify=False)
    resp.raise_for_status()
    return resp.json()

def get_group_children(token_mgr, group_id):
    """Obtiene los hijos directos de un grupo por su ID."""
    url = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups/{group_id}/children"
    resp = requests.get(url, headers=kc_headers(token_mgr.value), timeout=30, verify=False)
    resp.raise_for_status()
    return resp.json()

def find_child_by_name(token_mgr, parent_id, name):
    """Busca un hijo directo por nombre bajo un padre. Si parent_id=None, busca en raíz."""
    if parent_id:
        children = get_group_children(token_mgr, parent_id)
    else:
        children = get_top_level_groups(token_mgr)
    for c in children:
        if c.get("name") == name:
            return c.get("id")
    return None

def create_group(token_mgr, group_data, parent_id=None):
    """Crea un grupo. Retorna el ID del grupo creado o None si ya existe (409)."""
    if parent_id:
        url = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups/{parent_id}/children"
    else:
        url = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups"
    resp = requests.post(url, headers=kc_headers(token_mgr.value), json=group_data, timeout=30, verify=False)
    if resp.status_code == 409:
        return None
    resp.raise_for_status()
    location = resp.headers.get("Location")
    if location:
        return location.rstrip("/").split("/")[-1]
    return None

# Configuración de logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("importacion_grupos.log", encoding="utf-8"),
    ],
)
log = logging.getLogger(__name__)

# Cargar variables de entorno
load_dotenv()

# Keycloak
KC_URL           = os.getenv("KC_URL",           "https://keycloackdev.saludteprotege.cl:8443")
KC_REALM_DESTINO = os.getenv("KC_REALM_DESTINO", "RNI-Dev")
KC_CLIENT_ID     = os.getenv("KC_CLIENT_ID",     "rni-apigateway")
KC_CLIENT_SECRET = os.getenv("KC_CLIENT_SECRET", "REDACTED_KC_APIGW_SECRET")

# SQL Server
DB_SERVER   = os.getenv("DB_SERVER",   "172.16.0.102,1431")
DB_DATABASE = os.getenv("DB_DATABASE", "Rayen")
DB_USER     = os.getenv("DB_USER",     "svillalobos")
DB_PASSWORD = os.getenv("DB_PASSWORD", "Rayen2024#")
DB_DRIVER   = os.getenv("DB_DRIVER",   "ODBC Driver 17 for SQL Server")

# Query para grupos y subgrupos
SQL_QUERY = '''
SELECT ID, NOD_ID, TIPO, RAZON_SOCIAL, DOMINIO
FROM NOD_NODO
WHERE ACTIVO = 1 AND ELIMINADO = 0 AND TIPO IN (3,4,5,6,7,8,9,10,11,12,13,14,15,18,19,21) AND DOMINIO <> ''
'''

def get_db_connection():
    conn_str = (
        f"DRIVER={{{DB_DRIVER}}};SERVER={DB_SERVER};DATABASE={DB_DATABASE};"
        f"UID={DB_USER};PWD={DB_PASSWORD}"
    )
    return pyodbc.connect(conn_str)

def fetch_groups():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute(SQL_QUERY)
    rows = cursor.fetchall()
    columns = [column[0] for column in cursor.description]
    data = [dict(zip(columns, row)) for row in rows]
    conn.close()
    return data

def build_group_tree(nodes):
    # Construye el árbol de grupos y subgrupos
    id_map = {n['ID']: n for n in nodes}
    tree = []
    for node in nodes:
        node['subGroups'] = []
    for node in nodes:
        if node['TIPO'] == 3:
            tree.append(node)
        else:
            parent = id_map.get(node['NOD_ID'])
            if parent:
                parent.setdefault('subGroups', []).append(node)
    return tree

def group_to_keycloak_format(node, parent_path=None):
    path = f"{parent_path}/{node['RAZON_SOCIAL']}" if parent_path else f"/{node['RAZON_SOCIAL']}"
    group = {
        "name": node['RAZON_SOCIAL'],
        "path": path,
        "attributes": {
            "organizationId": [str(node['ID'])],
            "dominio": [node['DOMINIO']]
        },
        "subGroups": []
    }
    # Agregar subgrupos hijos (recursivo)
    hijos = [group_to_keycloak_format(sg, path) for sg in node.get('subGroups', [])]
    group["subGroups"].extend(hijos)
    # Si es hoja (no tiene subGrupos hijos) y TIPO != 3, agregar subgrupos estándar
    if node['TIPO'] != 3 and not hijos:
        standard_subgroups = [
            {
                "name": "Administrador Local",
                "attributes": {
                    "module": ["user_management,reports"],
                    "security_level": ["2"],
                    "actions": ["get_vaccines,insert_patient,get_patient_by_id,get_patient_by_run,create_vaccination"]
                }
            },
            {
                "name": "Administrador Minsal",
                "attributes": {
                    "module": ["administration"],
                    "security_level": ["2"],
                    "actions": ["get_vaccines,insert_patient,get_patient_by_id,get_patient_by_run,create_vaccination"]
                }
            },
            {
                "name": "Registrador",
                "attributes": {
                    "module": ["reporting"],
                    "security_level": ["1"],
                    "actions": ["get_vaccines,get_patient,get_report"]
                }
            },
            {
                "name": "Vacunador",
                "attributes": {
                    "module": ["register"],
                    "security_level": ["1"],
                    "actions": ["get_vaccines,get_patient_by_id,get_patient_by_run,create_vaccination"]
                }
            },
            {
                "name": "Visualizador",
                "attributes": {
                    "module": ["view"],
                    "security_level": ["1"],
                    "actions": ["get_vaccines,get_patient_by_id,get_patient_by_run"]
                }
            }
        ]
        for s in standard_subgroups:
            group["subGroups"].append({
                "name": s["name"],
                "path": f"{path}/{s['name']}",
                "attributes": s["attributes"]
            })
    return group

def main():
    nodes = fetch_groups()
    tree = build_group_tree(nodes)
    keycloak_groups = [group_to_keycloak_format(g) for g in tree]
    with open("grupos_keycloak_generados.json", "w", encoding="utf-8") as f:
        json.dump(keycloak_groups, f, ensure_ascii=False, indent=2)
    log.info("Archivo grupos_keycloak_generados.json generado correctamente.")

    # --- Keycloak integration ---
    log.info("Iniciando integración con Keycloak...")
    token_mgr = KeycloakToken()
    contadores = {"creados": 0, "existentes": 0, "errores": 0}

    def create_groups_recursively(group, parent_id=None):
        # Buscar si ya existe como hijo directo del padre
        existing_id = find_child_by_name(token_mgr, parent_id, group["name"])
        if existing_id:
            log.info(f"Ya existe: {group['path']}")
            gid = existing_id
            contadores["existentes"] += 1
        else:
            group_data = {
                "name": group["name"],
                "attributes": group.get("attributes", {})
            }
            gid = create_group(token_mgr, group_data, parent_id)
            if gid:
                log.info(f"Creado: {group['path']}")
                contadores["creados"] += 1
            else:
                # 409 — ya existía, recuperar su ID
                gid = find_child_by_name(token_mgr, parent_id, group["name"])
                log.info(f"Ya existía (recuperado): {group['path']}")
                contadores["existentes"] += 1
        if not gid:
            log.error(f"No se pudo obtener ID para: {group['path']} (parent_id={parent_id}). Saltando subgrupos.")
            contadores["errores"] += 1
            return
        # Subgrupos
        for sg in group.get("subGroups", []):
            create_groups_recursively(sg, gid)

    for g in keycloak_groups:
        create_groups_recursively(g)

    total = contadores["creados"] + contadores["existentes"] + contadores["errores"]
    log.info("Integración con Keycloak finalizada.")
    print(f"\n{'='*50}")
    print(f"  RESUMEN DE INTEGRACIÓN CON KEYCLOAK")
    print(f"{'='*50}")
    print(f"  Grupos creados:      {contadores['creados']}")
    print(f"  Grupos ya existentes: {contadores['existentes']}")
    print(f"  Errores:             {contadores['errores']}")
    print(f"  Total procesados:    {total}")
    print(f"{'='*50}")

if __name__ == "__main__":
    main()
