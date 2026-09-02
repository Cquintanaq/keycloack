# Runbook — Levantar Vault en PRE e inyectar secretos

Guía única, de punta a punta, para que Carlos (o cualquier operador con acceso al
cluster `worker-pre`) ejecute todo desde su propia terminal — sin tener que leer
los comentarios sueltos de cada script. Sigue el orden exacto; no saltar pasos.

Todos los comandos asumen que Carlos ya resolvió el "puente" hacia `worker-pre`
(VPN/bastión + kubeconfig con el contexto `worker-pre` cargado). Ese acceso es
responsabilidad suya y no se cubre acá — este runbook empieza donde `kubectl
--context=worker-pre get nodes` ya responde.

---

## 0. Prerrequisitos

- [ ] `kubectl` apuntando a `worker-pre` (verificar: `kubectl config get-contexts` debe listar `worker-pre`)
- [ ] `jq` instalado (lo usan `init.sh` y `unseal.sh`)
- [ ] `vault` CLI instalado localmente (opcional pero recomendado para `enable-k8s-pre.sh` — si no está, se puede adaptar a `kubectl exec -n vault vault-0 -- vault ...`)
- [ ] Este repo clonado (rama `26C5_Sprint7_CI_CD` o la que corresponda en producción)
- [ ] Acceso al gestor de secretos corporativo, para guardar `root_token` + 5 `unseal_keys`
- [ ] Los valores reales de infraestructura de PRE (checklist completo en el paso 4)

Todos los comandos de este runbook se ejecutan parado en:
```bash
cd Deployment/Cluster/Manifiestos/vault
```

---

## 1. Desplegar Vault en worker-pre

```bash
kubectl config use-context worker-pre
kubectl apply -f vault-pre-all.yaml
```

Esto crea el namespace `vault`, el StatefulSet `vault-0`, el Agent Injector y el
Ingress en `https://rni-pre.saludenred.cl/vault-ui`.

Verificar que el pod esté corriendo (todavía no "Ready" — antes de inicializar,
`vault status` siempre reporta `not initialized`, eso es normal):

```bash
kubectl -n vault wait --for=condition=PodScheduled pod/vault-0 --timeout=120s
kubectl -n vault get pod vault-0
```

---

## 2. Inicializar y desellar (solo la PRIMERA vez)

Si este Vault nunca fue inicializado, correr el script (genera 5 claves, umbral 3,
habilita KV v2, audit log y carga las políticas de `policies/*.hcl`):

```bash
bash init.sh
```

Al final imprime `vault-init-output.json`. **Antes de seguir**:

1. Abrir el archivo y copiar `root_token` + los 5 `unseal_keys_b64[0..4]` al
   gestor de secretos corporativo.
2. Borrarlo del disco: `rm vault-init-output.json` (o `shred -u` si está disponible).

Si el comando falla con `Vault is already initialized` (alguien ya corrió este
paso antes), saltar directo al paso 3 usando las keys ya guardadas en el gestor.

**Tras cualquier reinicio del pod `vault-0`** (no una inicialización nueva — un
Vault ya inicializado no se puede re-inicializar sin perder todo lo que tiene
adentro), Vault vuelve a quedar sellado. Para desellar sin volver a inicializar:

```bash
bash unseal.sh
```
(pide 3 de las 5 keys guardadas, interactivo, no las expone en el historial de shell).

---

## 3. Habilitar autenticación Kubernetes y políticas

Requiere `VAULT_ADDR` y `VAULT_TOKEN` (el `root_token` del paso 2):

```bash
export VAULT_ADDR="https://rni-pre.saludenred.cl/vault-ui"
export VAULT_TOKEN="<root_token del gestor corporativo>"

bash auth/enable-k8s-pre.sh
```

Esto habilita el auth method `kubernetes-pre`, recarga las políticas HCL, y crea
un rol por cada microservicio/infra de backend + security en el namespace
`pre-master` (ver comentarios del propio script para el detalle de qué rol
mapea a qué ServiceAccount).

---

## 4. Checklist de valores reales — resolver ANTES del paso 5

A diferencia de dev/qa, en PRE **no se aceptan placeholders `TODO`** para estos
campos — son datos de infraestructura real de salud (Ley 20.584). Confirmar cada
uno con Ops antes de continuar. Ninguno puede asumirse igual al de QA
(`172.16.1.74`) sin confirmación explícita:

