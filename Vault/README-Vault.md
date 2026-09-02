# Vault — Guía de Operación

HashiCorp Vault gestiona los secretos de RNI 2.0. Cada cluster tiene su propio Vault interno.
Acceso exclusivo via VPN + kubectl. Nunca expuesto a internet.

## Estado de implementación

| Fase | Descripción | Estado |
|------|-------------|--------|
| Fase 1 — Despliegue | Vault instalado, inicializado y operativo en `worker-dev` (namespace `dev-sprint-1`) | ✅ Completo |
| Fase 2 — Carga de secretos | Todos los paths de DEV cargados en Vault | ✅ Completo |
| Fase 3 — Vault Agent Injector | 13 deployments .NET/Redis + los 3 brokers RabbitMQ (`rabbit-general-backend`, `rabbit-notifications`, `rabbit-security`) migrados y validados corriendo en `worker-dev` | ✅ Completo (DEV) |
| Fase 4 — Reporting (nuevo servicio) | `reporting-sa`/`reporting-role` cargados, `postgresql/reporting` en Vault, imagen aún no construida por pipeline | 🟡 Vault listo, falta imagen |
| QA — Fase 1 | Vault instalado, inicializado y sin sellar en `worker-qa` (namespace `vault`) | ✅ Completo |
| QA — Fase 2 | Secretos cargados en `secret/rni/qa/...` (ver `load-secrets-qa.sh`, gitignored) — 15 roles `kubernetes-qa` creados, ServiceAccounts aplicados en `qa-sprint-1` | ✅ Completo |
| QA — Fase 3 | Vault Agent Injector — ningún pod de `qa-sprint-1` tiene el sidecar todavía (los 23 pods activos siguen `1/1`, sin Vault) | ⏳ Pendiente — deliberado, ver nota abajo |

> **Namespace real:** el pipeline (`azure-pipelines.yml`) despliega DEV por defecto a **`dev-sprint-1`**, no `dev-master`. Todo este documento asume `dev-sprint-1`. Ver sección "Namespace real vs `dev-master`" más abajo.

---

## Ambientes

| Ambiente | Cluster | Namespace real | Kubeconfig | Paths de secretos |
|----------|---------|-----------------|------------|-------------------|
| Desarrollo | worker-dev | `dev-sprint-1` | `worker-dev.yaml` | `rni/dev/...` |
| QA | worker-qa | `qa-sprint-1` | `worker-qa.yaml` | `rni/qa/...` |
| PRE | worker-pre | — | `worker-pre.yaml` | `rni/pre/...` |
| Producción | worker-prod | — | `worker-prod.yaml` | `rni/prod/...` |

En todos los pasos reemplazar `<kubeconfig>` y `<ambiente>` según la tabla anterior.

### Namespace real vs `dev-master`

`azure-pipelines.yml` define el parámetro `DEV_NAMESPACE` con **default `dev-sprint-1`** (valores posibles: `dev-master`, `dev-sprint-1`). Todo el trabajo de Vault de este documento se hizo y validó en `dev-sprint-1`, que es donde corren realmente los pods hoy. `dev-master` existe como namespace pero está vacío — no lo uses como referencia.

Mismo patrón en QA: `QA_NAMESPACE` default es `qa-sprint-1` (no `qa-master`).

### Estado real de QA (corrige suposiciones previas de este documento)

Al preparar la migración de QA se descubrió que Vault en `worker-qa` **ya estaba desplegado e inicializado** (33 días de uptime) — la fila anterior de este documento que decía "sin inicializar" estaba desactualizada. Lo que sí faltaba (Fase 2 y 3) se completó así:

