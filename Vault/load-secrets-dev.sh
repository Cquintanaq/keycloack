#!/usr/bin/env bash
# Carga inicial de secretos en Vault DEV.
# Rellena las variables marcadas con TODO antes de ejecutar.
# NUNCA commitear este archivo — está en .gitignore.
#
# IMPORTANTE: las claves de cada `vault kv put` deben coincidir EXACTAMENTE
# con lo que cada agent-inject-template lee en los manifiestos K8s
# (Deployment/Cluster/Manifiestos/backend/*.yml, security/*.yml). Antes de
# tocar este archivo, verificar el bloque `vault.hashicorp.com/agent-inject-template-*`
# del manifiesto correspondiente — un nombre de clave distinto se traduce en
# una variable de entorno vacía dentro del pod, no en un error visible.
#
# Uso:
#   export VAULT_ADDR=http://localhost:8200
#   export VAULT_TOKEN=<root-token>
#   bash load-secrets-dev.sh

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Definir VAULT_ADDR}"
VAULT_TOKEN="${VAULT_TOKEN:?Definir VAULT_TOKEN}"
ENV="dev"

export VAULT_ADDR VAULT_TOKEN

# Servidor PostgreSQL compartido de DEV — confirmado en version/dev-sprint-1.yml
# y version/dev-master.yml (usado hasta ahora por configurador.py antes de Vault).
# Cada servicio tiene su propia base <servicio>db_write en este mismo servidor.
DB_HOST="172.16.1.85"
DB_PORT="5432"
DB_USER="rni-miniservicios"
DB_PASS="RNI.2026#"

echo "==> Cargando secretos en secret/rni/${ENV}/..."

# ============================================================
# PostgreSQL
# ============================================================

# Leído por miniservice-organization.yml (postgresql/organization):
# ConnectionStrings__ReadWriteConnection, ConnectionStrings__ReadOnlyConnection,
# Keycloak__ClientSecret, AzureMonitor__ConnectionString
# NOTA: connection strings confirmadas contra el secret K8s real "miniservice-organization-secrets"
# (organizationdb_write/rni-miniservicios/RNI.2026#, coincide con lo de abajo).
# Keycloak__ClientSecret: confirmado que en vivo sigue siendo un placeholder sin sustituir
# (nunca se configuró un valor real) — sigue pendiente, hay que pedirlo al admin de Keycloak.
# AzureMonitor__ConnectionString: en vivo SÍ tiene un valor real (no un placeholder), pero
# el propio entorno lo redacta al leerlo — copiar el valor real directamente desde la UI de
# Rancher (Secret miniservice-organization-secrets) en vez de escribirlo aquí.
vault kv put "secret/rni/${ENV}/postgresql/organization" \
  ConnectionStrings__ReadWriteConnection="Server=${DB_HOST};Port=${DB_PORT};Database=organizationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Server=${DB_HOST};Port=${DB_PORT};Database=organizationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  Keycloak__ClientSecret="TODO: client secret de organization en Keycloak" \
  AzureMonitor__ConnectionString="TODO: copiar el valor real desde Rancher > Secret miniservice-organization-secrets (existe en vivo, redactado para mí)"
echo "  ✓ postgresql/organization"

# Leído por miniservice-patient.yml (postgresql/patient):
# ConnectionStrings__ReadWriteConnection, ConnectionStrings__ReadOnlyConnection, DB_PASSWORD
# NOTA: DB_PASSWORD confirmado contra el secret K8s real "miniservice-patient-secrets"
# en worker-dev — es "postgres" (valor plano distinto de RNI.2026#, aunque las
# connection strings sí usan RNI.2026#). Se mantiene el valor real en vivo.
vault kv put "secret/rni/${ENV}/postgresql/patient" \
  ConnectionStrings__ReadWriteConnection="Server=${DB_HOST};Port=${DB_PORT};Database=patientdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Server=${DB_HOST};Port=${DB_PORT};Database=patientdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  DB_PASSWORD="postgres"
echo "  ✓ postgresql/patient"

