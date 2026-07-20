import base64
import os
import re
import json
import time
import logging
import pyodbc
import requests
import urllib3
from dataclasses import dataclass, field
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
        logging.FileHandler("importacion_usuarios.log", encoding="utf-8"),
    ],
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Cargar variables de entorno (.env o variables del sistema)
# ---------------------------------------------------------------------------
load_dotenv()

# --- Keycloak ---
KC_URL           = os.getenv("KC_URL", "")                                                                   #
KC_REALM_ORIGEN  = os.getenv("KC_REALM_ORIGEN", "")                                                          # realm donde está admin-cli
KC_CLIENT_ID     = os.getenv("KC_CLIENT_ID", "")                                                             # cliente con el cual conectar con keycloak
KC_CLIENT_SECRET = os.getenv("KC_CLIENT_SECRET", "")                                                         # secret del cliente
KC_ADMIN_USER    = os.getenv("KC_ADMIN_USER", "")                                                            # usuario que creará los usuarios
KC_ADMIN_PASS    = os.getenv("KC_ADMIN_PASS", "")                                                            #

KC_REALM_DESTINO = os.getenv("KC_REALM_DESTINO", "")                                                         # <-- realm objetivo

# --- SQL Server origen ---
DB_SERVER   = os.getenv("DB_SERVER", "")                                                                     # IP,puerto del SQL Server
DB_DATABASE = os.getenv("DB_DATABASE", "")                                                                   #
DB_USER     = os.getenv("DB_USER", "")                                                                       #
DB_PASSWORD = os.getenv("DB_PASSWORD", "")                                                                   #
DB_DRIVER   = os.getenv("DB_DRIVER", "ODBC Driver 17 for SQL Server")                                        #

TOKEN_REFRESH_MARGIN = 30                                                                                    # segundos de margen antes de expirar el token

# ---------------------------------------------------------------------------
# Query SQL
# FIX: sin "USE RPBC" — pyodbc ya conecta a esa BD en conn_str
# FIX: APELLIDO_PATERNO corregido (el original tenía APELLIDO_MATERNO duplicado)
# FIX: alias en minúsculas para mapeo seguro en leer_usuarios_db()
# FIX: ROW_NUMBER() para deduplicar por RUT — un funcionario puede tener
#      múltiples logins/perfiles activos; nos quedamos con el más reciente (ID mayor)
# FIX: JOINs a NOD_PADRE y ENUM_TIPO_NODO para razon_social_padre y tipo_nodo
# ---------------------------------------------------------------------------
SQL_QUERY = """
                WITH dedup AS (
            SELECT
                FNP.NOMBRES                    AS nombres,
                FNP.APELLIDO_PATERNO           AS apellido_paterno,
                FNP.APELLIDO_MATERNO           AS apellido_materno,
                PFU.EMAIL                      AS email,
                FNP.ACTIVO                     AS activo,
                FNP.RUT                        AS rut,
                LGN.PASSWORD_HASH              AS password_hash,
                LGN.SALT                       AS salt,
                NOD.ID                         AS nodo_id,
                NOD.NOD_ID                     AS nodo_padre_id,
                NOD_PADRE.RAZON_SOCIAL         AS razon_social_padre,
                NOD.RAZON_SOCIAL               AS razon_social,
                NOD.TIPO                       AS nodo_tipo,
                ENUM_T.DESCRIPCION             AS tipo_descripcion,
                LGN.LOGIN                      AS login,
                LGN.DOMINIO                    AS dominio,
                LGN.ELIMINADO                  AS eliminado,
                LGN.ID                         AS lgn_id,
				ROL.NOMBRE					   AS rol,
				ROL.ID						   AS rol_id,
                ROW_NUMBER() OVER (
                    PARTITION BY FNP.RUT, NOD.DOMINIO
                    ORDER BY LGN.ID DESC
                ) AS rn_dominio,
                ROW_NUMBER() OVER (
                    PARTITION BY FNP.RUT
                    ORDER BY LGN.ID DESC
                ) AS rn_global
            FROM FNP_FUNCIONARIO_PRESTADOR FNP
            INNER JOIN LGN_LOGIN        LGN       ON FNP.ID        = LGN.FNP_ID
            INNER JOIN PFU_PERFIL       PFU       ON LGN.ID        = PFU.LGN_ID
			INNER JOIN RL_PFUROL        PFUROL    ON PFU.ID        = PFUROL.ID
			INNER JOIN ROL_ROL			ROL		  ON PFUROL.ROL_ID = ROL.ID
            INNER JOIN NOD_NODO         NOD       ON LGN.DOMINIO   = NOD.DOMINIO
            INNER JOIN ENUM_TIPO_NODO   ENUM_T    ON NOD.TIPO      = ENUM_T.ID
            INNER JOIN NOD_NODO         NOD_PADRE ON NOD.NOD_ID    = NOD_PADRE.ID
            WHERE
                FNP.ACTIVO    = 1
                AND LGN.ELIMINADO = 0
				AND ROL.ID IN (0,5,6,8,9,11,12,13,14,15,16)
                AND NOD.TIPO IN (4,5,6,7,8,9,10,11,12,13,14,15,18,19,21)
                AND NOD.DOMINIO <> ''
        )
        SELECT 
            nombres, apellido_paterno, apellido_materno,
            email, activo, rut, password_hash, salt,
            nodo_id, nodo_padre_id, razon_social_padre, razon_social,
            nodo_tipo, tipo_descripcion,
            login, dominio, eliminado,
            lgn_id,rol ,rol_id, rn_global
        FROM dedup
        WHERE rn_dominio = 1
        ORDER BY rut, rn_global
"""

