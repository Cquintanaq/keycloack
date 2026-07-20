# AKS + ACR desde cero en Azure Cloud Shell (Bash)

## 1. Objetivo

Flujo completo para construir todo desde cero usando la terminal web de Azure (Cloud Shell Bash):

1. Crear Resource Group.
2. Crear Azure Container Registry (ACR).
3. Clonar este repositorio en Cloud Shell.
4. Construir y subir imagen de Keycloak a ACR.
5. Crear AKS.
6. Crear PostgreSQL Flexible Server y base de datos.
7. Desplegar Keycloak en AKS usando la imagen del ACR.
8. Verificar despliegue.

## 2. Prerrequisitos

- Acceso a Azure Portal y Cloud Shell (Bash).
- Permisos para crear recursos en la suscripcion.
- Nombre de recursos disponibles globalmente para ACR y PostgreSQL.

## 3. Variables base

Ejecuta esto en Cloud Shell Bash y ajusta los valores.
No ejecutes `bash` antes de pegar el bloque; solo copia y pega directamente en la misma sesion de Cloud Shell.

Importante: en Cloud Shell interactivo, `!` puede romper comandos (`event not found`).
Por eso se desactiva `histexpand` al inicio:

```bash
set +H

export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-284d787d-673e-4653-830b-ff03e6abd764}"
export LOCATION="${LOCATION:-chilecentral}"
export RG="${RG:-RNI_CLU_AKS}"

# ACR
export ACR_NAME="${ACR_NAME:-rnikeycloakacr}"
export IMAGE_NAME="${IMAGE_NAME:-keycloak}"
export IMAGE_TAG="${IMAGE_TAG:-v1}"

# AKS
export AKS_NAME="${AKS_NAME:-keycloak-cluster}"
export NODE_COUNT="${NODE_COUNT:-2}"
export NODE_SIZE="${NODE_SIZE:-Standard_D2s_v5}"

# PostgreSQL Flexible Server
export PG_SERVER="${PG_SERVER:-keycloakpro-db}"
export PG_ADMIN_USER="${PG_ADMIN_USER:-kcadmin}"
export PG_ADMIN_PASS="${PG_ADMIN_PASS:-CambiaEstePasswordSeguro123}"
export PG_DB="${PG_DB:-keycloak}"

# Kubernetes
export NAMESPACE="${NAMESPACE:-keycloak}"
export DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-keycloak}"
export SERVICE_NAME="${SERVICE_NAME:-keycloak-svc}"
```

Validar que las variables quedaron cargadas:

```bash
set -euo pipefail

echo "SUBSCRIPTION_ID=$SUBSCRIPTION_ID"
echo "LOCATION=$LOCATION"
echo "RG=$RG"
echo "ACR_NAME=$ACR_NAME"
echo "AKS_NAME=$AKS_NAME"
echo "PG_SERVER=$PG_SERVER"
```

Nota segun tu salida real:

- AKS existente: `aks-RNI-cluster`
- ACR existente: `rniacr`
- Si quieres reutilizarlos, antes de continuar ajusta:

```bash
AKS_NAME="aks-RNI-cluster"
ACR_NAME="rniacr"
```

## 4. Login y contexto

```bash
az login --tenant c500e2eb-ab3a-4d3d-9573-15c62a700b75
az account set --subscription "$SUBSCRIPTION_ID"
az account show --output table
```

Chequeo rapido de permisos (si falla con `AuthorizationFailed`, debes pedir rol `Contributor` o superior sobre el Resource Group `RNI_CLU_AKS`):

```bash
az group show --name "$RG" --output table
az aks list --resource-group "$RG" --output table
az acr list --resource-group "$RG" --output table
az postgres flexible-server list --resource-group "$RG" --output table
```

## 5. Crear Resource Group

```bash
az group create \
  --name "$RG" \
  --location "$LOCATION"
```

## 6. Crear ACR

Si ya existe, este comando fallara. En ese caso usa el existente.

```bash
az acr create \
  --resource-group "$RG" \
  --name "$ACR_NAME" \
  --sku Basic \
  --admin-enabled false
```

Obtener login server:

```bash
ACR_LOGIN_SERVER=$(az acr show --name "$ACR_NAME" --resource-group "$RG" --query loginServer -o tsv)
echo "$ACR_LOGIN_SERVER"
```

## 7. Usar este repositorio como contexto de build

Si ya tienes este repositorio en tu Cloud Shell, solo entra a la carpeta y verifica que exista `Dockerfile`:

```bash
cd ~/keycloack
ls -la
```

Si el repo esta en otra ruta, usa esa ruta en lugar de `~/keycloack`.

Si todavia no lo tienes en Cloud Shell, recien ahi clona:

```bash
git clone https://github.com/Cquintanaq/keycloack.git
cd keycloack
```

Opcional (si quieres construir desde cambios no publicados en GitHub):

- Comprime el repositorio local y subelo a Cloud Shell.
- Descomprime y usa esa carpeta como contexto del `az acr build`.

## 8. Construir y subir imagen a ACR

Opcion recomendada en Cloud Shell: construir en ACR con ACR Tasks.

```bash
az acr build \
  --registry "$ACR_NAME" \
  --image "$IMAGE_NAME:$IMAGE_TAG" \
  .
```

Si ejecutas desde PowerShell (Windows), usa esta variante para evitar el error con `:`:

```powershell
az acr build --registry $ACR_NAME --image "${IMAGE_NAME}:$IMAGE_TAG" .
```

Validar imagen/tag:

```bash
az acr repository list --name "$ACR_NAME" --output table
az acr repository show-tags --name "$ACR_NAME" --repository "$IMAGE_NAME" --output table
```

## 9. Crear AKS con 2 nodos

```bash
az aks create \
  --resource-group "$RG" \
  --name "$AKS_NAME" \
  --location "$LOCATION" \
  --node-count "$NODE_COUNT" \
  --node-vm-size "$NODE_SIZE" \
  --enable-managed-identity \
  --network-plugin azure \
  --tier free \
  --generate-ssh-keys
```

Adjuntar ACR a AKS para pull de imagen sin secretos:

```bash
az aks update \
  --resource-group "$RG" \
  --name "$AKS_NAME" \
  --attach-acr "$ACR_NAME"
```

Credenciales kubectl:

```bash
az aks get-credentials \
  --resource-group "$RG" \
  --name "$AKS_NAME" \
  --overwrite-existing

kubectl get nodes
```

## 10. Crear PostgreSQL Flexible Server y base

Crear servidor:

```bash
az postgres flexible-server create \
  --resource-group "$RG" \
  --name "$PG_SERVER" \
  --location "$LOCATION" \
  --admin-user "$PG_ADMIN_USER" \
  --admin-password "$PG_ADMIN_PASS" \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --version 16 \
  --storage-size 32 \
  --public-access 0.0.0.0
```

Crear base:

```bash
az postgres flexible-server db create \
  --resource-group "$RG" \
  --server-name "$PG_SERVER" \
  --database-name "$PG_DB"
```

Obtener FQDN:

```bash
PG_HOST=$(az postgres flexible-server show --resource-group "$RG" --name "$PG_SERVER" --query fullyQualifiedDomainName -o tsv)
echo "$PG_HOST"
```

## 11. Desplegar Keycloak en AKS

Crear namespace:

```bash
kubectl create namespace "$NAMESPACE" || true
```

Crear secreto con credenciales DB:

```bash
kubectl -n "$NAMESPACE" create secret generic keycloak-db-secret \
  --from-literal=KC_DB_USERNAME="$PG_ADMIN_USER" \
  --from-literal=KC_DB_PASSWORD="$PG_ADMIN_PASS"
```

Aplicar deployment + service:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${DEPLOYMENT_NAME}
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
        - name: keycloak
          image: ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}
          imagePullPolicy: Always
          args: ["start", "--optimized"]
          ports:
            - containerPort: 8080
          env:
            - name: KC_DB
              value: postgres
            - name: KC_DB_URL
              value: jdbc:postgresql://${PG_HOST}:5432/${PG_DB}
            - name: KC_DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: keycloak-db-secret
                  key: KC_DB_USERNAME
            - name: KC_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-db-secret
                  key: KC_DB_PASSWORD
            - name: KC_HTTP_ENABLED
              value: "true"
            - name: KC_PROXY_HEADERS
              value: xforwarded
            - name: KC_BOOTSTRAP_ADMIN_USERNAME
              value: admin
            - name: KC_BOOTSTRAP_ADMIN_PASSWORD
              value: CambiaEsteAdminPass123!
---
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE_NAME}
  namespace: ${NAMESPACE}
spec:
  type: LoadBalancer
  selector:
    app: keycloak
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
EOF
```

## 12. Verificacion del despliegue

```bash
kubectl get pods -n "$NAMESPACE"
kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"
kubectl get svc -n "$NAMESPACE"
```

Obtener IP publica:

```bash
kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo
```

## 13. Actualizar imagen y redeploy

Desde la carpeta del repo en Cloud Shell:

```bash
IMAGE_TAG="v2"
az acr build --registry "$ACR_NAME" --image "$IMAGE_NAME:$IMAGE_TAG" .

kubectl set image deployment/"$DEPLOYMENT_NAME" \
  keycloak="${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" \
  -n "$NAMESPACE"

kubectl rollout status deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"
```