# Leído por miniservice-practitioner.yml (postgresql/practitioner): solo DB_PASSWORD
# (host/db/usuario van en el ConfigMap del manifiesto, no en Vault)
# NOTA: confirmado contra el secret K8s real "miniservice-practitioner-secrets" — "postgres".
vault kv put "secret/rni/${ENV}/postgresql/practitioner" \
  DB_PASSWORD="postgres"
echo "  ✓ postgresql/practitioner"

# Leído por miniservice-vaccination.yml (postgresql/vaccination):
# ConnectionStrings__ReadWriteConnection, ConnectionStrings__ReadOnlyConnection
# + ConnectionStrings__Read{Write,Only}ConnectionBucket{A,B,C,D} (AddImmunizationBucketing).
# NOTA 2026-07-24: el sharding real de immunization aún no está diseñado (feature
# incompleta, tampoco existe en QA). Decisión pragmática del equipo: los 4 buckets
# apuntan por ahora a la MISMA conexión base que ya usa el servicio, solo para que
# el servicio deje de crashear al arrancar. Rediseño real de la topología de
# bucketing pendiente — revisar antes de asumir que hay sharding real funcionando.
vault kv put "secret/rni/${ENV}/postgresql/vaccination" \
  ConnectionStrings__ReadWriteConnection="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketA="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketA="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketB="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketB="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketC="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketC="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketD="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketD="Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true"
echo "  ✓ postgresql/vaccination (+ 4 buckets apuntando a la misma conexión, pendiente rediseño)"

# Leído por miniservice-notifications.yml (postgresql/notifications):
# NotificationsDb, JWT_ALGORITHM, KEYCLOAK_ISSUER, RABBITMQ_HOST/PASS/PORT/USER, REDIS_HOST/PORT
# NOTA: valores verificados contra el secret K8s real "miniservice-notifications-secret"
# en worker-dev — corregidos: nombre de base "notifications_write" (no "notificationsdb_write"),
# KEYCLOAK_ISSUER interno del cluster, REDIS_HOST con sufijo "-service" (nombre real del Service).
# RABBITMQ_USER/PASS: el secret viejo tenía "notifications_user"/"notifications_secure_2026",
# pero es un valor PRE-Vault (stale) — el broker rabbit-notifications ya fue reconfigurado
# vía Vault con el usuario "notifications_service" (ver rabbitmq/notifications-infra abajo,
# confirmado con `rabbitmqctl list_users` en vivo), así que se mantiene ese valor nuevo.
vault kv put "secret/rni/${ENV}/postgresql/notifications" \
  NotificationsDb="Host=${DB_HOST};Port=${DB_PORT};Database=notifications_write;Username=${DB_USER};Password=${DB_PASS};Search Path=notifications" \
  JWT_ALGORITHM="RS256" \
  KEYCLOAK_ISSUER="http://keycloak.dev-sprint-1.svc.cluster.local:8080/realms/rni-realm" \
  RABBITMQ_HOST="rabbit-notifications.dev-sprint-1.svc.cluster.local" \
  RABBITMQ_PASS="notif-service-2026" \
  RABBITMQ_PORT="5672" \
  RABBITMQ_USER="notifications_service" \
  REDIS_HOST="redis-notifications-service.dev-sprint-1.svc.cluster.local" \
  REDIS_PORT="6379"
echo "  ✓ postgresql/notifications"

# Leído por miniservice-version-manager.yml (postgresql/versionmanager):
# la clave "database-connection" (literal, con guion) y ConnectionStrings__VersionesDb
# CONFIRMADO contra el secret K8s real "miniservice-versionmanager-secrets" en worker-dev:
# ambas claves usan el mismo valor, con el patrón compartido rni-miniservicios/RNI.2026#
# (no postgres/postgres como se había asumido con baja confianza antes).
vault kv put "secret/rni/${ENV}/postgresql/versionmanager" \
  database-connection="Host=${DB_HOST};Port=${DB_PORT};Database=versioning;Username=${DB_USER};Password=${DB_PASS}" \
  ConnectionStrings__VersionesDb="Host=${DB_HOST};Port=${DB_PORT};Database=versioning;Username=${DB_USER};Password=${DB_PASS}"