- **Se perdió el acceso original**: no había root token ni unseal keys de QA guardados en ningún lado accesible. Como Vault QA no tenía ningún secreto cargado todavía (Fase 2/3 nunca se habían hecho), se decidió reinicializar desde cero: `kubectl scale statefulset vault -n vault --replicas=0`, borrar el PVC `data-vault-0`, escalar de vuelta a 1, `vault operator init`, unseal con 3 de las 5 keys nuevas. **El output nuevo (unseal keys + root token) se guardó en `D:\...\Config Cluster\vault-qa-init-output.json`** — cuidarlo igual que el de dev.
- **Hallazgo colateral importante**: al recrear el PVC se descubrió que el `local-path-provisioner` del cluster `worker-qa` **no existía** (el `Deployment` fue borrado en algún momento, dejando huérfanos el ConfigMap y el RBAC) — por eso el PVC nuevo no bindeaba. Se recreó el `Deployment` reutilizando el ServiceAccount/ClusterRole/ClusterRoleBinding/ConfigMap ya existentes (imagen `rancher/local-path-provisioner:v0.0.30`). Esto afecta a *todo* el cluster QA (cualquier PVC nuevo), no solo a Vault — vale la pena que operaciones lo tenga presente para no perderlo de nuevo.
- **Secretos**: `Deployment/Cluster/Manifiestos/vault/load-secrets-qa.sh` (nuevo, gitignored) — mismos paths/claves que `load-secrets-dev.sh`, valores reales extraídos de los 27 `Secret` de Kubernetes en texto plano de `qa-sprint-1`. Igual que en dev, quedaron varios `TODO` sin resolver (Keycloak client secrets, MINSAL, OPA, AzureMonitor, y las passwords `${RABBIT_CONSUMER_PASS}`/`${RABBIT_PRODUCER_PASS}` de audit-consumer/producer que nunca se sustituyeron en QA tampoco).
- **Policies**: las 17 que aplican a QA (todas menos `reporting-policy` y `rabbit-audit-policy`, ninguno de los dos desplegado ahí) se cargaron sustituyendo `rni/dev/`→`rni/qa/` y `kubernetes-dev`→`kubernetes-qa` al momento de escribirlas — el `.hcl` fuente sigue apuntando a `dev`, el ambiente se resuelve al cargar, no en el archivo.
- **Roles y ServiceAccounts**: `vault/auth/enable-k8s-qa.sh` tenía el mismo bug que `enable-k8s-dev.sh` (asumía namespaces `qa-backend`/`qa-security` que no existen) — corregido a `qa-sprint-1`. Se crearon los 15 roles (8 microservicios + gateway + 3 redis + 3 rabbit) y sus ServiceAccounts correspondientes.
- **Gap de repo encontrado (afecta a dev y QA por igual)**: `rabbit-general-backend-sa` y `redis-security-sa` nunca estuvieron definidos en `backend/service-accounts.yml`/`security/service-accounts.yml` — se crearon manualmente en dev en su momento sin comitear. Ya se agregaron a ambos archivos.
- **Deliberadamente NO se tocó**: ningún pod de `qa-sprint-1` fue reiniciado ni sus manifiestos de Deployment recibieron las anotaciones de Vault Agent — eso es Fase 3 y queda para cuando se decida coordinar el corte junto con un despliegue real vía pipeline (los manifiestos de servicio ya son compatibles tal cual gracias a `configurador.py` — no hace falta tocarlos por separado para QA).
- **`rabbit-audit-server-0` sigue corriendo en QA** (a diferencia de dev, donde se confirmó que estaba huérfano y se eliminó) — no se tocó porque no se confirmó si algo lo usa ahí; queda pendiente esa verificación antes de replicar la limpieza de dev.

---

## Requisitos previos

- VPN corporativa activa
- kubectl instalado (`kubectl version --client`)
- Kubeconfig del cluster descargado desde Rancher (ver `Deployment/Cluster/Manifiestos` para los `.yaml` ya guardados si aplica)
- Helm 3 instalado si vas a regenerar `vault-*-all.yaml` con `render.sh`

### Descargar kubeconfig desde Rancher

1. Abrir `https://rancher-dev.saludenred.cl` (o `rancher-qa...` para QA)
2. Click en el cluster destino
3. Botón **Download KubeConfig** (arriba a la derecha)
4. Guardar el archivo en tu máquina — el token expira, si un comando devuelve `system:unauthenticated` o 403, vuelve a descargarlo

---

## Fase 1 — Despliegue e instalación (nuevo cluster)

### Paso 1 — Generar y aplicar el manifiesto de Vault

```bash
cd Deployment/Cluster/Manifiestos/vault
./render.sh                                   # genera vault-all.yaml (requiere helm)
kubectl --context=<contexto> apply -f vault-dev-all.yaml   # o vault-qa-all.yaml
kubectl --context=<contexto> get pods -n vault
```

El pod `vault-0` arranca en estado `0/1 Running` — esto es normal. Vault está en pie pero sellado.

### Paso 2 — Inicializar Vault (una sola vez por cluster)

```bash
./init.sh
```

Genera `vault-init-output.json` con las 5 unseal keys y el root token (esquema Shamir 5/3 — el Vault de `worker-dev` actual usa 1/1 porque se inicializó manualmente antes de existir este script; no lo reinicialices).

**Guardar inmediatamente en el gestor corporativo y borrar el archivo local: `rm vault-init-output.json`.**

### Paso 3 — Habilitar KV v2 y audit log

Si `init.sh` no lo hizo (o Vault ya estaba inicializado manualmente):

```bash
export VAULT_TOKEN=<root-token>
kubectl --context=<contexto> exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault secrets enable -path=secret kv-v2
kubectl --context=<contexto> exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault audit enable file file_path=/vault/logs/audit.log
```

> En Git Bash / MSYS (Windows), antepone `export MSYS_NO_PATHCONV=1` a comandos que usan rutas Unix como argumento (`/vault/logs/...`, `secret/rni/...`) — si no, MSYS las convierte a rutas de Windows y el comando falla.

### Paso 4 — Cargar policies

```bash
cd Deployment/Cluster/Manifiestos/vault
export VAULT_TOKEN=<root-token>
export MSYS_NO_PATHCONV=1
for f in policies/*.hcl; do
  name=$(basename "$f" .hcl)
  kubectl --context=<contexto> exec -n vault -i vault-0 -- sh -c "cat > /tmp/${name}.hcl" < "$f"
  kubectl --context=<contexto> exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault policy write "$name" "/tmp/${name}.hcl"
done
```

