#!/usr/bin/env bash
# Inicialización única de Vault. Ejecutar UNA sola vez post-install.
# Los unseal keys y root token se deben guardar en gestor de contraseñas corporativo.

set -euo pipefail

NAMESPACE="vault"
POD="vault-0"
VAULT_CMD="kubectl exec -n ${NAMESPACE} ${POD} -- vault"

echo "==> Verificando estado de Vault..."
kubectl exec -n ${NAMESPACE} ${POD} -- vault status 2>/dev/null || true

echo ""
echo "==> Inicializando Vault (5 claves, umbral 3)..."
INIT_OUTPUT=$(kubectl exec -n ${NAMESPACE} ${POD} -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json)

echo "${INIT_OUTPUT}" > vault-init-output.json
echo ""
echo "⚠️  vault-init-output.json generado. GUÁRDALO EN EL GESTOR CORPORATIVO"
echo "⚠️  ELIMÍNALO de este equipo después: rm vault-init-output.json"
echo ""

ROOT_TOKEN=$(echo "${INIT_OUTPUT}" | jq -r '.root_token')
UNSEAL_KEY_1=$(echo "${INIT_OUTPUT}" | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(echo "${INIT_OUTPUT}" | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(echo "${INIT_OUTPUT}" | jq -r '.unseal_keys_b64[2]')

echo "==> Haciendo unseal (3 de 5 claves)..."
${VAULT_CMD} operator unseal "${UNSEAL_KEY_1}"
${VAULT_CMD} operator unseal "${UNSEAL_KEY_2}"
${VAULT_CMD} operator unseal "${UNSEAL_KEY_3}"

echo "==> Login con root token..."
${VAULT_CMD} login "${ROOT_TOKEN}"

echo "==> Habilitando KV v2 engine en path 'secret/'..."
${VAULT_CMD} secrets enable -path=secret kv-v2

echo "==> Habilitando Audit Log..."
${VAULT_CMD} audit enable file file_path=/vault/logs/audit.log

echo "==> Cargando políticas desde policies/..."
for policy_file in policies/*.hcl; do
  policy_name=$(basename "${policy_file}" .hcl)
  kubectl cp "${policy_file}" "${NAMESPACE}/${POD}:/tmp/${policy_name}.hcl"
  ${VAULT_CMD} policy write "${policy_name}" "/tmp/${policy_name}.hcl"
  echo "  ✓ Policy cargada: ${policy_name}"
done

echo ""
echo "✅ Vault inicializado correctamente."
echo "   Próximos pasos:"
echo "   1. Guardar vault-init-output.json en gestor corporativo"
echo "   2. Eliminar vault-init-output.json de este equipo"
echo "   3. Ejecutar auth/enable-k8s-dev.sh para configurar worker-dev"
echo "   4. Ejecutar auth/enable-k8s-qa.sh para configurar worker-qa"
