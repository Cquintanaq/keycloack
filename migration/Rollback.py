import os
import time
import logging
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
# Cargar variables de entorno (.env)
# ---------------------------------------------------------------------------
load_dotenv()

KC_URL           = os.getenv("KC_URL",           "http://localhost:8080")                                    #
KC_REALM_ORIGEN  = os.getenv("KC_REALM_ORIGEN",  "master")                                                  # siempre master para el token admin
KC_REALM_DESTINO = os.getenv("KC_REALM_DESTINO", "RNI-DEV")                                                 # realm donde se eliminarán los usuarios
KC_CLIENT_ID     = os.getenv("KC_CLIENT_ID",     "admin-cli")                                               #
KC_ADMIN_USER    = os.getenv("KC_ADMIN_USER",     "admin")                                                  #
KC_ADMIN_PASS    = os.getenv("KC_ADMIN_PASS",     "admin")                                                  #

TOKEN_REFRESH_MARGIN = 60                                                                                    # segundos de margen antes de expirar el token

# ---------------------------------------------------------------------------
# RUTs piloto — misma lista que el importador
# Vaciar para eliminar TODOS los usuarios del realm (¡cuidado!)
# ---------------------------------------------------------------------------
RUTS_PILOTO = {
    "109860913", "132530939", "140709603",
    "92788695",  "134978341", "153565023",
    "159681548", "10863670k", "158977796",
    # usuario de prueba
    "admin2411",
}

# ---------------------------------------------------------------------------
# Manejo de token con auto-refresh
# ---------------------------------------------------------------------------
class KeycloakToken:
    def __init__(self):
        self._token: Optional[str] = None
        self._expires_at: float = 0.0

    def _fetch(self) -> None:
        url  = f"{KC_URL}/realms/{KC_REALM_ORIGEN}/protocol/openid-connect/token"
        data = {
            "client_id":  KC_CLIENT_ID,
            "username":   KC_ADMIN_USER,
            "password":   KC_ADMIN_PASS,
            "grant_type": "password",
        }
        resp = requests.post(url, data=data,
                             headers={"Content-Type": "application/x-www-form-urlencoded"},
                             timeout=15, verify=False)                                                       # verify=False por cert self-signed en DEV
        resp.raise_for_status()
        payload          = resp.json()
        self._token      = payload["access_token"]
        expires_in       = int(payload.get("expires_in", 300))
        self._expires_at = time.time() + expires_in - TOKEN_REFRESH_MARGIN
        log.info("Token obtenido. Expira en %d s.", expires_in)

    @property
    def value(self) -> str:
        if not self._token or time.time() >= self._expires_at:
            log.info("Refrescando token de Keycloak...")
            self._fetch()
        return self._token                                                                                    # type: ignore[return-value]

# ---------------------------------------------------------------------------
# Funciones de Keycloak
# ---------------------------------------------------------------------------
def _headers(token: str) -> dict:
    return {
        "Authorization": f"Bearer {token}",
        "Content-Type":  "application/json",
    }

def buscar_usuarios_por_rut(tk: KeycloakToken, rut: str) -> list[dict]:                                     # busca por atributo rut — un RUT puede tener varios logins
    """Busca por atributo custom 'rut' — retorna lista de usuarios KC que coinciden."""
    rut_norm = rut.strip().replace(".", "").lower()
    if "-" not in rut_norm:
        rut_norm = rut_norm[:-1] + "-" + rut_norm[-1]
    url  = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users"
    resp = requests.get(url, params={"q": f"rut:{rut_norm}", "max": 50},
                        headers=_headers(tk.value), timeout=15, verify=False)
    resp.raise_for_status()
    return resp.json()

def buscar_usuario_por_username(tk: KeycloakToken, username: str) -> Optional[str]:                         # retorna el ID interno de KC o None
    url  = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users"
    resp = requests.get(url, params={"username": username, "exact": "true"},
                        headers=_headers(tk.value), timeout=15, verify=False)
    resp.raise_for_status()
    usuarios = resp.json()
    return usuarios[0]["id"] if usuarios else None