echo "  ✓ postgresql/versionmanager"

# Leído por audit-consumer.yml y audit-producer.yml (AMBOS comparten este path,
# cada uno con su propio set de claves con prefijo consumer_/producer_):
# consumer_* = base propia de audit (auditdb_write, misma réplica hasta que se separe).
# producer_listener_* = las mismas bases de organization/patient/practitioner
# (el producer lee su outbox para publicar eventos de auditoría) — orden 0/1/2
# confirmado en Backend/docker-compose.override.yml (AuditListener__Databases__0/1/2).
vault kv put "secret/rni/${ENV}/postgresql/audit" \
  consumer_primary="Server=${DB_HOST};Port=${DB_PORT};Database=auditdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_replica="Server=${DB_HOST};Port=${DB_PORT};Database=auditdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_analytics="Server=${DB_HOST};Port=${DB_PORT};Database=auditdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_broker_user="svc-audit-consumer" \
  consumer_broker_password="audit_consumer_secret" \
  producer_listener_0="Server=${DB_HOST};Port=${DB_PORT};Database=organizationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_listener_1="Server=${DB_HOST};Port=${DB_PORT};Database=patientdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_listener_2="Server=${DB_HOST};Port=${DB_PORT};Database=practitionerdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_broker_user="svc-audit-producer" \
  producer_broker_password="audit_producer_secret"
echo "  ✓ postgresql/audit"

# Leído por miniservice-reporting.yml (API) y reporting-worker.yml (Worker) —
# AMBOS comparten este mismo path y la misma ServiceAccount/rol de Vault
# (reporting-sa / reporting-role). Las credenciales de RabbitMQ NO van aquí —
# van en rabbitmq/backend (ver más abajo), igual que organization/patient.
# TODO: ConnectionStrings__VaccinationRead necesita un usuario de PostgreSQL
# de SOLO LECTURA real sobre vaccinationdb_write — ese rol todavía no existe
# en el servidor 172.16.1.85, hay que crearlo con quien administra esa base
# antes de que esto funcione. Por ahora reutiliza el usuario compartido
# (funcionará igual porque ya tiene acceso, pero NO es el usuario correcto
# a largo plazo — es de lectura/escritura, no solo lectura).
vault kv put "secret/rni/${ENV}/postgresql/reporting" \
  ConnectionStrings__ReportingDb="Server=${DB_HOST};Port=${DB_PORT};Database=reportingdb;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__VaccinationRead="TODO: crear usuario de solo lectura real sobre vaccinationdb_write — Server=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true"
echo "  ✓ postgresql/reporting"

# ============================================================
# RabbitMQ
# ============================================================

# Usado por rabbit-general-backend.yml/rabbit-audit.yml (para crear los usuarios
# del broker) Y por miniservice-organization.yml/miniservice-patient.yml (para
# que la app se autentique con ese mismo usuario) — deben coincidir.
vault kv put "secret/rni/${ENV}/rabbitmq/backend" \
  admin_password="admin-audit-2026" \
  organization_user="svc-organization" \
  organization_password="organization_secret" \
  patient_user="svc-patient" \
  patient_password="patient_secret" \
  vaccination_password="vaccination_secret" \
  audit_consumer_password="audit_consumer_secret" \
  audit_producer_password="audit_producer_secret" \
  notifications_password="notif-service-2026" \
  reporting_user="svc-reporting" \
  reporting_password="reporting_secret"
echo "  ✓ rabbitmq/backend"

vault kv put "secret/rni/${ENV}/rabbitmq/notifications-infra" \
  admin_password="admin-notifications-2026" \
  erlang_cookie="rabbit-notifications-cookie-2026" \
  notifications_service_password="notif-service-2026" \
  email_service_password="email-service-2026" \
  sms_service_password="sms-service-2026" \
  monitoring_user_password="monitor-notif-2026"
echo "  ✓ rabbitmq/notifications-infra"

vault kv put "secret/rni/${ENV}/rabbitmq/security" \
  admin_password="admin-secure-2026" \
  erlang_cookie="rabbit-security-cookie-2026" \
  apigateway_password="apigw_secure_2026"
