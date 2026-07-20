# Verificacion y eliminacion de ACR, AKS y PostgreSQL (Bash)

## 1. Objetivo

Este archivo contiene comandos para:

1. Verificar recursos en Azure.
2. Eliminar AKS.
3. Eliminar ACR.
4. Eliminar PostgreSQL Flexible Server.

Usar desde Azure Cloud Shell (Bash).

## 2. Variables

```bash
: "${SUBSCRIPTION_ID:=284d787d-673e-4653-830b-ff03e6abd764}"
: "${RG:=RNI_CLU_AKS}"
: "${AKS_NAME:=aks-RNI-cluster}"
: "${ACR_NAME:=rnikeycloakacr}"
: "${PG_SERVER:=keycloakpro-db}"
```

No ejecutes `bash` antes del bloque de variables. Pegalo directo en Cloud Shell y valida:

```bash
set -euo pipefail

# Si las variables no existen en la sesion, las inicializa con defaults seguros.
: "${SUBSCRIPTION_ID:=284d787d-673e-4653-830b-ff03e6abd764}"
: "${RG:=RNI_CLU_AKS}"
: "${AKS_NAME:=aks-RNI-cluster}"
: "${ACR_NAME:=rnikeycloakacr}"
: "${PG_SERVER:=keycloakpro-db}"

echo "SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "RG=$RG"
echo "AKS_NAME=$AKS_NAME"
echo "ACR_NAME=$ACR_NAME"
echo "PG_SERVER=$PG_SERVER"
```

Nota: en tu salida real, el AKS existente era `aks-RNI-cluster`. Si quieres borrar otro cluster, cambia `AKS_NAME` antes de ejecutar.

## 3. Seleccionar suscripcion

```bash
az login --tenant c500e2eb-ab3a-4d3d-9573-15c62a700b75
az account set --subscription "$SUBSCRIPTION_ID"
az account show --output table
```

## 4. Verificar recursos

```bash
az group show --name "$RG" --output table

az aks list --resource-group "$RG" --output table
az acr list --resource-group "$RG" --output table
az postgres flexible-server list --resource-group "$RG" --output table

az aks show --resource-group "$RG" --name "$AKS_NAME" --output table
az acr show --name "$ACR_NAME" --output table
az postgres flexible-server show --resource-group "$RG" --name "$PG_SERVER" --output table
```

Si aparece `AuthorizationFailed`, solicita al menos rol `Contributor` (o `Owner`) sobre el Resource Group `RNI_CLU_AKS`.

Verificar bases en PostgreSQL:

```bash
az postgres flexible-server db list \
  --resource-group "$RG" \
  --server-name "$PG_SERVER" \
  --output table
```

## 5. Eliminar recursos (orden recomendado)

Orden recomendado para evitar dependencias:

1. AKS
2. PostgreSQL Flexible Server
3. ACR

### 5.1 Eliminar AKS

```bash
if az aks show --resource-group "$RG" --name "$AKS_NAME" --output none 2>/dev/null; then
  az aks delete \
    --resource-group "$RG" \
    --name "$AKS_NAME" \
    --yes \
    --no-wait

  az aks wait \
    --resource-group "$RG" \
    --name "$AKS_NAME" \
    --deleted
else
  echo "AKS $AKS_NAME no existe en $RG (se omite borrado)."
fi
```

### 5.2 Eliminar PostgreSQL Flexible Server

Este comando elimina el servidor y todas sus bases.

```bash
if az postgres flexible-server show --resource-group "$RG" --name "$PG_SERVER" --output none 2>/dev/null; then
  az postgres flexible-server delete \
    --resource-group "$RG" \
    --name "$PG_SERVER" \
    --yes
else
  echo "PostgreSQL $PG_SERVER no existe en $RG (se omite borrado)."
fi
```

### 5.3 Eliminar ACR

```bash
if az acr show --name "$ACR_NAME" --output none 2>/dev/null; then
  az acr delete \
    --resource-group "$RG" \
    --name "$ACR_NAME" \
    --yes
else
  echo "ACR $ACR_NAME no existe (se omite borrado)."
fi
```

## 6. Validacion post-eliminacion

```bash
az aks show --resource-group "$RG" --name "$AKS_NAME" --output table || true
az acr show --name "$ACR_NAME" --output table || true
az postgres flexible-server show --resource-group "$RG" --name "$PG_SERVER" --output table || true
```

Si fueron eliminados correctamente, los comandos anteriores deberian devolver error de recurso no encontrado.
