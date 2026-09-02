#!/usr/bin/env bash
# Configura autenticación Kubernetes para el cluster worker-pre.
# Requiere: VAULT_ADDR y VAULT_TOKEN como variables de entorno.
# Requiere: kubectl con contexto worker-pre disponible.
#
# Basado en enable-k8s-dev.sh (NO en enable-k8s-qa.sh): la versión de QA no carga
# las políticas HCL y le falta el rol rabbit-security-role — enable-k8s-dev.sh
# es el único de los dos que crea ambas cosas. PRE necesita las dos.
#
# Diferencia respecto a dev/qa: PRE usa un único namespace (pre-master) para
# backend y security, en vez de separar dev-backend/dev-security/dev-sprint-1.

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Definir VAULT_ADDR}"
VAULT_TOKEN="${VAULT_TOKEN:?Definir VAULT_TOKEN}"
CLUSTER_CONTEXT="worker-pre"
NAMESPACE="pre-master"

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

echo "==> Habilitando método auth kubernetes-pre en Vault..."
vault auth enable -path=kubernetes-pre kubernetes 2>/dev/null || \
  echo "  (ya estaba habilitado, actualizando config)"

vault write auth/kubernetes-pre/config \
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

echo "==> Creando roles para microservicios en namespace ${NAMESPACE}..."
for svc in patient organization practitioner vaccination notifications integrations audit versionmanager reporting; do
  vault write "auth/kubernetes-pre/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${NAMESPACE}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

echo "==> Creando roles para infraestructura backend en namespace ${NAMESPACE}..."
for svc in rabbit-notifications redis-notifications redis-versionmanager rabbit-general-backend rabbit-audit; do
  vault write "auth/kubernetes-pre/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${NAMESPACE}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

echo "==> Creando roles para seguridad en namespace ${NAMESPACE}..."
for svc in gateway rabbit-security redis-security; do
  vault write "auth/kubernetes-pre/role/${svc}-role" \
    bound_service_account_names="${svc}-sa" \
    bound_service_account_namespaces="${NAMESPACE}" \
    policies="${svc}-policy" \
    ttl=1h
  echo "  ✓ Rol: ${svc}-role → policy: ${svc}-policy"
done

# opa-role queda creado por paridad con dev, aunque security/opa-security.yml no
# tiene anotaciones Vault todavía (ver secrets-backend-vault-azure.md) — no hace
# daño tenerlo listo, ningún manifiesto lo usa hasta que se active ese flujo.
vault write auth/kubernetes-pre/role/opa-role \
  bound_service_account_names="opa-sa" \
  bound_service_account_namespaces="${NAMESPACE}" \
  policies="opa-policy" \
  ttl=1h
echo "  ✓ Rol: opa-role → policy: opa-policy (sin consumidor todavía)"

echo ""
echo "✅ Auth kubernetes-pre configurado para cluster worker-pre."
echo "   Todos los ServiceAccounts (backend + security) viven en el namespace ${NAMESPACE}."