def eliminar_usuario(tk: KeycloakToken, user_id: str, username: str) -> None:
    url  = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users/{user_id}"
    resp = requests.delete(url, headers=_headers(tk.value), timeout=15, verify=False)
    resp.raise_for_status()

def listar_todos_usuarios(tk: KeycloakToken) -> list[dict]:                                                  # útil cuando RUTS_PILOTO está vacío
    url    = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users"
    params = {"max": 1000}                                                                                   # ajustar si hay más de 1000
    resp   = requests.get(url, params=params, headers=_headers(tk.value), timeout=15, verify=False)
    resp.raise_for_status()
    return resp.json()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)                                      # silencia warnings SSL de DEV

    log.info("=== ROLLBACK — eliminando usuarios del realm: %s ===", KC_REALM_DESTINO)

    tk         = KeycloakToken()
    eliminados = 0
    no_encontrados = 0
    errores: list[str] = []

    if RUTS_PILOTO:
        # Modo selectivo — busca por atributo RUT (cubre cualquier username/login)
        ruts = sorted(RUTS_PILOTO)
        log.info("Modo selectivo: %d RUTs a eliminar.", len(ruts))

        for i, rut in enumerate(ruts, start=1):
            log.info("[%d/%d] Buscando RUT: %s", i, len(ruts), rut)
            try:
                # Busca por atributo rut — más robusto que buscar por username
                encontrados = buscar_usuarios_por_rut(tk, rut)

                if not encontrados:
                    # Fallback: intenta por username = RUT tal cual
                    user_id = buscar_usuario_por_username(tk, rut)
                    encontrados = [{"id": user_id, "username": rut}] if user_id else []

                if not encontrados:
                    log.warning("  → No encontrado en KC, omitido.")
                    no_encontrados += 1
                    continue

                for u in encontrados:                                                                        # puede haber más de uno si hubo duplicados
                    uid  = u["id"]
                    uname = u.get("username", uid)
                    eliminar_usuario(tk, uid, uname)
                    log.info("  → Eliminado: %s (id: %s)", uname, uid)
                    eliminados += 1

            except requests.exceptions.HTTPError as exc:
                msg = f"{rut}: HTTP {exc.response.status_code} — {exc.response.text[:200]}"
                log.error("  → Error HTTP: %s", msg)
                errores.append(msg)
            except Exception as exc:
                msg = f"{rut}: {exc}"
                log.error("  → Error inesperado: %s", msg)
                errores.append(msg)
    else:
        # Modo total — elimina TODOS los usuarios del realm (¡destructivo!)
        log.warning("⚠ RUTS_PILOTO vacío — se eliminarán TODOS los usuarios del realm.")
        todos = listar_todos_usuarios(tk)
        log.info("Usuarios encontrados en realm: %d", len(todos))

        for i, u in enumerate(todos, start=1):
            username = u.get("username", "—")
            user_id  = u["id"]
            log.info("[%d/%d] Eliminando: %s", i, len(todos), username)
            try:
                eliminar_usuario(tk, user_id, username)
                log.info("  → Eliminado OK.")
                eliminados += 1
            except requests.exceptions.HTTPError as exc:
                msg = f"{username}: HTTP {exc.response.status_code} — {exc.response.text[:200]}"
                log.error("  → Error HTTP: %s", msg)
                errores.append(msg)
            except Exception as exc:
                msg = f"{username}: {exc}"
                log.error("  → Error inesperado: %s", msg)
                errores.append(msg)

    # Resumen final
    log.info("=== Resumen rollback ===")
    log.info("  Eliminados       : %d", eliminados)
    log.info("  No encontrados   : %d", no_encontrados)
    log.info("  Errores          : %d", len(errores))
    if errores:
        log.warning("  Detalle errores:")
        for e in errores:
            log.warning("    • %s", e)
    log.info("  Log guardado en  : rollback_usuarios.log")


if __name__ == "__main__":
    main()