# ---------------------------------------------------------------------------
# RUTs piloto — filtro aplicado en Python después del SELECT
# Para importar todos los usuarios deja el set vacío: RUTS_PILOTO = set()
# ---------------------------------------------------------------------------
RUTS_PILOTO = {

}

# ---------------------------------------------------------------------------
# Helpers de normalización
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Mapeo ROL_ID → nombre de grupo en Keycloak
# ---------------------------------------------------------------------------
ROL_A_GRUPO: dict[int, str] = {
    0:  "Administrador Local",
    5:  "Visualizador",
    6:  "Administrador Minsal",
    8:  "Vacunador",
    9:  "Registrador",
    11: "Registrador",
    12: "Vacunador",
    13: "Vacunador",
    14: "Registrador",
    15: "Registrador",
    16: "Vacunador",
}

def normalizar_rut(rut: Optional[str]) -> Optional[str]:                                                     # elimina puntos y asegura formato XXXXXXXX-D
    if not rut:
        return None
    rut = rut.strip().replace(".", "").lower()
    if len(rut) >= 2 and "-" not in rut:
        rut = rut[:-1] + "-" + rut[-1]
    return rut

def limpiar_nombre(valor: Optional[str]) -> str:                                                             # elimina caracteres inválidos para KC (*, [], paréntesis, etc.)
    if not valor:
        return ""
    texto = str(valor)
    texto = re.sub(r"[\[\(].*?[\]\)]", "", texto)                                                            # elimina "[CGU]", "(No usar)", etc.
    texto = re.sub(r"\*[^*]*\*", "", texto)                                                                  # elimina "*No Tocar*", "****texto****"
    texto = re.sub(r"[*#@!$%^&+=<>{}]", "", texto)                                                          # elimina caracteres sueltos que KC rechaza
    return " ".join(texto.split()).title()                                                                    # normaliza espacios y title case