### Paso 5 — Habilitar auth Kubernetes

El chart de Vault ya crea un ServiceAccount propio (`vault` en el namespace `vault`) con el `ClusterRoleBinding` `system:auth-delegator` necesario — **no hace falta crear un SA `vault-reviewer` aparte**. Ejecuta esto dentro del propio pod `vault-0`, usando su token de servicio:

```bash
export VAULT_TOKEN=<root-token>
kubectl --context=<contexto> exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault auth enable -path=kubernetes-dev kubernetes
kubectl --context=<contexto> exec -n vault vault-0 -- sh -c '
  vault write auth/kubernetes-dev/config \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
'
```

Para QA, usar `-path=kubernetes-qa` y `auth/kubernetes-qa/config`.

`Manifiestos/vault/auth/enable-k8s-dev.sh` existe como referencia histórica pero asume namespaces `dev-backend`/`dev-security` que **no existen** en el cluster real — no ejecutarlo tal cual. Los roles reales se crean en el Paso 6.

### Paso 6 — Crear roles (uno por ServiceAccount)

```bash
export VAULT_TOKEN=<root-token>
NS=dev-sprint-1   # o qa-sprint-1

# Ejemplo — repetir por cada rol de la tabla "Políticas ACL" más abajo
kubectl --context=<contexto> exec -n vault vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault write auth/kubernetes-dev/role/patient-role \
  bound_service_account_names=patient-sa \
  bound_service_account_namespaces="$NS" \
  policies=patient-policy \
  ttl=1h
```

---

## Fase 2 — Carga de secretos

### Opción A — Script automatizado

`load-secrets-dev.sh` está en `.gitignore` — nunca se commitea con valores reales. Rellena los TODO y ejecútalo:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=<root-token>
bash Manifiestos/vault/load-secrets-dev.sh
```

### Opción B — `vault kv put` / `vault kv patch` directo

Usa `vault kv put` para crear/reemplazar un secreto completo, y `vault kv patch` para agregar campos sin perder los existentes. Ver "Mapa de paths" abajo para los paths y claves reales.

### Checklist de carga (DEV) — ya completo en `worker-dev`

- [x] `rni/dev/postgresql/{patient,organization,practitioner,vaccination,notifications,versionmanager,audit}`
- [x] `rni/dev/rabbitmq/{backend,security,notifications-infra}`
- [x] `rni/dev/redis/{security,notifications,versionmanager}`
- [x] `rni/dev/keycloak/clients/gateway`
- [x] `rni/dev/minsal/empi`
- [ ] `rni/dev/opa/auth` — policy existe, secreto no cargado (OPA no consume secretos hoy, ver nota en Políticas ACL)

### Checklist de carga (QA) — completo, ver "Estado real de QA" arriba

- [x] `rni/qa/postgresql/{patient,organization,practitioner,vaccination,notifications,versionmanager,audit}`
- [x] `rni/qa/rabbitmq/{backend,security,notifications-infra}`
- [x] `rni/qa/redis/{security,notifications,versionmanager}`
- [x] `rni/qa/keycloak/clients/{organization,gateway}`
- [x] `rni/qa/minsal/empi`
- [x] `rni/qa/azure/monitor`
- [x] `rni/qa/opa/auth`

Script: `Deployment/Cluster/Manifiestos/vault/load-secrets-qa.sh` (gitignored, no commitear). Varios campos quedaron con `TODO` real (ver nota arriba) — cargados como placeholder hasta tener el valor real del equipo.

---

## Fase 3 — Vault Agent Injector

### Patrón usado (todos los servicios .NET/Java)

Cada Deployment usa **una sola plantilla renderizada como archivo de variables de entorno** (no JSON), inyectada por el Vault Agent en `/vault/secrets/config`, y el contenedor la carga sobreescribiendo su `command`:

```yaml
annotations:
  vault.hashicorp.com/agent-inject: "true"
  vault.hashicorp.com/role: "patient-role"
  vault.hashicorp.com/auth-path: "auth/kubernetes-dev"
  vault.hashicorp.com/agent-limits-cpu: "50m"      # sidecar liviano — el cluster dev tiene poco margen de CPU
  vault.hashicorp.com/agent-limits-mem: "64Mi"
  vault.hashicorp.com/agent-requests-cpu: "10m"
  vault.hashicorp.com/agent-requests-mem: "32Mi"
  vault.hashicorp.com/agent-inject-secret-config: "secret/data/rni/dev/postgresql/patient"
  vault.hashicorp.com/agent-inject-template-config: |
    {{ with secret "secret/data/rni/dev/postgresql/patient" }}
    export ConnectionStrings__ReadWriteConnection="{{ .Data.data.ConnectionStrings__ReadWriteConnection }}"
    {{ end }}
spec:
  containers:
  - name: patient
    command: ["sh", "-c"]
    args: ["set -a; . /vault/secrets/config; exec dotnet Patient.API.dll"]
