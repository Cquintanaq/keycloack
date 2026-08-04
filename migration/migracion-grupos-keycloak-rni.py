import os
import logging
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
        if resp.status_code >= 400:
            log.error(f"No se pudo obtener token de Keycloak ({resp.status_code}): {resp.text}")
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

def raise_for_status_verbose(resp):
    """Como resp.raise_for_status() pero logueando el body de error de Keycloak (útil para 403/404)."""
    if resp.status_code >= 400:
        log.error(f"Keycloak respondió {resp.status_code} en {resp.request.method} {resp.url}: {resp.text}")
    resp.raise_for_status()

def get_top_level_groups(token_mgr):
    """Obtiene solo los grupos raíz del realm."""
    url = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups"
    resp = requests.get(url, headers=kc_headers(token_mgr.value), timeout=30, verify=False)
    raise_for_status_verbose(resp)
    return resp.json()

def get_group_children(token_mgr, group_id):
    """Obtiene los hijos directos de un grupo por su ID."""
    url = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups/{group_id}/children"
    resp = requests.get(url, headers=kc_headers(token_mgr.value), timeout=30, verify=False)
    raise_for_status_verbose(resp)
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
    raise_for_status_verbose(resp)
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
KC_URL           = os.getenv("KC_URL",           "http://localhost:8080/")
KC_REALM_DESTINO = os.getenv("KC_REALM_DESTINO", "RNI")
KC_CLIENT_ID     = os.getenv("KC_CLIENT_ID",     "rni-apigateway")
KC_CLIENT_SECRET = os.getenv("KC_CLIENT_SECRET", "REDACTED_KC_APIGW_SECRET")

# Archivo fuente: solo los grupos del ambiente demo (extraído de realm-export.json, referencia, nunca se modifica)
# y archivo de salida generado por este script
SCRIPT_DIR         = os.path.dirname(os.path.abspath(__file__))
GROUPS_SOURCE_FILE = os.getenv("GROUPS_SOURCE_FILE", os.path.join(SCRIPT_DIR, "grupos-ambiente-demo.json"))
GROUPS_OUTPUT_FILE = os.getenv("GROUPS_OUTPUT_FILE", os.path.join(SCRIPT_DIR, "grupos_keycloak_generados.json"))

def load_source_groups(path):
    """Carga el árbol de grupos desde el archivo dedicado (solo grupos, sin el resto del realm)."""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("groups", [])

def clean_group(node):
    """Recorre un nodo del export y produce una copia mínima (name/path/attributes/subGroups),
    descartando campos internos de Keycloak (id, parentId, realmRoles, clientRoles) que no
    deben reutilizarse al crear los grupos de nuevo."""
    return {
        "name": node["name"],
        "path": node["path"],
        "attributes": node.get("attributes", {}),
        "subGroups": [clean_group(sg) for sg in node.get("subGroups", [])],
    }

def main():
    source_groups = load_source_groups(GROUPS_SOURCE_FILE)
    keycloak_groups = [clean_group(g) for g in source_groups]
    with open(GROUPS_OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(keycloak_groups, f, ensure_ascii=False, indent=2)
    log.info(f"Archivo {os.path.basename(GROUPS_OUTPUT_FILE)} generado correctamente a partir de {os.path.basename(GROUPS_SOURCE_FILE)}.")

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
