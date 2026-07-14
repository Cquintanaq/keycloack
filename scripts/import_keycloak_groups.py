#!/usr/bin/env python3
"""Importa grupos de Keycloak desde un realm-export.json.

Uso:
  python scripts/import_keycloak_groups.py --file realm-export.json

Variables de entorno requeridas:
  KEYCLOAK_URL               URL base de Keycloak (por defecto: http://localhost:8080)
  KEYCLOAK_ADMIN             Usuario admin
  KEYCLOAK_ADMIN_PASSWORD    Password admin

Opcionales:
  KEYCLOAK_REALM             Realm destino (si no se define, usa el del JSON)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


class KeycloakAdminClient:
    def __init__(self, base_url: str, admin_user: str, admin_password: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.admin_user = admin_user
        self.admin_password = admin_password
        self.token = self._login()

    def _login(self) -> str:
        url = f"{self.base_url}/realms/master/protocol/openid-connect/token"
        payload = urllib.parse.urlencode(
            {
                "client_id": "admin-cli",
                "grant_type": "password",
                "username": self.admin_user,
                "password": self.admin_password,
            }
        ).encode("utf-8")

        req = urllib.request.Request(url, data=payload, method="POST")
        req.add_header("Content-Type", "application/x-www-form-urlencoded")

        try:
            with urllib.request.urlopen(req) as resp:
                body = json.loads(resp.read().decode("utf-8"))
                token = body.get("access_token")
                if not token:
                    raise RuntimeError("No se pudo obtener access_token de Keycloak.")
                return token
        except urllib.error.HTTPError as err:
            detail = err.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"Error autenticando contra Keycloak: {err.code} {detail}") from err

    def _request(
        self,
        method: str,
        path: str,
        *,
        body: dict[str, Any] | list[Any] | None = None,
        query: dict[str, Any] | None = None,
    ) -> tuple[int, dict[str, str], Any | None]:
        url = f"{self.base_url}{path}"
        if query:
            url = f"{url}?{urllib.parse.urlencode(query)}"

        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")

        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {self.token}")
        req.add_header("Accept", "application/json")
        if body is not None:
            req.add_header("Content-Type", "application/json")

        try:
            with urllib.request.urlopen(req) as resp:
                raw = resp.read()
                parsed = None
                if raw:
                    parsed = json.loads(raw.decode("utf-8"))
                return resp.status, dict(resp.headers.items()), parsed
        except urllib.error.HTTPError as err:
            detail = err.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"{method} {path} fallo con {err.code}: {detail}") from err

    def list_top_groups(self, realm: str) -> list[dict[str, Any]]:
        _, _, body = self._request(
            "GET",
            f"/admin/realms/{urllib.parse.quote(realm)}/groups",
            query={"first": 0, "max": 2000},
        )
        return body or []

    def list_child_groups(self, realm: str, parent_id: str) -> list[dict[str, Any]]:
        _, _, body = self._request(
            "GET",
            f"/admin/realms/{urllib.parse.quote(realm)}/groups/{urllib.parse.quote(parent_id)}/children",
            query={"first": 0, "max": 2000},
        )
        return body or []

    def create_top_group(self, realm: str, payload: dict[str, Any]) -> str:
        _, headers, _ = self._request(
            "POST",
            f"/admin/realms/{urllib.parse.quote(realm)}/groups",
            body=payload,
        )
        location = headers.get("Location") or headers.get("location")
        if not location:
            raise RuntimeError("Keycloak no devolvio header Location al crear grupo top-level.")
        return location.rstrip("/").split("/")[-1]

    def create_child_group(self, realm: str, parent_id: str, payload: dict[str, Any]) -> str:
        _, headers, _ = self._request(
            "POST",
            f"/admin/realms/{urllib.parse.quote(realm)}/groups/{urllib.parse.quote(parent_id)}/children",
            body=payload,
        )
        location = headers.get("Location") or headers.get("location")
        if not location:
            raise RuntimeError("Keycloak no devolvio header Location al crear subgrupo.")
        return location.rstrip("/").split("/")[-1]

    def update_group(self, realm: str, group_id: str, payload: dict[str, Any]) -> None:
        self._request(
            "PUT",
            f"/admin/realms/{urllib.parse.quote(realm)}/groups/{urllib.parse.quote(group_id)}",
            body=payload,
        )


def normalize_attributes(raw: Any) -> dict[str, list[str]]:
    if not isinstance(raw, dict):
        return {}

    attributes: dict[str, list[str]] = {}
    for key, value in raw.items():
        if isinstance(value, list):
            attributes[str(key)] = [str(v) for v in value]
        else:
            attributes[str(key)] = [str(value)]
    return attributes


def group_payload(group_data: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": group_data["name"],
        "attributes": normalize_attributes(group_data.get("attributes", {})),
    }


def find_by_name(groups: list[dict[str, Any]], name: str) -> dict[str, Any] | None:
    for group in groups:
        if group.get("name") == name:
            return group
    return None


def ensure_group_tree(
    client: KeycloakAdminClient,
    realm: str,
    group_data: dict[str, Any],
    parent_id: str | None,
) -> str:
    name = str(group_data.get("name", "")).strip()
    if not name:
        raise RuntimeError("Se encontro un grupo sin nombre en el JSON.")

    if parent_id is None:
        siblings = client.list_top_groups(realm)
        existing = find_by_name(siblings, name)
        if existing:
            group_id = existing["id"]
            client.update_group(realm, group_id, group_payload(group_data))
            print(f"[OK] Grupo existente actualizado: {name}")
        else:
            group_id = client.create_top_group(realm, group_payload(group_data))
            print(f"[OK] Grupo creado: {name}")
    else:
        siblings = client.list_child_groups(realm, parent_id)
        existing = find_by_name(siblings, name)
        if existing:
            group_id = existing["id"]
            client.update_group(realm, group_id, group_payload(group_data))
            print(f"[OK] Subgrupo existente actualizado: {name}")
        else:
            group_id = client.create_child_group(realm, parent_id, group_payload(group_data))
            print(f"[OK] Subgrupo creado: {name}")

    for child in group_data.get("subGroups", []):
        ensure_group_tree(client, realm, child, group_id)

    return group_id


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Crea/actualiza grupos en Keycloak desde realm-export.json"
    )
    parser.add_argument("--file", required=True, help="Ruta al realm-export.json")
    parser.add_argument(
        "--realm",
        default=None,
        help="Realm destino (si no se indica, usa el campo realm del JSON)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    keycloak_url = os.getenv("KEYCLOAK_URL", "http://localhost:8080")
    admin_user = os.getenv("KEYCLOAK_ADMIN")
    admin_password = os.getenv("KEYCLOAK_ADMIN_PASSWORD")

    if not admin_user or not admin_password:
        print(
            "Faltan variables KEYCLOAK_ADMIN y/o KEYCLOAK_ADMIN_PASSWORD.",
            file=sys.stderr,
        )
        return 2

    try:
        with open(args.file, "r", encoding="utf-8") as file:
            data = json.load(file)
    except OSError as err:
        print(f"No se pudo leer el archivo: {err}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as err:
        print(f"JSON invalido: {err}", file=sys.stderr)
        return 2

    realm = args.realm or os.getenv("KEYCLOAK_REALM") or data.get("realm")
    if not realm:
        print(
            "No se pudo determinar el realm (usa --realm o KEYCLOAK_REALM).",
            file=sys.stderr,
        )
        return 2

    groups = data.get("groups")
    if not isinstance(groups, list):
        print("El JSON no contiene un arreglo valido en 'groups'.", file=sys.stderr)
        return 2

    try:
        client = KeycloakAdminClient(keycloak_url, admin_user, admin_password)
        for group in groups:
            ensure_group_tree(client, realm, group, None)
    except RuntimeError as err:
        print(f"Error: {err}", file=sys.stderr)
        return 1

    print("Importacion de grupos completada.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