```

**Por qué no JSON + volumeMount manual:** los manifiestos originales usaban `agent-inject-file-config: appsettings.Production.json` montado sobre el archivo de config de la app. Se descartó porque: (1) requiere que la app soporte overlay de `appsettings.Production.json`, cosa no verificada; (2) con múltiples `with secret` en un mismo template hay que tener cuidado con `{{- -}}` (trim) — comerse el salto de línea entre bloques concatena la línea anterior con `export` de la siguiente, corrompiendo el primer valor. Usa `{{ with ... }}` (sin guion) entre bloques distintos, `{{- with ... -}}` solo si es el único bloque.

**Redis** usa el mismo patrón pero el `command` invoca `redis-server` con `--requirepass "$REDIS_PASSWORD"` en vez de `dotnet`:

```yaml
args: ["set -a; . /vault/secrets/config; exec redis-server /etc/redis/redis.conf --requirepass \"$REDIS_PASSWORD\""]
```

El `redis.conf` montado desde ConfigMap trae `requirepass ${REDIS_PASSWORD}` sin resolver — es intencional, el valor real llega por `--requirepass` en el arranque y ese literal en el archivo queda inerte.

### Paso 1 — Aplicar ServiceAccounts

```bash
kubectl apply -f Manifiestos/backend/service-accounts.yml
kubectl apply -f Manifiestos/backend/service-accounts-sprint1.yml
kubectl apply -f Manifiestos/security/service-accounts.yml
```

### Paso 2 — Regenerar y aplicar el manifiesto unificado

```bash
cd Manifiestos/
python configurador.py --namespace dev-sprint-1 --versions version/dev-sprint-1.yml
kubectl apply -f dev-sprint-1-all.yml
```

Para QA: `--namespace qa-sprint-1 --versions version/qa-sprint-1.yml`. `configurador.py` ahora reescribe automáticamente las rutas `secret/rni/dev/...` y `auth/kubernetes-dev` al ambiente destino (`vault_env` en el archivo de versiones) — no hace falta editar los manifiestos a mano por ambiente.

### Paso 3 — Verificar inyección

```bash
NS=dev-sprint-1
POD=$(kubectl get pod -n $NS -l app=miniservice-patient -o jsonpath='{.items[0].metadata.name}')

# Log del init container — debe mostrar "rendered ... => /vault/secrets/config"
kubectl -n $NS logs "$POD" -c vault-agent-init

# Contenido real inyectado
export MSYS_NO_PATHCONV=1   # Windows/Git Bash
kubectl -n $NS exec "$POD" -c patient -- cat /vault/secrets/config