# ---------------------------------------------------------------------------
# Modelo de usuario — mapea los campos de BD al payload de Keycloak
# ---------------------------------------------------------------------------
@dataclass
class UsuarioKC:
    username:      str
    email:         str
    firstName:     str
    lastName:      str
    enabled:       bool
    rut:           Optional[str] = None
    password_hash: Optional[str] = None                                                                      # SHA-1 hex de la BD — no compatible con KC nativo
    salt:          Optional[str] = None                                                                       # salt string Base64 de LGN_LOGIN (ej: qPnVXO0=)
    attributes:    dict = field(default_factory=dict)
    nodos:         list = field(default_factory=list)                                                         # lista de {nodo_id, razon_social, razon_social_padre, dominio, tipo_descripcion}

    def _clave_temporal(self) -> str:                                                                        # clave temporal = RUT sin guión (ej: 109860913)
        if self.rut:
            return self.rut.replace("-", "").replace(".", "")                                                # ej: 10986091-3 → 109860913
        return self.username                                                                                  # fallback: el propio username

    def to_keycloak_payload(self) -> dict:
        attrs = dict(self.attributes)
        if self.rut:
            attrs["rut"] = [self.rut]                                                                        # Keycloak espera lista de strings
        payload = {
            "username":   self.username,                                                                     # el username es el RUT — primer login con RUT
            "email":      self.email if self.email else f"{self.username}@pendiente.rni.cl",                 # email de BD o placeholder si no tiene
            "firstName":  self.firstName,
            "lastName":   self.lastName,
            "enabled":    self.enabled,
            "attributes": attrs,
            # Hash SHA-1 migrado directamente — custom-sha1 SPI verifica en KC
            # En el primer login exitoso KC rehashea automáticamente a pbkdf2-sha256
            "credentials": [
                {
                    "type":           "password",
                    "secretData":     json.dumps({"value": self.password_hash, "salt": base64.b64encode((self.salt or "").encode("utf-8")).decode("utf-8")}),
                    "credentialData": json.dumps({"hashIterations": 0, "algorithm": "dotnet-sha1"}),
                    "temporary":      False,
                }
            ],
            "requiredActions": ["UPDATE_PROFILE", "CONFIGURE_TOTP", "username-to-email-updater"],              # 1) completar perfil → 2) configurar OTP → 3) cambiar username a email
        }
        return payload

