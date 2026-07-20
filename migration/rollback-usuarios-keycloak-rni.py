import os
import csv
import logging
import time
import requests
import urllib3
from typing import Optional
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Configuración de logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("rollback_usuarios.log", encoding="utf-8"),
    ],
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Cargar variables de entorno
# ---------------------------------------------------------------------------
load_dotenv()

KC_URL           = os.getenv("KC_URL",           "https://keyloackdesa.saludteprotege.cl:8443")
KC_REALM_DESTINO = os.getenv("KC_REALM_DESTINO", "RNI-Dev")
KC_CLIENT_ID     = os.getenv("KC_CLIENT_ID",     "rni-apigateway")
KC_CLIENT_SECRET = os.getenv("KC_CLIENT_SECRET", "REDACTED_KC_APIGW_SECRET")

TOKEN_REFRESH_MARGIN = 30

# Ruta al CSV generado por migracion-usuarios-keycloak-rni.py
CSV_PATH = os.getenv("CSV_PATH", "usuarios_nodos_log.csv")

# ---------------------------------------------------------------------------
# Manejo de token con auto-refresh
# ---------------------------------------------------------------------------
class KeycloakToken:
    def __init__(self):
        self._token: Optional[str] = None
        self._expires_at: float = 0.0

    def _fetch(self) -> None:
        url = f"{KC_URL}/realms/{KC_REALM_DESTINO}/protocol/openid-connect/token"
        data = {
            "client_id":     KC_CLIENT_ID,
            "client_secret": KC_CLIENT_SECRET,
            "grant_type":    "client_credentials",
        }
        resp = requests.post(url, data=data,
                             headers={"Content-Type": "application/x-www-form-urlencoded"},
                             timeout=15, verify=False)
        resp.raise_for_status()
        payload          = resp.json()
        self._token      = payload["access_token"]
        expires_in       = int(payload.get("expires_in", 300))
        self._expires_at = time.time() + expires_in - TOKEN_REFRESH_MARGIN
        log.info("Token obtenido. Expira en %d s.", expires_in)

    @property
    def value(self) -> str:
        if not self._token or time.time() >= self._expires_at:
            self._fetch()
        return self._token


# ---------------------------------------------------------------------------
# Funciones de Keycloak
# ---------------------------------------------------------------------------
def _headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def buscar_usuario(token_mgr: KeycloakToken, username: str) -> Optional[str]:
    """Busca un usuario por username exacto y retorna su ID, o None si no existe."""
    url    = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users"
    params = {"username": username, "exact": "true"}
    resp   = requests.get(url, params=params, headers=_headers(token_mgr.value), timeout=15, verify=False)
    resp.raise_for_status()
    users = resp.json()
    return users[0]["id"] if users else None


def eliminar_usuario(token_mgr: KeycloakToken, user_id: str) -> None:
    """Elimina un usuario por su ID."""
    url  = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users/{user_id}"
    resp = requests.delete(url, headers=_headers(token_mgr.value), timeout=15, verify=False)
    resp.raise_for_status()


# ---------------------------------------------------------------------------
# Leer usernames del CSV de migración
# ---------------------------------------------------------------------------
def leer_usernames_csv(csv_path: str) -> list[str]:
    """Lee la columna 'username' del CSV generado por la migración."""
    if not os.path.exists(csv_path):
        log.error("CSV no encontrado: %s", csv_path)
        return []
    usernames = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            username = row.get("username", "").strip()
            if username:
                usernames.append(username)
    log.info("Usernames leídos del CSV: %d", len(usernames))
    return usernames


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    log.info("=== Rollback de usuarios migrados → realm: %s ===", KC_REALM_DESTINO)
    log.info("CSV origen: %s", CSV_PATH)

    usernames = leer_usernames_csv(CSV_PATH)
    if not usernames:
        log.warning("No se encontraron usuarios en el CSV. Finalizando.")
        return

    log.info("Usuarios a eliminar: %d", len(usernames))
    log.info("Usernames: %s", ", ".join(usernames))

    token_mgr  = KeycloakToken()
    eliminados = 0
    no_encontrados = 0
    errores: list[str] = []

    for i, username in enumerate(usernames, start=1):
        log.info("[%d/%d] Buscando: %s", i, len(usernames), username)
        try:
            user_id = buscar_usuario(token_mgr, username)
            if not user_id:
                log.warning("  → No encontrado en KC, omitido.")
                no_encontrados += 1
                continue
            eliminar_usuario(token_mgr, user_id)
            log.info("  → Eliminado (id=%s)", user_id)
            eliminados += 1
        except requests.exceptions.HTTPError as exc:
            msg = f"{username}: HTTP {exc.response.status_code} — {exc.response.text[:300]}"
            log.error("  → Error HTTP: %s", msg)
            errores.append(msg)
        except Exception as exc:
            msg = f"{username}: {exc}"
            log.error("  → Error inesperado: %s", msg)
            errores.append(msg)

    log.info("=== Resumen Rollback ===")
    log.info("  Total en CSV      : %d", len(usernames))
    log.info("  Eliminados        : %d", eliminados)
    log.info("  No encontrados    : %d", no_encontrados)
    log.info("  Errores           : %d", len(errores))
    if errores:
        log.warning("  Detalle errores:")
        for e in errores:
            log.warning("    • %s", e)
    log.info("  Log guardado en   : rollback_usuarios.log")


if __name__ == "__main__":
    main()
