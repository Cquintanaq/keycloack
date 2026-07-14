# Guia completa: ACR + AKS desde cero (PowerShell)

## 1. Objetivo

Este documento cubre el flujo manual completo para:

1. Eliminar el cluster existente `aks-pre-cluster`.
2. Crear un cluster AKS nuevo con 2 nodos.
3. Subir la imagen de este repositorio a `rnikeycloakacr`.
4. Desplegar Keycloak en AKS.
5. Publicar cambios y actualizar el deployment.
6. Hacer rollback si es necesario.

## 2. Importante (operacion destructiva)

La eliminacion de `aks-pre-cluster` borra el cluster y su `node resource group` administrado.

Comando para revisar primero:

az aks show --resource-group RNI_CLU_AKS --name aks-pre-cluster --output table

Solo ejecuta la eliminacion cuando tengas respaldo de manifiestos, configuraciones y datos externos necesarios.

## 3. Prerrequisitos

- Docker Desktop instalado y funcionando.
- Azure CLI instalado.
- kubectl instalado.
- Permisos en Azure para:
  - ACR (push/pull)
  - AKS (create/delete/get-credentials/update)

## 4. Variables base (PowerShell)

$SUBSCRIPTION_ID="284d787d-673e-4653-830b-ff03e6abd764"
$RESOURCE_GROUP="RNI_CLU_AKS"
$LOCATION="chilecentral"
$AKS_OLD_NAME="aks-pre-cluster"
$AKS_NAME="aks-pre-cluster-v2"
$ACR_NAME="rnikeycloakacr"
$ACR_LOGIN_SERVER="rnikeycloakacr.azurecr.io"
$IMAGE_NAME="keycloak"
$IMAGE_TAG="v1"
$NAMESPACE="keycloak"
$DEPLOYMENT_NAME="keycloak"
$CONTAINER_NAME="keycloak"
$NODE_COUNT=2
$NODE_VM_SIZE="Standard_D2s_v5"

## 5. Login y seleccion de suscripcion

az login
az account set --subscription $SUBSCRIPTION_ID
az account show --output table

## 6. Verificar ACR objetivo

az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --output table
az acr repository list --name $ACR_NAME --output table

## 7. Eliminar cluster AKS anterior (desde cero)

### 7.1 Verificacion previa

az aks show --resource-group $RESOURCE_GROUP --name $AKS_OLD_NAME --output table

### 7.2 Eliminacion

az aks delete --resource-group $RESOURCE_GROUP --name $AKS_OLD_NAME --yes --no-wait

### 7.3 Esperar finalizacion

az aks wait --resource-group $RESOURCE_GROUP --name $AKS_OLD_NAME --deleted

## 8. Crear cluster AKS nuevo con 2 nodos

az aks create \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_NAME \
  --location $LOCATION \
  --node-count $NODE_COUNT \
  --node-vm-size $NODE_VM_SIZE \
  --enable-managed-identity \
  --generate-ssh-keys \
  --network-plugin azure \
  --tier free

Verificar creacion:

az aks show --resource-group $RESOURCE_GROUP --name $AKS_NAME --output table

## 9. Conectar AKS con ACR

Recomendado: habilitar pull sin secretos de docker-registry:

az aks update --resource-group $RESOURCE_GROUP --name $AKS_NAME --attach-acr $ACR_NAME

## 10. Construir y subir imagen a ACR

Desde la raiz de este repositorio:

docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}
az acr login --name $ACR_NAME
docker push ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}

Verificar tag:

az acr repository show-tags --name $ACR_NAME --repository $IMAGE_NAME --output table

## 11. Conectar kubectl al cluster nuevo

az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing
kubectl config current-context
kubectl get nodes

## 12. Desplegar Keycloak en AKS

### 12.1 Namespace

kubectl create namespace $NAMESPACE

Si ya existe, puedes ignorar el error.

### 12.2 Deployment

kubectl create deployment $DEPLOYMENT_NAME --image=${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG} -n $NAMESPACE
kubectl set env deployment/$DEPLOYMENT_NAME -n $NAMESPACE KC_HTTP_ENABLED=true
kubectl set env deployment/$DEPLOYMENT_NAME -n $NAMESPACE KC_PROXY_HEADERS=xforwarded

### 12.3 Exponer servicio

kubectl expose deployment $DEPLOYMENT_NAME --type=LoadBalancer --port=80 --target-port=8080 -n $NAMESPACE

### 12.4 Verificacion

kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE
kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE

## 13. Publicar cambios y actualizar deployment

Cada vez que cambies codigo o Dockerfile:

### 13.1 Generar nuevo tag y push

$IMAGE_TAG=(Get-Date -Format "yyyyMMdd-HHmm")
docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}
docker push ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}

### 13.2 Actualizar imagen en AKS

kubectl set image deployment/$DEPLOYMENT_NAME $CONTAINER_NAME=${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG} -n $NAMESPACE
kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE

### 13.3 Validacion

kubectl get pods -n $NAMESPACE -o wide
kubectl describe deployment $DEPLOYMENT_NAME -n $NAMESPACE

## 14. Rollback rapido

Si la ultima version falla:

kubectl rollout undo deployment/$DEPLOYMENT_NAME -n $NAMESPACE
kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE

## 15. Comandos utiles

Imagen activa en el deployment:

kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath="{.spec.template.spec.containers[0].image}"

Historial de rollout:

kubectl rollout history deployment/$DEPLOYMENT_NAME -n $NAMESPACE

Escalar replicas:

kubectl scale deployment/$DEPLOYMENT_NAME --replicas=2 -n $NAMESPACE

## 16. Troubleshooting

### 16.1 ImagePullBackOff

- Verifica que el tag exista en ACR.
- Verifica `attach-acr` entre AKS y ACR.
- Inspecciona eventos:

kubectl describe pod <POD_NAME> -n $NAMESPACE

### 16.2 Error SSL en Azure CLI (proxy corporativo)

Si aparece `CERTIFICATE_VERIFY_FAILED`, instala el certificado corporativo en el trust store del sistema o configura proxy/CA para Azure CLI.

### 16.3 Servicio sin respuesta

- Confirma que el contenedor escucha en puerto 8080.
- Revisa logs:

kubectl logs deployment/$DEPLOYMENT_NAME -n $NAMESPACE --tail=200

## 17. Recomendaciones de produccion

- No usar `latest`; usar tags versionados.
- Agregar `readinessProbe` y `livenessProbe`.
- Definir requests/limits de CPU y memoria.
- Externalizar secretos con Azure Key Vault + CSI Driver.
- Usar Ingress Controller o Application Gateway para TLS y ruteo.
- Automatizar pipeline con GitHub Actions o Azure DevOps.