# La app arrancó con esos valores
kubectl -n $NS logs "$POD" -c patient --tail=30
```

### ServiceAccounts por namespace (real, `worker-dev`)

Todos en **`dev-sprint-1`** — no existen namespaces separados `dev-backend`/`dev-security` en el cluster real:

| ServiceAccount | Rol Vault | Usado por |
|----------------|-----------|-----------|
| `patient-sa` | `patient-role` | miniservice-patient |
| `organization-sa` | `organization-role` | miniservice-organization |
| `practitioner-sa` | `practitioner-role` | miniservice-practitioner |
| `vaccination-sa` | `vaccination-role` | miniservice-vaccination |
| `notifications-sa` | `notifications-role` | miniservice-notifications |
| `integrations-sa` | `integrations-role` | miniservice-integrations |
| `versionmanager-sa` | `versionmanager-role` | miniservice-versionmanager |
| `audit-sa` | `audit-role` | audit-consumer, audit-producer (comparten SA y policy) |
| `reporting-sa` | `reporting-role` | miniservice-reporting, reporting-worker (comparten SA y policy, mismo patrón que audit) |
| `gateway-sa` | `gateway-role` | apigateway-deployment |
| `opa-sa` | `opa-role` | reservado — OPA hoy no consume secretos |
| `redis-notifications-sa` | `redis-notifications-role` | redis-notifications-deploy |
| `redis-security-sa` | `redis-security-role` | redis-security-deploy |
| `redis-versionmanager-sa` | `redis-versionmanager-role` | redis-versionmanager-deploy |
| `rabbit-general-backend-sa` (+ `rabbit-general-backend-server` del Operator) | `rabbit-general-backend-role` | rabbit-general-backend-server-0 |
| `rabbit-notifications-sa` (+ `rabbit-notifications-server` del Operator) | `rabbit-notifications-role` | rabbit-notifications-server-0 |
| `rabbit-security-sa` (+ `rabbit-security-server` del Operator) | `rabbit-security-role` | rabbit-security-server-0 |

Los brokers RabbitMQ (`rabbit-general-backend-server-0`, `rabbit-notifications-server-0`, `rabbit-security-server-0`) **ya migraron a Vault** (antes no leían su admin password desde ahí). Usan una mezcla: el `override.statefulSet.spec.template.spec.serviceAccountName` que sí se puede fijar en el manifiesto (`rabbit-general-backend-sa`, etc., definidos en `backend/service-accounts.yml` y `security/service-accounts.yml`), **pero el Operator también genera su propio SA por defecto** (`<nombre>-server`) y a veces sigue usándolo — por eso los roles de Vault de estos 3 brokers están vinculados a **ambos** nombres de SA (ver gotcha abajo).

### ⚠️ Gotcha crítico — RabbitmqCluster Operator vs Vault Agent Injector

El Vault Agent Injector es un **mutating webhook que solo intercepta la creación de Pods** (`apiGroups: [""], resources: ["pods"]` en `vault-agent-injector-cfg`). El `RabbitmqCluster` (CRD `rabbitmq.com/v1beta1`) no crea Pods directamente: el **RabbitMQ Cluster Operator** construye y envía él mismo el `StatefulSet` (`apps/v1`) subyacente, y esa creación **no pasa por el webhook de Pods** de la misma manera — el resultado observado es que declarar explícitamente un `volumeMounts` apuntando a un volumen `vault-secrets` en `override.statefulSet` falla la validación de la API de Kubernetes (`volumeMounts[2].name: Not found: "vault-secrets"`), porque ese volumen lo crea el injector en tiempo de mutación del Pod, no existe todavía cuando el Operator arma el StatefulSet.

**Síntomas si esto pasa:** `kubectl apply` del `RabbitmqCluster` falla con ese error de validación, o si ya estaba aplicado y solo cambias el `load_definitions`, el Operator **elimina el pod actual para el rolling update y falla al recrearlo** (outage real, nos pasó en vivo con `rabbit-general-backend`).

**Fix aplicado (los 3 brokers):**
1. Usar el path por defecto del injector: `load_definitions = /vault/secrets/definitions.json` (no una ruta/nombre de archivo custom que obligue a declarar `volumeMounts` a mano).
2. **No declarar `volumeMounts` explícito** para `vault-secrets` en `override.statefulSet` — dejar que el injector lo agregue en tiempo de mutación del Pod. El único override necesario en `containers` es `- name: rabbitmq` (vacío), porque el CRD exige que la clave `containers` exista si hay `override.statefulSet.spec.template.spec`.
3. Verificar que `serviceAccountName` en el override apunte a un SA que **exista de verdad** (aplicar `service-accounts.yml` primero) — si no existe, el pod queda en error `serviceaccount "X" not found`.
4. El **rol de Vault** (`vault write auth/kubernetes-dev/role/<broker>-role bound_service_account_names=...`) debe incluir **tanto** el SA custom del manifiesto **como** el SA que el Operator genera por defecto (`<nombre>-server`), separados por coma — en la práctica el pod terminó autenticándose con uno u otro según el momento del rolling update:
   ```bash
   vault write auth/kubernetes-dev/role/rabbit-general-backend-role \
     bound_service_account_names="rabbit-general-backend-sa,rabbit-general-backend-server" \
     bound_service_account_namespaces="dev-sprint-1" \
     policies="rabbit-general-backend-policy" ttl=1h
   ```
5. **No usar** `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS_FILE` como env vars del contenedor `rabbitmq` — la imagen rechaza `_FILE` como deprecado (`error: RABBITMQ_DEFAULT_PASS_FILE is set but deprecated`) y además el Operator **ya genera su propio secreto `default_user.conf`** con credenciales aleatorias como mecanismo de bootstrap real; esas env vars son redundantes y rompen el arranque.
6. Al reintentar tras cualquiera de estos fixes, siempre `kubectl delete pod <broker>-server-0` (StatefulSet de 1 réplica) para forzar que el Operator lo recree con la config nueva — no hay hot-reload de `load_definitions`.

**Antes de tocar cualquier `rabbit-*.yml` en producción/QA:** aplica este mismo checklist en orden (SA → rol Vault con ambos nombres → sin volumeMounts custom → sin env vars deprecadas) para evitar el mismo outage que tuvimos en dev.

---

## Mapa de paths (real, verificado en `worker-dev`)

```
secret/rni/dev/
├── postgresql/
│   ├── patient          ConnectionStrings__ReadWriteConnection, ConnectionStrings__ReadOnlyConnection, DB_PASSWORD
│   ├── organization     ConnectionStrings__ReadWriteConnection, ConnectionStrings__ReadOnlyConnection,
│   │                    Keycloak__ClientSecret, AzureMonitor__ConnectionString
│   ├── practitioner     DB_PASSWORD
│   ├── vaccination      ConnectionStrings__ReadWriteConnection, ConnectionStrings__ReadOnlyConnection
│   ├── notifications    NotificationsDb, JWT_ALGORITHM, KEYCLOAK_ISSUER,
│   │                    RABBITMQ_HOST, RABBITMQ_PASS, RABBITMQ_PORT, RABBITMQ_USER, REDIS_HOST, REDIS_PORT
│   ├── versionmanager   ConnectionStrings__VersionesDb, database-connection
│   ├── audit            consumer_primary, consumer_replica, consumer_analytics,
│   │                    consumer_broker_host, consumer_broker_user, consumer_broker_password,
│   │                    producer_listener_0/1/2, producer_broker_host, producer_broker_user, producer_broker_password
│   │                    (⚠️ consumer_* apuntan a bd_practitioner_audit con password ${DEMO_DB_PASS} sin resolver — ver Pendientes)
│   └── reporting        ConnectionStrings__ReportingDb, ConnectionStrings__VaccinationRead
│                        (⚠️ VaccinationRead reutiliza la credencial compartida rni-miniservicios — falta el rol de solo lectura real)
├── rabbitmq/
│   ├── backend            admin_password, admin_user, organization_user, organization_password,
│   │                      patient_user, patient_password, vaccination_password,
│   │                      audit_consumer_password, audit_producer_password,
│   │                      reporting_user, reporting_password
│   ├── security           admin_password, admin_user, erlang_cookie, apigateway_password
│   └── notifications-infra admin_password, admin_user, erlang_cookie,
│                          notifications_service_password, email_service_password,
│                          sms_service_password, monitoring_user_password
├── keycloak/
│   └── clients/
│       └── gateway        JwtSecret, ClientSecret
├── redis/
│   ├── security           Password, REDIS_PASSWORD, REDIS_USER
│   ├── notifications       REDIS_PASSWORD, REDIS_USER
│   └── versionmanager      REDIS_PASSWORD, REDIS_USER
└── minsal/
    └── empi               ClientId, ClientSecret   (vacíos — MINSAL aún no integrado)