# ---------------------------------------------------------------------------
# Manejo de token con auto-refresh
# ---------------------------------------------------------------------------
class KeycloakToken:
    def __init__(self):
        self._token: Optional[str] = None
        self._expires_at: float = 0.0

    def _fetch(self) -> None:
        log.info("Conectando a Keycloak: %s ", KC_URL)
        url = f"{KC_URL}/realms/{KC_REALM_DESTINO}/protocol/openid-connect/token"
        data = {
            "client_id":  KC_CLIENT_ID,
            # "username":   KC_ADMIN_USER,
            "client_secret":   KC_CLIENT_SECRET,
            "grant_type": "client_credentials",
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

def usuario_existe(token_mgr: KeycloakToken, username: str) -> bool:                                        # True si el username ya existe en el realm destino
    url    = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users"
    params = {"username": username, "exact": "true"}
    resp   = requests.get(url, params=params,
                          headers=_headers(token_mgr.value), timeout=15, verify=False)
    resp.raise_for_status()
    return len(resp.json()) > 0

def crear_usuario(token_mgr: KeycloakToken, usuario: UsuarioKC) -> Optional[str]:
    """Crea usuario y retorna su ID (extraído del header Location)."""
    url  = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users"
    resp = requests.post(url, json=usuario.to_keycloak_payload(),
                         headers=_headers(token_mgr.value), timeout=15, verify=False)
    resp.raise_for_status()
    location = resp.headers.get("Location", "")
    return location.rsplit("/", 1)[-1] if location else None


def cargar_cache_grupos(token_mgr: KeycloakToken) -> dict[str, dict]:
    """Carga todos los grupos del realm (3 niveles: SS → establecimiento → rol).
    Keycloak 26 no retorna subGroups anidados; hay que usar /children en cada nivel."""
    cache: dict[str, dict] = {}                                                                              # organizationId → {group_id, name, children: {child_name: child_id}}

    def _get_children(group_id: str) -> list[dict]:
        url  = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups/{group_id}/children"
        params = {"briefRepresentation": "false", "max": "10000"}
        resp = requests.get(url, params=params, headers=_headers(token_mgr.value), timeout=30, verify=False)
        resp.raise_for_status()
        return resp.json()

    # 1. Grupos raíz (S.S.)
    url    = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups"
    params = {"briefRepresentation": "false", "max": "10000"}
    resp   = requests.get(url, params=params, headers=_headers(token_mgr.value), timeout=60, verify=False)
    resp.raise_for_status()
    root_groups = resp.json()
    log.info("Grupos raíz encontrados: %d — cargando establecimientos y roles...", len(root_groups))

    # 2. Por cada raíz → obtener establecimientos (/children)
    for rg in root_groups:
        rg_org_id = ""
        attrs = rg.get("attributes", {})
        if "organizationId" in attrs:
            val = attrs["organizationId"]
            rg_org_id = val[0] if isinstance(val, list) else str(val)

        establecimientos = _get_children(rg["id"])

        if rg_org_id:
            hijos = {e["name"]: e["id"] for e in establecimientos}
            cache[rg_org_id] = {"group_id": rg["id"], "name": rg.get("name", ""), "children": hijos}

        # 3. Por cada establecimiento → obtener roles (/children)
        for est in establecimientos:
            est_org_id = ""
            est_attrs = est.get("attributes", {})
            if "organizationId" in est_attrs:
                val = est_attrs["organizationId"]
                est_org_id = val[0] if isinstance(val, list) else str(val)

            roles = _get_children(est["id"])

            if est_org_id:
                hijos_roles = {r["name"]: r["id"] for r in roles}
                cache[est_org_id] = {"group_id": est["id"], "name": est.get("name", ""), "children": hijos_roles}

    log.info("Cache de grupos cargada: %d nodos con organizationId", len(cache))
    return cache


def asignar_usuario_a_grupo(token_mgr: KeycloakToken, user_id: str, group_id: str) -> None:
    """Asigna un usuario a un grupo en Keycloak."""
    url  = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/users/{user_id}/groups/{group_id}"
    resp = requests.put(url, headers=_headers(token_mgr.value), timeout=15, verify=False)
    resp.raise_for_status()


def asignar_grupos_usuario(token_mgr: KeycloakToken, user_id: str, nodos: list, cache_grupos: dict) -> None:
    """Para cada nodo del usuario, busca el grupo por organizationId (nodo_id) y asigna al subgrupo de rol."""
    asignados = set()                                                                                        # evitar duplicados
    for nodo in nodos:
        grupo_kc = nodo.get("grupo_kc", "")
        if not grupo_kc:
            log.warning("    Sin mapeo de grupo para rol_id=%s en nodo %s (padre: %s)", nodo.get("rol_id"), nodo.get("nodo_id"), nodo.get("razon_social_padre"))
            continue

        nodo_id = nodo.get("nodo_id", "")
        clave = f"{nodo_id}:{grupo_kc}"
        if clave in asignados:
            continue

        # Buscar el nodo en la cache por organizationId
        grupo_padre = cache_grupos.get(nodo_id)
        if not grupo_padre:
            log.warning("    Nodo %s (padre: %s) no encontrado en cache de grupos KC", nodo_id, nodo.get("razon_social_padre"))
            continue

        # Buscar el subgrupo de rol dentro del nodo
        child_id = grupo_padre["children"].get(grupo_kc)
        if not child_id:
            log.warning("    Subgrupo '%s' no encontrado bajo nodo %s (%s)", grupo_kc, nodo_id, grupo_padre["name"])
            continue

        asignar_usuario_a_grupo(token_mgr, user_id, child_id)
        log.info("    Asignado a grupo: %s/%s/%s (nodo_id=%s)", nodo.get("razon_social_padre", ""), grupo_padre["name"], grupo_kc, nodo_id)
        asignados.add(clave)

# ---------------------------------------------------------------------------
# Lectura desde SQL Server y construcción de objetos UsuarioKC
# ---------------------------------------------------------------------------
def leer_usuarios_db() -> list[UsuarioKC]:
    conn_str = (
        f"DRIVER={{{DB_DRIVER}}};"
        f"SERVER={DB_SERVER};"
        f"DATABASE={DB_DATABASE};"
        f"UID={DB_USER};"
        f"PWD={DB_PASSWORD};"
        "TrustServerCertificate=yes;"
        "Encrypt=yes;"
    )
    log.info("Conectando a SQL Server: %s / %s", DB_SERVER, DB_DATABASE)
    with pyodbc.connect(conn_str, timeout=30) as conn:
        cursor = conn.cursor()
        cursor.execute(SQL_QUERY)
        cols  = [col[0].lower() for col in cursor.description]
        filas = cursor.fetchall()

    log.info("Filas obtenidas: %d — agrupando por RUT...", len(filas))

    # Agrupar filas por RUT: la primera fila (rn_global=1) tiene la contraseña más reciente
    rut_map: dict[str, dict] = {}
    for fila in filas:
        row = dict(zip(cols, fila))
        rut_raw = str(row.get("rut") or "").strip().replace(".", "").lower()
        rut_sin_guion = rut_raw.replace("-", "")

        if RUTS_PILOTO and rut_sin_guion not in RUTS_PILOTO:
            continue

        rol_id_raw = row.get("rol_id")
        rol_id = int(rol_id_raw) if rol_id_raw is not None else None

        nodo_info = {
            "nodo_id":             str(row.get("nodo_id") or ""),
            "razon_social":        str(row.get("razon_social") or "").strip(),
            "razon_social_padre":  str(row.get("razon_social_padre") or "").strip(),
            "tipo_descripcion":    str(row.get("tipo_descripcion") or "").strip(),
            "dominio":             str(row.get("dominio") or "").strip(),
            "password_hash":       str(row.get("password_hash") or "").strip(),
            "salt":                str(row.get("salt") or "").strip(),
            "rol_id":              rol_id,
            "rol":                 str(row.get("rol") or "").strip(),
            "grupo_kc":            ROL_A_GRUPO.get(rol_id, "") if rol_id is not None else "",
        }

        if rut_raw not in rut_map:
            # Primera fila = login más reciente (rn_global=1), se usa su contraseña
            rut_map[rut_raw] = {
                "row": row,
                "nodos": [nodo_info],
            }
        else:
            rut_map[rut_raw]["nodos"].append(nodo_info)

    usuarios: list[UsuarioKC] = []
    skipped_sin_mail = 0

    for rut_raw, data in rut_map.items():
        row = data["row"]
        nodos = data["nodos"]

        email = str(row.get("email") or "").strip()
        if not email:
            log.warning("Sin email: RUT=%s login=%s — se importará sin email.", rut_raw, row.get("login"))
            skipped_sin_mail += 1

        login     = str(row.get("login") or "").strip().lower()
        nombres   = limpiar_nombre(row.get("nombres"))
        apellidos = limpiar_nombre(
            str(row.get("apellido_paterno") or "") + " " +
            str(row.get("apellido_materno") or "")
        )

        # Contraseña del último login (primera fila, rn_global=1)
        pwd_hash = str(row.get("password_hash") or "").strip() or None
        salt     = str(row.get("salt") or "").strip() or None

        usuarios.append(UsuarioKC(
            username      = normalizar_rut(rut_raw) or login,                                               # username = RUT formateado (ej: 12345678-9)
            email         = email,
            firstName     = nombres,
            lastName      = apellidos,
            enabled       = bool(row.get("activo", True)),
            rut           = normalizar_rut(rut_raw),
            password_hash = pwd_hash,
            salt          = salt,
            attributes    = {
                "organizacion":        [nodos[0]["razon_social"]],
                "organizacion_padre":  [nodos[0]["razon_social_padre"]],
                "tipo_establecimiento":[nodos[0]["tipo_descripcion"]],
                "dominio":             [nodos[0]["dominio"]],
                "nodo_id":             [nodos[0]["nodo_id"]],
                "nodo_padre_id":       [str(row.get("nodo_padre_id") or "").strip()],
            },
            nodos         = nodos,
        ))

    log.info("Usuarios a importar: %d  (sin email: %d)", len(usuarios), skipped_sin_mail)

    # --- Generar log CSV: usuario | rut | contraseña usada (nodo origen) | nodos asignados ---
    import csv
    csv_path = "usuarios_nodos_log.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile, delimiter=";")
        writer.writerow(["username", "rut", "password_hash_usado", "salt_usado", "nodo_origen_password", "dominio_origen_password", "nodos_roles_grupos"])
        for u in usuarios:
            nodo_pwd = u.nodos[0] if u.nodos else {}
            nodos_str = " | ".join([f"{n['nodo_id']}:{n['razon_social']}({n['dominio']}) rol={n.get('rol_id','?')}→{n.get('grupo_kc','?')}" for n in u.nodos])
            writer.writerow([
                u.username,
                u.rut,
                u.password_hash or "",
                u.salt or "",
                nodo_pwd.get("razon_social", ""),
                nodo_pwd.get("dominio", ""),
                nodos_str,
            ])
    log.info("Log de usuarios/nodos generado: %s", csv_path)

    return usuarios

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> None:
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)                                      # silencia warnings SSL de DEV

    log.info("=== Inicio importación → realm: %s ===", KC_REALM_DESTINO)

    # 1. Leer usuarios desde BD
    usuarios = leer_usuarios_db()
    if not usuarios:
        log.warning("No se encontraron usuarios en la BD. Finalizando.")
        return

    # --- Usuario de prueba — simula hash SHA-1 de producción ---
    # Permite verificar que el SPI custom-sha1 valida correctamente
    # antes de tocar la BD de producción real
    from dataclasses import fields as dc_fields
    usuario_prueba = UsuarioKC(
        username      = "16645560k",                                                                         # RUT cortiz como username
        email         = "cortiz@rayen.cl",                                                                   #
        firstName     = "Claudio",                                                                           #
        lastName      = "Ortiz",                                                                             #
        enabled       = True,                                                                                #
        rut           = "16645560-k",                                                                        #
        password_hash = "42A142CFFF3153F15C6F15B043542F2150329E14",                                          # SHA1("Rayen123" + salt) — clave de prueba
        salt          = "sq6pvdo=",                                                                           # salt ficticio formato Base64 — igual al de producción
        attributes    = {
            "organizacion":         ["Rayen Salud SpA"],                                                     #
            "organizacion_padre":   ["Rayen"],                                                               #
            "tipo_establecimiento": ["Test"],                                                                 #
            "dominio":              ["rayen"],                                                               #
            "nodo_id":              ["0"],                                                                   #
            "nodo_padre_id":        ["0"],                                                                   #
        },
    )
    usuarios.append(usuario_prueba)
    # --- fin usuario de prueba ---

    # 2. Importar usuario por usuario
    token_mgr  = KeycloakToken()

    # Cargar cache de grupos KC — índice por organizationId (nodo_id)
    cache_grupos = cargar_cache_grupos(token_mgr)

    creados    = 0
    omitidos   = 0
    errores: list[str] = []

    for i, u in enumerate(usuarios, start=1):
        log.info("[%d/%d] %s  |  %s  |  %s", i, len(usuarios), u.username, u.rut or "—", u.email)
        try:
            if usuario_existe(token_mgr, u.username):
                log.info("  → Ya existe, omitido.")
                omitidos += 1
                continue
            user_id = crear_usuario(token_mgr, u)
            nodos_str = ", ".join([f"{n['razon_social']}({n['dominio']})" for n in u.nodos])
            log.info("  → Creado OK (id=%s). Nodos: [%s]", user_id, nodos_str)
            # Asignar a grupos según nodos + roles
            if user_id:
                asignar_grupos_usuario(token_mgr, user_id, u.nodos, cache_grupos)
            creados += 1
        except requests.exceptions.HTTPError as exc:
            msg = f"{u.username}: HTTP {exc.response.status_code} — {exc.response.text[:300]}"
            log.error("  → Error HTTP: %s", msg)
            errores.append(msg)
        except Exception as exc:
            msg = f"{u.username}: {exc}"
            log.error("  → Error inesperado: %s", msg)
            errores.append(msg)

    # 3. Resumen final
    log.info("=== Resumen ===")
    log.info("  Total procesados : %d", len(usuarios))
    log.info("  Creados          : %d", creados)
    log.info("  Omitidos (exist) : %d", omitidos)
    log.info("  Errores          : %d", len(errores))
    if errores:
        log.warning("  Detalle errores:")
        for e in errores:
            log.warning("    • %s", e)
    log.info("  Log guardado en  : importacion_usuarios.log")


if __name__ == "__main__":
    main()