echo "  ✓ rabbitmq/security"

# ============================================================
# Keycloak
# ============================================================

# NOTA: el ClientSecret de organization NO se lee de aquí — miniservice-organization.yml
# lo lee de postgresql/organization (ver arriba). Este path queda cargado para
# uso directo desde código/futuro, pero no es consumido hoy por ningún manifiesto.
vault kv put "secret/rni/${ENV}/keycloak/clients/organization" \
  ClientSecret="TODO: client secret de organization en Keycloak (igual al de postgresql/organization arriba)"
echo "  ✓ keycloak/clients/organization"

# Leído por security/apigateway.yml: JwtSecret, ClientSecret
vault kv put "secret/rni/${ENV}/keycloak/clients/gateway" \
  ClientSecret="TODO: client secret de apigateway en Keycloak" \
  InternalClientSecret="TODO: internal client secret" \
  AccessKey="0DdrT08xEM" \
  JwtSecret="TODO: JWT signing secret RS256"
echo "  ✓ keycloak/clients/gateway (AccessKey tomado de version/dev-master.yml: apiGateway__internalAccessKey)"

# ============================================================
# Redis
# ============================================================

# Dos consumidores distintos del MISMO valor: security/apigateway.yml lee "Password",
# security/redis-security.yml (el propio Redis) lee "REDIS_PASSWORD". Deben ser iguales.
REDIS_SECURITY_PASS="redis_strong_pass_2026"
vault kv put "secret/rni/${ENV}/redis/security" \
  Password="${REDIS_SECURITY_PASS}" \
  REDIS_PASSWORD="${REDIS_SECURITY_PASS}" \
  ConnectionString="redis-security-service.dev-sprint-1.svc.cluster.local:6379,password=${REDIS_SECURITY_PASS}"
echo "  ✓ redis/security"

# Leído por backend/redis-notifications.yml: REDIS_PASSWORD (no "Password")
vault kv put "secret/rni/${ENV}/redis/notifications" \
  REDIS_PASSWORD="redis_strong_pass_2026"
echo "  ✓ redis/notifications"

# Leído por backend/redis-versionmanager.yml: REDIS_PASSWORD (no "Password")
vault kv put "secret/rni/${ENV}/redis/versionmanager" \
  REDIS_PASSWORD="redis_strong_pass_2026"
echo "  ✓ redis/versionmanager"

# ============================================================
# Azure Monitor
# ============================================================

# NOTA: no lo lee ningún manifiesto hoy — miniservice-organization.yml usa
# AzureMonitor__ConnectionString desde postgresql/organization (ver arriba).
# Se deja cargado para uso futuro/directo desde código.
vault kv put "secret/rni/${ENV}/azure/monitor" \
  ConnectionString="TODO: InstrumentationKey=XXXX;IngestionEndpoint=https://..."
echo "  ✓ azure/monitor"

# ============================================================
# MINSAL EMPI
# ============================================================

# Leído por miniservice-integrations.yml: ClientId, ClientSecret
vault kv put "secret/rni/${ENV}/minsal/empi" \
  ClientId="TODO: client id MINSAL" \
  ClientSecret="TODO: client secret MINSAL"
echo "  ✓ minsal/empi"

# ============================================================
# OPA
# ============================================================

# No lo lee ningún manifiesto hoy (Secret eliminado de opa-security.yml
# intencionalmente — ver vault-hashicorp.md). Cargado para activarlo a futuro.
vault kv put "secret/rni/${ENV}/opa/auth" \
  admin_token="TODO: JWT token de admin OPA" \
  api_key="TODO: API key OPA" \
  jwt_secret="TODO: JWT secret para validar tokens" \
  jwt_issuer="TODO: https://keycloak.../realms/rni" \
  jwt_audience="opa-service"
echo "  ✓ opa/auth"

echo ""
echo "✅ Secretos DEV cargados."
echo "   IMPORTANTE: Rota los valores marcados como 'TODO' y los"
echo "   marcados como iniciales (contraseñas *-2026, redis_strong_pass_2026)"
echo "   antes de pasar a QA/producción."