```

> `organization-policy` e `integrations-policy` en `Deployment/Cluster/Manifiestos/vault/policies/` se ajustaron hoy para dar acceso a `rabbitmq/backend` y `minsal/empi` respectivamente — antes apuntaban a paths que no coincidían con lo que el código realmente lee.

---

## Políticas ACL

| Política | Paths que autoriza |
|----------|--------------------|
| `patient-policy` | `postgresql/patient`, `rabbitmq/backend` |
| `organization-policy` | `postgresql/organization`, `rabbitmq/backend` |
| `practitioner-policy` | `postgresql/practitioner` |
| `vaccination-policy` | `postgresql/vaccination` |
| `notifications-policy` | `postgresql/notifications` |
| `integrations-policy` | `postgresql/integrations` (sin uso hoy), `minsal/empi` |
| `audit-policy` | `postgresql/audit`, `rabbitmq/backend`, `azure/monitor` |
| `reporting-policy` | `postgresql/reporting`, `rabbitmq/backend` |
| `versionmanager-policy` | `postgresql/versionmanager` |
| `gateway-policy` | `keycloak/clients/gateway`, `rabbitmq/security`, `redis/security`, `azure/monitor` |
| `rabbit-general-backend-policy` | `rabbitmq/backend` — **aplicada**, broker en vivo la usa |
| `rabbit-notifications-policy` | `rabbitmq/notifications-infra` — **aplicada**, broker en vivo la usa |
| `rabbit-security-policy` | `rabbitmq/security` — **aplicada**, broker en vivo la usa |
| `redis-notifications-policy` | `redis/notifications` |
| `redis-versionmanager-policy` | `redis/versionmanager` |
| `redis-security-policy` | `redis/security` |
| `opa-policy` | `opa/auth` (no aplicada — OPA no consume secretos hoy) |
| `pipeline-policy` | acceso de pipeline CI/CD |

---

## Pendientes conocidos (no bloquean DEV, sí antes de PROD)

1. **`audit-consumer` no puede persistir eventos**: la base `bd_practitioner_audit` (nombre real esperado por el código, `AuditDatabasesOptions`) **no existe en el Postgres compartido (`172.16.1.85`)** — se confirmó consultando `pg_database` directamente: las únicas 8 bases reales ahí son `notifications_write`, `organizationdb_write`, `patientdb_write`, `practitionerdb_write`, `reportingdb`, `vaccinationdb_write`, `versioning`, `postgres`. Además el password de esa conexión en Vault (`consumer_primary`/`consumer_replica`/`consumer_analytics`) sigue siendo el placeholder literal `${DEMO_DB_PASS}` sin resolver — el bus de RabbitMQ conecta bien (ya corregido esta sesión), pero `audit-consumer` falla en cada escritura con `Npgsql.NpgsqlException: No password has been provided`. Requiere confirmar con el equipo dónde vive realmente esta base (o crearla, mismo patrón que se usó para `reportingdb`) y cuál es la password real — decisión de negocio/DBA pendiente.
2. **Secretos con valor placeholder, no reales**: `Keycloak__ClientSecret` (organization, gateway), `Jwt__Secret` (gateway) — están cargados en Vault tal cual estaban en los `Secret` de K8s originales (valores de ejemplo, no credenciales reales de Keycloak). Login/JWT en esos flujos no funcionará hasta reemplazarlos. `AzureMonitor__ConnectionString` de organization sí es un valor real en el K8s Secret original, pero queda redactado en cualquier lectura automatizada — cópialo directo desde la UI de Rancher (Secret `miniservice-organization-secrets`) al cargarlo en Vault.
3. **Password de Redis compartida**: los 3 Redis (`security`, `notifications`, `versionmanager`) usan la misma contraseña (`redis_strong_pass_2026`). Funciona pero no sigue el principio de mínimo privilegio — cada instancia debería tener su propia clave.
4. **Vault de `worker-dev` en Shamir 1/1**: sin alta disponibilidad de unseal (una sola clave). Suficiente para dev, no para producción.
5. **QA sin inicializar**: `vault-qa-all.yaml` existe pero Vault de `worker-qa` no se ha desplegado/inicializado. `configurador.py` ya soporta generar el manifiesto de QA con las rutas de Vault correctas (`vault_env: qa` en `version/qa-*.yml`) — falta repetir Fases 1–3 en ese cluster.
6. **Código con vhost de RabbitMQ hardcodeado**: `Patient.API` y `Organization.API` (`Program.cs`) ignoraban `MessageBroker:VirtualHost` (hardcodeaban `"/"`, pero el vhost real del broker es `/audit`). Ya corregido en el código fuente — pendiente de bump de versión + build del pipeline para que tome efecto en la imagen desplegada.
7. **`ConnectionStrings__VaccinationRead` de Reporting usa la credencial compartida `rni-miniservicios`** (lectura/escritura), no un rol de solo lectura real — funciona porque ya tiene acceso, pero no es el usuario correcto a largo plazo. Requiere crear un rol de Postgres de solo lectura sobre `vaccinationdb_write` antes de QA/prod.
8. **Drift de schema entre el repo y la base viva de dev** (hallado en la revisión sprint_7 de Cesar): `Vaccination` tiene el gap más grande — falta la tabla `imh_immunization_hot` (las funciones que ya la referencian están rotas en runtime) y el schema `outbox` completo (sin triggers de auditoría en ~30 tablas de vacunación). Script de cierre generado en `Backend/Services/Vaccination/Vaccination.API/Infrastructure/psql/08_00_sprint_7_update.psql`, **pendiente de revisión antes de aplicar** (100% aditivo, pero cambia mucha superficie). `Organization` y `Patient` tenían solo columnas faltantes (`codigo_deis_cl`, `keycloak_base_path`) — Organization ya aplicado, Patient ya aplicado. `Practitioner`, `Notifications`, `VersionManager` ya estaban sincronizados.

---

## Cómo agregar un servicio nuevo a Vault (checklist)

Ejemplo real trabajado esta sesión: **Reporting** (API + Worker, comparten SA y rol — mismo patrón que Audit Consumer/Producer). Sigue este orden exacto:

1. **ServiceAccount** — agregar UNA entrada en `Manifiestos/backend/service-accounts.yml` (namespace `dev-sprint-1`). Si el servicio tiene 2 deployables (API + Worker), comparten la misma SA, no crear una por deployable.
2. **Policy** — nuevo archivo `Manifiestos/vault/policies/<servicio>-policy.hcl` con acceso de lectura (`capabilities = ["read"]`) solo a los paths que ese servicio realmente necesita, más los 2 paths estándar de token:
   ```hcl
   path "secret/data/rni/dev/postgresql/<servicio>" { capabilities = ["read"] }
   path "secret/data/rni/dev/rabbitmq/backend"      { capabilities = ["read"] }   # si publica/consume eventos
   path "auth/token/renew-self" { capabilities = ["update"] }
   path "auth/token/lookup-self" { capabilities = ["read"] }
   ```
3. **Cargar la policy y crear el rol** (ver Paso 4/6 de Fase 1 arriba, o directo):
   ```bash
   kubectl exec -n vault -i vault-0 -- sh -c "cat > /tmp/<servicio>-policy.hcl" < policies/<servicio>-policy.hcl
   kubectl exec -n vault vault-0 -- env VAULT_TOKEN=<root-token> vault policy write <servicio>-policy /tmp/<servicio>-policy.hcl
   kubectl exec -n vault vault-0 -- env VAULT_TOKEN=<root-token> vault write auth/kubernetes-dev/role/<servicio>-role \
     bound_service_account_names=<servicio>-sa bound_service_account_namespaces=dev-sprint-1 \
     policies=<servicio>-policy ttl=1h
   ```
4. **Cargar el secreto** — agregar el bloque `vault kv put secret/rni/dev/postgresql/<servicio> ...` a `load-secrets-dev.sh` (nunca se commitea con valores reales) y ejecutarlo, o usar `vault kv put`/`vault kv patch` directo. Si el servicio publica a un broker compartido (ej. `rabbitmq/backend`), agregar sus credenciales ahí con `vault kv patch` (nunca `put`, para no pisar los usuarios ya cargados de otros servicios) y también en el `agent-inject-template-definitions` del broker correspondiente para que se cree el usuario.
5. **Manifiesto K8s** — annotations Vault en el Deployment (`vault.hashicorp.com/role`, `/auth-path`, `/agent-inject-secret-*`, `/agent-inject-template-*`), `serviceAccountName: <servicio>-sa`. Usar el patrón de plantilla de variables de entorno (ver "Patrón usado" arriba), no JSON + volumeMount manual.
6. **Verificar ANTES de dar por bueno**:
   - `vault read auth/kubernetes-dev/role/<servicio>-role` — confirma que el rol quedó con el SA/policy correctos.
   - `vault kv get secret/rni/dev/postgresql/<servicio>` — confirma que el secreto tiene las claves exactas que el template del manifiesto espera (un nombre de clave distinto = variable de entorno vacía en el pod, sin error visible).
   - Si el servicio usa una base de datos nueva, **confirmarla con una query directa** (`SELECT datname FROM pg_database WHERE datname='<db>'`) — no asumas que existe solo porque el connection string está bien armado en Vault.
   - Si el servicio publica a un broker compartido, probar autenticación real antes de desplegar: `rabbitmqctl authenticate_user <user> <password>` ejecutado dentro del pod del broker.
7. **`configurador.py`** — agregar el/los nombre(s) de imagen a `IMAGE_MAP` y el/los manifiesto(s) a `LAYERS["backend"]`.
8. **`azure-pipelines.yml`** — replicar el cableado de un servicio existente con la misma forma (2 deployables → seguir el patrón de Audit Consumer/Producer; 1 deployable → seguir el patrón de cualquier miniservicio simple) en `detect_changes`, `build_all`, `test_all`, `containerize_publish`, `Deploy_Dev`/`Deploy_QA`, y los 3 arrays `SERVICES` de `promote_to_*`.

---

## Re-unseal tras reinicio del pod

```bash
kubectl --kubeconfig "<kubeconfig>" exec -n vault vault-0 -- vault operator unseal <KEY_1>
kubectl --kubeconfig "<kubeconfig>" exec -n vault vault-0 -- vault operator unseal <KEY_2>
kubectl --kubeconfig "<kubeconfig>" exec -n vault vault-0 -- vault operator unseal <KEY_3>
```

O usa `Manifiestos/vault/unseal.sh` (pide las claves interactivamente).

---

## Acceso a Vault UI / CLI

```bash
kubectl --context=<contexto> port-forward -n vault svc/vault 8200:8200
```

Abrir `http://localhost:8200/ui` → login con **Token** → root token del ambiente. `Ctrl+C` para cerrar el túnel.

