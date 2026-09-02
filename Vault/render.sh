#!/usr/bin/env bash
# render.sh — Genera vault-all.yaml listo para importar en Rancher.
# Requiere: helm >= 3.0 instalado localmente.
#
# Uso:
#   ./render.sh
#
# Para actualizar versión de Vault:
#   Cambiar VAULT_CHART_VERSION abajo y volver a correr.
#   Revisar el diff en vault-all.yaml antes de commitear.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/vault-all.yaml"
VAULT_CHART_VERSION="0.29.1"

echo "==> Verificando dependencias..."
if ! command -v helm &>/dev/null; then
  echo "ERROR: helm no encontrado. Instalar desde https://helm.sh/docs/intro/install/"
  exit 1
fi

echo "==> Actualizando repo hashicorp..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null || true
helm repo update hashicorp

echo "==> Renderizando chart vault@${VAULT_CHART_VERSION} con values.yaml..."
HELM_OUTPUT=$(helm template vault hashicorp/vault \
  --namespace vault \
  --version "${VAULT_CHART_VERSION}" \
  --values "${SCRIPT_DIR}/values.yaml")

echo "==> Compilando ${OUTPUT}..."
{
  printf "# vault-all.yaml\n"
  printf "# Generado por render.sh — NO editar manualmente.\n"
  printf "# Vault chart version: %s\n" "${VAULT_CHART_VERSION}"
  printf "# Para actualizar: cambiar VAULT_CHART_VERSION en render.sh y volver a correr.\n"
  printf "#\n"
  printf "# Para worker-dev y worker-qa — SIN Ingress externo\n"
  printf "# Import en Rancher:\n"
  printf "#   Rancher UI → worker-dev o worker-qa → Import YAML → subir este archivo\n"
  printf "# O via CLI:\n"
  printf "#   kubectl --context=worker-dev apply -f vault-all.yaml\n"
  printf "---\n"
  cat "${SCRIPT_DIR}/namespace.yaml"
  printf "---\n"
  printf "%s\n" "${HELM_OUTPUT}"
} > "${OUTPUT}"

LINE_COUNT=$(wc -l < "${OUTPUT}")
echo ""
echo "✅ Generado: vault-all.yaml (${LINE_COUNT} líneas)"
echo ""
echo "Próximos pasos:"
echo "  1. git diff vault-all.yaml"
echo "  2. git commit -m 'Update: vault-all.yaml vault@${VAULT_CHART_VERSION}'"
echo "  3. Rancher UI → worker-dev o worker-qa → Import YAML → vault-all.yaml"
echo "  4. kubectl --context=worker-dev get pods -n vault"
echo "  5. vault operator init + unseal manual"
