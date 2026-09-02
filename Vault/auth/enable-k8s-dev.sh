#!/usr/bin/env bash
# Configura autenticación Kubernetes para el cluster worker-dev.
# Requiere: VAULT_ADDR y VAULT_TOKEN como variables de entorno.
# Requiere: kubectl con contexto worker-dev disponible.

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Definir VAULT_ADDR}"
VAULT_TOKEN="${VAULT_TOKEN:?Definir VAULT_TOKEN}"
CLUSTER_CONTEXT="worker-dev"
BACKEND_NS="dev-backend"
SECURITY_NS="dev-security"
SPRINT1_NS="dev-sprint-1"

export VAULT_ADDR VAULT_TOKEN

K8S_HOST=$(kubectl --context="${CLUSTER_CONTEXT}" config view \
  --minify -o jsonpath='{.clusters[0].cluster.server}')

K8S_CA=$(kubectl --context="${CLUSTER_CONTEXT}" \
  config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

SA_JWT=$(kubectl --context="${CLUSTER_CONTEXT}" \
  -n kube-system create token vault-reviewer --duration=8760h 2>/dev/null || \
  kubectl --context="${CLUSTER_CONTEXT}" \
  -n kube-system get secret \
  "$(kubectl --context="${CLUSTER_CONTEXT}" -n kube-system get sa vault-reviewer \
    -o jsonpath='{.secrets[0].name}')" \
  -o jsonpath='{.data.token}' | base64 -d)

echo "==> Habilitando método auth kubernetes-dev en Vault..."
vault auth enable -path=kubernetes-dev kubernetes 2>/dev/null || \
  echo "  (ya estaba habilitado, actualizando config)"

vault write auth/kubernetes-dev/config \
  kubernetes_host="${K8S_HOST}" \
  kubernetes_ca_cert="${K8S_CA}" \
  token_reviewer_jwt="${SA_JWT}"

echo "==> Cargando políticas de microservicios..."
POLICY_DIR="$(dirname "$0")/../policies"
for policy in patient organization practitioner vaccination notifications integrations audit versionmanager reporting gateway \
              rabbit-general-backend rabbit-audit rabbit-notifications rabbit-security \
              redis-notifications redis-versionmanager redis-security opa; do
  vault policy write "${policy}-policy" "${POLICY_DIR}/${policy}-policy.hcl"
  echo "  ✓ Policy: ${policy}-policy"
done

echo "==> Creando roles para microservicios en namespace ${BACKEND_NS}..."
for svc in patient organization practitioner vaccination notifications integrations audit versionmanager reporting; do
  vault write "auth/kubernetes-dev/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${BACKEND_NS}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

echo "==> Creando roles para infraestructura backend en namespace ${BACKEND_NS}..."
for svc in rabbit-notifications redis-notifications redis-versionmanager; do
  vault write "auth/kubernetes-dev/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${BACKEND_NS}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

echo "==> Creando roles para infraestructura en namespace ${SPRINT1_NS}..."
for svc in rabbit-general-backend rabbit-audit redis-security; do
  vault write "auth/kubernetes-dev/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${SPRINT1_NS}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

echo "==> Creando roles para seguridad en namespace ${SECURITY_NS}..."
vault write auth/kubernetes-dev/role/gateway-role \
  bound_service_account_names="gateway-sa" \
  bound_service_account_namespaces="${SECURITY_NS}" \
  policies="gateway-policy" \
  ttl=1h
echo "  ✓ Rol: gateway-role → policy: gateway-policy"

vault write auth/kubernetes-dev/role/rabbit-security-role \
  bound_service_account_names="rabbit-security-sa" \
  bound_service_account_namespaces="${SECURITY_NS}" \
  policies="rabbit-security-policy" \
  ttl=1h
echo "  ✓ Rol: rabbit-security-role → policy: rabbit-security-policy"

vault write auth/kubernetes-dev/role/opa-role \
  bound_service_account_names="opa-sa" \
  bound_service_account_namespaces="${SECURITY_NS}" \
  policies="opa-policy" \
  ttl=1h
echo "  ✓ Rol: opa-role → policy: opa-policy"

echo ""
echo "✅ Auth kubernetes-dev configurado para cluster worker-dev."
echo "   ServiceAccounts requeridos:"
echo "   - ${BACKEND_NS}: patient/organization/practitioner/vaccination/notifications/integrations/audit/versionmanager/reporting-sa"
echo "   - ${BACKEND_NS}: rabbit-notifications/redis-notifications/redis-versionmanager-sa"
echo "   - ${SPRINT1_NS}: rabbit-general-backend/rabbit-audit/redis-security-sa"
echo "   - ${SECURITY_NS}: gateway/rabbit-security/opa-sa"