Alternativa sin port-forward, ejecutando directo dentro del pod (útil en Windows/Git Bash donde el port-forward compite con otras terminales):

```bash
export MSYS_NO_PATHCONV=1
kubectl --context=<contexto> exec -n vault vault-0 -- env VAULT_TOKEN=<root-token> vault kv get secret/rni/dev/postgresql/patient
```

---

## Estado del servicio

```bash
kubectl --context=<contexto> exec -n vault vault-0 -- vault status
```

| Campo | Significado |
|-------|-------------|
| `Sealed: false` | Vault operativo |
| `Sealed: true` | Requiere unseal (ver arriba) |
| Pod `0/1 Pending` | Problema de scheduling — revisar recursos del nodo (`kubectl describe node`) |

---

## Seguridad y justificación de la arquitectura

### Por qué esta práctica es la más segura

#### 1. Vault como ClusterIP — sin exposición externa

El servicio `vault` es `ClusterIP` — no tiene dirección enrutable fuera del cluster. Elimina la superficie de ataque externa completamente.

**Referencia:** OWASP API Security Top 10 — API8:2023 *Security Misconfiguration*.

#### 2. Acceso via VPN + kubeconfig — autenticación doble

- **VPN activa**: autenticación a nivel de red — solo IPs corporativas autorizadas
- **Kubeconfig de Rancher**: token/certificado de cliente Kubernetes emitido por Rancher, expira periódicamente

