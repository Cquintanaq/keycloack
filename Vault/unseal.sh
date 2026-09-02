#!/usr/bin/env bash
# unseal.sh — Desbloquea Vault después de un reinicio del pod.
# Requiere 3 de 5 unseal keys (guardadas en gestor corporativo).

set -euo pipefail

NAMESPACE="vault"
POD="vault-0"

echo "Estado actual de Vault:"
kubectl exec -n "${NAMESPACE}" "${POD}" -- vault status 2>/dev/null || true
echo ""

SEALED=$(kubectl exec -n "${NAMESPACE}" "${POD}" -- vault status -format=json 2>/dev/null \
  | jq -r '.sealed' || echo "true")

if [ "${SEALED}" = "false" ]; then
  echo "✅ Vault ya está desbloqueado."
  exit 0
fi

echo "Ingresa 3 unseal keys (no se muestran al escribir):"
read -r -s -p "Unseal Key 1: " KEY1; echo
read -r -s -p "Unseal Key 2: " KEY2; echo
read -r -s -p "Unseal Key 3: " KEY3; echo
echo ""

kubectl exec -n "${NAMESPACE}" "${POD}" -- vault operator unseal "${KEY1}"
kubectl exec -n "${NAMESPACE}" "${POD}" -- vault operator unseal "${KEY2}"
kubectl exec -n "${NAMESPACE}" "${POD}" -- vault operator unseal "${KEY3}"

echo ""
echo "Estado después del unseal:"
kubectl exec -n "${NAMESPACE}" "${POD}" -- vault status