**Obligatorios (el script falla si faltan):**
- [ ] `DB_HOST_CORE` / puerto — instancia Postgres de organization+practitioner+notifications+versionmanager
- [ ] `DB_HOST_PATIENT` / puerto
- [ ] `DB_HOST_REPORTING` / puerto
- [ ] `DB_HOST_VACCINATION` / puerto
- [ ] `DB_HOST_AUDIT` / puerto
- [ ] `DB_USER` / `DB_PASS`
- [ ] `KEYCLOAK_ISSUER` (con puerto real — `version/pre-master.yml` no lo trae)

**Opcionales pero bloqueantes para dar PRE por operativo** (si se dejan vacíos,
`load-secrets-pre.sh` carga un placeholder `TODO: ...` y lo lista al final —
hay que volver y resolverlos, no dejarlos así como en dev/qa):
- [ ] `ORGANIZATION_KEYCLOAK_CLIENT_SECRET`
- [ ] `AZURE_MONITOR_CONNECTION_STRING`
- [ ] `GATEWAY_KEYCLOAK_CLIENT_SECRET` / `GATEWAY_INTERNAL_CLIENT_SECRET` / `GATEWAY_JWT_SECRET`
- [ ] `MINSAL_CLIENT_ID` / `MINSAL_CLIENT_SECRET`
- [ ] `REPORTING_VACCINATION_READ_CONNECTION` (requiere crear antes un usuario Postgres de solo lectura real sobre `vaccinationdb_write`)
- [ ] `PATIENT_DB_PASSWORD_LEGACY`

Las passwords puramente internas de RabbitMQ/Redis (16 variables) **no** están en
esta lista — `load-secrets-pre.sh` las autogenera con `openssl rand` si no se
exportan, y las imprime al final para guardar en el gestor corporativo.

---

## 5. Cargar los secretos en Vault

`load-secrets-pre.sh` y `load-secrets-pre.env` **no están en el repo** (están en
`.gitignore` a propósito — contienen o generan valores reales). Deben llegar a
Carlos por un canal seguro (no email/chat en texto plano), no por `git clone`.

```bash
cp load-secrets-pre.env.example load-secrets-pre.env
# completar load-secrets-pre.env con los valores del checklist del paso 4
nano load-secrets-pre.env   # o el editor que prefieras

export VAULT_ADDR="https://rni-pre.saludenred.cl/vault-ui"
export VAULT_TOKEN="<root_token o token con permiso de escritura>"

bash load-secrets-pre.sh
```

Al terminar, el script imprime:
- Las passwords internas autogeneradas de RabbitMQ/Redis → guardarlas en el gestor corporativo.
- El checklist de valores que quedaron en `TODO` → deben quedar en cero antes de dar PRE por operativo.

**Importante**: los usuarios de RabbitMQ (`admin`, `svc-organization`, `svc-patient`,
`svc-vaccination`, `svc-audit-consumer`, `svc-audit-producer`, `svc-reporting`,
`notifications_service`, `email_service`, `sms_service`, `monitoring_user`,
`apigateway_user`) **no existen todavía en los brokers reales de PRE** — las
passwords quedan en Vault, pero hay que crear/actualizar esos usuarios en
RabbitMQ (`definitions.json` en el primer arranque, o `rabbitmqctl` si el broker
ya está corriendo) con los mismos valores.

---

## 6. Verificación final

```bash
vault kv list secret/rni/pre/postgresql
vault kv list secret/rni/pre/rabbitmq
vault kv list secret/rni/pre/redis
vault status
```

Cuando se despliegue el resto del stack backend/security en `pre-master`
(vía `configurador.py --namespace pre-master`), los pods con anotación
`vault.hashicorp.com/agent-inject-*` deben pasar de `Init:X/Y` a `Running`
solos — si se quedan pegados en `Init`, es Vault sellado o el rol/policy
correspondiente mal configurado, no un problema del pod puntual.

---

## Nota — dónde vive realmente el multi-instancia de PRE

Los 11 servicios backend leen su connection string exclusivamente vía Vault
Agent Injector (ninguno tiene ya un `Host=`/`Server=` literal en el manifiesto
fuente) — por eso el soporte de las 4 instancias de PostgreSQL de PRE
(core/patient/reporting/vaccination/audit) se resuelve **100% en el paso 5**
de este runbook (`load-secrets-pre.sh` con `DB_HOST_CORE`/`DB_HOST_PATIENT`/
`DB_HOST_REPORTING`/`DB_HOST_VACCINATION`/`DB_HOST_AUDIT`), no en
`configurador.py` ni en `version/pre-master.yml` — esos dos no necesitan (ni
tienen) ningún campo `db_host_<grupo>`.
