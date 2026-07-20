import os
import requests
from dotenv import load_dotenv

# Cargar variables de entorno
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), '.env'))

KC_URL = os.getenv('KC_URL', 'https://keyloackdesa.saludteprotege.cl:8443')
KC_REALM_DESTINO = os.getenv('KC_REALM_DESTINO', 'RNI-Dev')
KC_CLIENT_ID = os.getenv('KC_CLIENT_ID', 'rni-apigateway')
KC_CLIENT_SECRET = os.getenv('KC_CLIENT_SECRET', 'REDACTED_KC_APIGW_SECRET')

# Suprimir warnings de SSL
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def get_token():
    url = f'{KC_URL}/realms/{KC_REALM_DESTINO}/protocol/openid-connect/token'
    data = {
        'client_id': KC_CLIENT_ID,
        'client_secret': KC_CLIENT_SECRET,
        'grant_type': 'client_credentials'
    }
    resp = requests.post(
        url,
        data=data,
        headers={'Content-Type': 'application/x-www-form-urlencoded'},
        verify=False
    )
    resp.raise_for_status()
    return resp.json()['access_token']


def get_subgroups(group_id, token):
    """Obtiene los hijos directos de un grupo vía API"""
    url = f"{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups/{group_id}/children"
    resp = requests.get(
        url,
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        verify=False
    )
    resp.raise_for_status()
    return resp.json()


def print_groups(groups, token, level=0):
    for group in groups:
        indent = '  ' * level
        print(f"{indent}- {group['name']} (id: {group['id']}, path: {group['path']})")

        subgrupos = group.get('subGroups', [])

        # Si no vienen subgrupos pero el contador dice que hay, consultarlos
        if not subgrupos and group.get('subGroupCount', 0) > 0:
            subgrupos = get_subgroups(group['id'], token)

        # Recursión para cada subgrupo sin importar el nivel
        if subgrupos:
            print_groups(subgrupos, token, level + 1)


def get_all_groups(token):
    url = f'{KC_URL}/admin/realms/{KC_REALM_DESTINO}/groups'
    resp = requests.get(
        url,
        headers={'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'},
        verify=False
    )
    resp.raise_for_status()
    return resp.json()


if __name__ == "__main__":
    try:
        print("Obteniendo token...")
        token = get_token()
        print("Token obtenido correctamente.\n")

        print("Obteniendo grupos...")
        groups = get_all_groups(token)

        if not groups:
            print("No se encontraron grupos en el realm.")
        else:
            print(f"Se encontraron {len(groups)} grupos raíz.\n")
            print("Listado de grupos y subgrupos:")
            print("-" * 50)
            print_groups(groups, token)
            print("-" * 50)
            print("Fin del listado.")

    except requests.exceptions.HTTPError as e:
        print(f'ERROR HTTP: {e.response.status_code} - {e.response.text}')
    except Exception as e:
        print(f'ERROR: {e}')