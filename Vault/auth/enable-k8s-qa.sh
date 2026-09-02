#!/usr/bin/env bash
# Configura autenticación Kubernetes para el cluster worker-qa.
# Requiere: VAULT_ADDR y VAULT_TOKEN como variables de entorno.
# Requiere: kubectl con contexto worker-qa disponible.

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Definir VAULT_ADDR}"
VAULT_TOKEN="${VAULT_TOKEN:?Definir VAULT_TOKEN}"
CLUSTER_CONTEXT="worker-qa"
BACKEND_NS="qa-sprint-1"
SECURITY_NS="qa-sprint-1"

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

echo "==> Habilitando método auth kubernetes-qa en Vault..."
vault auth enable -path=kubernetes-qa kubernetes 2>/dev/null || \
  echo "  (ya estaba habilitado, actualizando config)"

vault write auth/kubernetes-qa/config \
  kubernetes_host="${K8S_HOST}" \
  kubernetes_ca_cert="${K8S_CA}" \
  token_reviewer_jwt="${SA_JWT}"

echo "==> Creando roles para microservicios en namespace ${BACKEND_NS}..."
for svc in patient organization practitioner vaccination notifications integrations audit versionmanager reporting; do
  vault write "auth/kubernetes-qa/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${BACKEND_NS}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

echo "==> Creando rol para API Gateway en namespace ${SECURITY_NS}..."
vault write auth/kubernetes-qa/role/gateway-role \
  bound_service_account_names="gateway-sa" \
  bound_service_account_namespaces="${SECURITY_NS}" \
  policies="gateway-policy" \
  ttl=1h
echo "  ✓ Rol: gateway-role → policy: gateway-policy"

echo "==> Creando roles para infraestructura backend en namespace ${BACKEND_NS}..."
for svc in rabbit-notifications redis-notifications redis-versionmanager; do
  vault write "auth/kubernetes-qa/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${BACKEND_NS}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

echo "==> Creando roles para infraestructura en namespace ${BACKEND_NS}..."
for svc in rabbit-general-backend rabbit-audit redis-security; do
  vault write "auth/kubernetes-qa/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${BACKEND_NS}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

echo ""
echo "✅ Auth kubernetes-qa configurado para cluster worker-qa."
echo "   Próximo paso: crear ServiceAccounts en ${BACKEND_NS} y ${SECURITY_NS}."