Sin ambos factores el acceso es imposible.

**Referencia:** NIST SP 800-207 *Zero Trust Architecture*.

#### 3. Port-forward efímero — acceso just-in-time

El túnel existe solo mientras el operador lo necesita. Al cerrar la terminal el acceso termina.

**Referencia:** CIS Kubernetes Benchmark v1.8 — Control 5.4.1.

#### 4. Vault Agent Injector — secretos nunca en manifiestos

Ninguna credencial vive en manifiestos YAML ni código fuente. El Vault Agent (sidecar) escribe los secretos en un volumen `emptyDir` en memoria (`Medium: Memory` para los volúmenes de redis; el injector usa un volumen efímero propio para el resto) dentro del pod. Los secretos no persisten en disco del nodo ni en etcd.

**Referencia:** OWASP Top 10 — A02:2021 *Cryptographic Failures*. CWE-312.

#### 5. Cumplimiento Ley 20.584 y MINSAL

- Control de acceso estricto a sistemas que procesan datos de salud
- Trazabilidad de accesos via audit log inmutable en Vault (`/vault/logs/audit.log`)
- Credenciales nunca en texto plano en repositorio ni en el cluster (excepto los pendientes listados en "Pendientes conocidos")

### Resumen de controles

| Control | Implementación | Referencia |
|---------|---------------|------------|
| Sin exposición externa | ClusterIP + sin Ingress | OWASP API8:2023 |
| Doble autenticación | VPN + kubeconfig | NIST SP 800-207 |
| Acceso efímero | port-forward just-in-time | CIS K8s Benchmark 5.4 |
| Secrets fuera del repo | Vault KV v2 | OWASP A02:2021 |
| Secrets fuera de etcd | Vault Agent Injector → volumen efímero | CWE-312 |
| Audit trail | `/vault/logs/audit.log` | Ley 20.584 |
| Least privilege | Una política + un rol + un ServiceAccount por servicio | NIST SP 800-53 AC-6 |
