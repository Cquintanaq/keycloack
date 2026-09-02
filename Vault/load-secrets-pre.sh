#!/usr/bin/env bash
# Carga inicial de secretos en Vault PRE.
# NUNCA commitear este archivo con valores reales — está en .gitignore.
#
# Reescrito desde cero a partir de load-secrets-dev.sh (NO de load-secrets-qa.sh,
# a ese le faltan organization_password/patient_password en rabbitmq/backend y las
# 4 claves de usuarios de rabbitmq/notifications-infra — ver
# .agents/plans/sprint 8/secrets-backend-vault-azure.md). Cubre los 16 paths de la
# tabla maestra de ese documento, sin ninguna clave faltante.
#
# La versión ANTERIOR de este archivo tenía ENV="dev" hardcodeado y el DB_HOST de
# DEV (172.16.1.85) — era literalmente una copia de load-secrets-dev.sh sin adaptar.
#
# IMPORTANTE — a diferencia de dev/qa, para PRE NO se aceptan valores inventados
# para infraestructura real: DB_HOST_<GRUPO>/DB_PORT_<GRUPO>/DB_USER/DB_PASS y
# KEYCLOAK_ISSUER son OBLIGATORIOS por variable de entorno (el script falla si
# faltan) porque adivinar mal cualquiera de estos apunta silenciosamente a la
# base de datos o al Keycloak equivocado — dato de salud bajo Ley 20.584, no es
# un detalle menor.
#
# PRE (a diferencia de dev/qa, que comparten un solo Postgres) tiene 4 instancias
# PostgreSQL propias en el MISMO servidor físico, cada una con su propio volumen
# de disco (ver version/pre-master.yml para el detalle de sizing). Este script
# pide un DB_HOST/DB_PORT por grupo en vez de uno solo:
#   DB_HOST_CORE        -> organization, practitioner, notifications, versionmanager
#   DB_HOST_PATIENT     -> patient
#   DB_HOST_REPORTING   -> reporting
#   DB_HOST_VACCINATION -> vaccination
#   DB_HOST_AUDIT       -> audit (base propia de auditoría; el AUDIT-PRODUCER
#                          además escucha directo las DBs de organization/patient/
#                          practitioner vía outbox — usa el host de CADA una de
#                          esas, no el de audit, ver bloque postgresql/audit abajo)
#
# La versión ANTERIOR de este script tenía un solo DB_HOST=172.16.1.74 (el mismo
# que QA) — arrastre nunca corregido, no confirmar esa IP para ningún grupo sin
# validar con Ops.
#
# Las passwords puramente internas de RabbitMQ/Redis (no dependen de ningún sistema
# externo) se autogeneran con `openssl rand` si no se exportan explícitamente, y se
# imprimen al final para guardarlas en el gestor de secretos corporativo.
#
# Los valores que dependen de un sistema externo (Keycloak, MINSAL, Azure Monitor)
# quedan como "TODO: ..." si no se exportan — el script termina igual, pero el
# checklist final lista cuáles quedaron pendientes. Antes de dar PRE por operativo,
# ese checklist debe quedar vacío (ver "Advertencia importante para PRE/PRO" en el
# plan).
#
# Uso recomendado (todas las variables en un solo lugar):
#   cp load-secrets-pre.env.example load-secrets-pre.env
#   # completar load-secrets-pre.env con los valores reales de PRE (nunca commitear,
#   # ya está en .gitignore)
#   bash load-secrets-pre.sh
#
# Uso alternativo (exportar variables sueltas en la terminal, sin el .env):
#   export VAULT_ADDR=https://rni-pre.saludenred.cl/vault-ui   # o el endpoint interno
#   export VAULT_TOKEN=<root-o-token-con-permisos-de-escritura>
#   export DB_HOST_CORE=<host real de la instancia core>
#   export DB_HOST_PATIENT=<host real de la instancia patient>
#   export DB_HOST_REPORTING=<host real de la instancia reporting>
#   export DB_HOST_VACCINATION=<host real de la instancia vaccination>
#   export DB_HOST_AUDIT=<host real de la instancia audit>
#   export DB_USER=<usuario real>
#   export DB_PASS=<password real>
#   export KEYCLOAK_ISSUER=<https://keycloak-pre.saludteprotege.cl:PUERTO/realms/RNI-PRE>
#   bash load-secrets-pre.sh

set -euo pipefail

# Carga automática de load-secrets-pre.env si existe junto a este script — evita
# tener que exportar las ~38 variables una por una en la terminal.
ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/load-secrets-pre.env"
if [ -f "${ENV_FILE}" ]; then
  echo "==> Cargando variables desde ${ENV_FILE}"
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
fi

VAULT_ADDR="${VAULT_ADDR:?Definir VAULT_ADDR (o completarlo en load-secrets-pre.env)}"
VAULT_TOKEN="${VAULT_TOKEN:?Definir VAULT_TOKEN (o completarlo en load-secrets-pre.env)}"
ENV="pre"

export VAULT_ADDR VAULT_TOKEN

# ============================================================
# Infraestructura real de PRE — obligatorio, sin default
# 4 instancias PostgreSQL, mismo servidor físico, un host/puerto por grupo
# (ver version/pre-master.yml para el sizing y el detalle del agrupamiento)
# ============================================================
DB_HOST_CORE="${DB_HOST_CORE:?Definir DB_HOST_CORE real de PostgreSQL PRE (organization+practitioner+notifications+versionmanager) — NO asumir 172.16.1.74 de QA sin confirmar con Ops}"
DB_PORT_CORE="${DB_PORT_CORE:-5432}"
DB_HOST_PATIENT="${DB_HOST_PATIENT:?Definir DB_HOST_PATIENT real de PostgreSQL PRE — NO asumir 172.16.1.74 de QA sin confirmar con Ops}"
DB_PORT_PATIENT="${DB_PORT_PATIENT:-5432}"
DB_HOST_REPORTING="${DB_HOST_REPORTING:?Definir DB_HOST_REPORTING real de PostgreSQL PRE — NO asumir 172.16.1.74 de QA sin confirmar con Ops}"
DB_PORT_REPORTING="${DB_PORT_REPORTING:-5432}"
DB_HOST_VACCINATION="${DB_HOST_VACCINATION:?Definir DB_HOST_VACCINATION real de PostgreSQL PRE — NO asumir 172.16.1.74 de QA sin confirmar con Ops}"
DB_PORT_VACCINATION="${DB_PORT_VACCINATION:-5432}"
DB_HOST_AUDIT="${DB_HOST_AUDIT:?Definir DB_HOST_AUDIT real de PostgreSQL PRE — NO asumir 172.16.1.74 de QA sin confirmar con Ops}"
DB_PORT_AUDIT="${DB_PORT_AUDIT:-5432}"
DB_USER="${DB_USER:?Definir DB_USER real de PRE}"
DB_PASS="${DB_PASS:?Definir DB_PASS real de PRE}"
KEYCLOAK_ISSUER="${KEYCLOAK_ISSUER:?Definir KEYCLOAK_ISSUER real, ej. https://keycloak-pre.saludteprotege.cl:8444/realms/RNI-PRE — version/pre-master.yml no trae el puerto, confirmarlo con Ops}"

# ============================================================
# Passwords internas (RabbitMQ/Redis) — autogeneradas si no se exportan
# ============================================================
gen() { openssl rand -hex 24; }

RABBIT_ADMIN_PASS="${RABBIT_ADMIN_PASS:-$(gen)}"
RABBIT_ORG_PASS="${RABBIT_ORG_PASS:-$(gen)}"
RABBIT_PATIENT_PASS="${RABBIT_PATIENT_PASS:-$(gen)}"
RABBIT_VACCINATION_PASS="${RABBIT_VACCINATION_PASS:-$(gen)}"
RABBIT_AUDIT_CONSUMER_PASS="${RABBIT_AUDIT_CONSUMER_PASS:-$(gen)}"
RABBIT_AUDIT_PRODUCER_PASS="${RABBIT_AUDIT_PRODUCER_PASS:-$(gen)}"
RABBIT_REPORTING_PASS="${RABBIT_REPORTING_PASS:-$(gen)}"

RABBIT_NOTIF_ADMIN_PASS="${RABBIT_NOTIF_ADMIN_PASS:-$(gen)}"
RABBIT_NOTIF_COOKIE="${RABBIT_NOTIF_COOKIE:-$(gen)}"
RABBIT_NOTIF_SERVICE_PASS="${RABBIT_NOTIF_SERVICE_PASS:-$(gen)}"
RABBIT_EMAIL_SERVICE_PASS="${RABBIT_EMAIL_SERVICE_PASS:-$(gen)}"
RABBIT_SMS_SERVICE_PASS="${RABBIT_SMS_SERVICE_PASS:-$(gen)}"
RABBIT_MONITORING_PASS="${RABBIT_MONITORING_PASS:-$(gen)}"

RABBIT_SECURITY_ADMIN_PASS="${RABBIT_SECURITY_ADMIN_PASS:-$(gen)}"
RABBIT_SECURITY_COOKIE="${RABBIT_SECURITY_COOKIE:-$(gen)}"
RABBIT_APIGATEWAY_PASS="${RABBIT_APIGATEWAY_PASS:-$(gen)}"

REDIS_SECURITY_PASS="${REDIS_SECURITY_PASS:-$(gen)}"
REDIS_NOTIFICATIONS_PASS="${REDIS_NOTIFICATIONS_PASS:-$(gen)}"
REDIS_VERSIONMANAGER_PASS="${REDIS_VERSIONMANAGER_PASS:-$(gen)}"

# Password legada de patient/practitioner (clave DB_PASSWORD, distinta de la
# connection string) — mismo patrón raro que dev/qa ("postgres" plano). No
# autogenerar: si algo la lee en texto plano fuera de la connection string,
# mejor que sea explícita. Definir con el valor real que tenga PRE.
PATIENT_DB_PASSWORD_LEGACY="${PATIENT_DB_PASSWORD_LEGACY:-TODO: DB_PASSWORD real de patient en PRE}"

echo "==> Cargando secretos en secret/rni/${ENV}/..."

# ============================================================
# PostgreSQL
# ============================================================

vault kv put "secret/rni/${ENV}/postgresql/organization" \
  ConnectionStrings__ReadWriteConnection="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=organizationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=organizationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  Keycloak__ClientSecret="${ORGANIZATION_KEYCLOAK_CLIENT_SECRET:-TODO: client secret de organization en Keycloak PRE}" \
  AzureMonitor__ConnectionString="${AZURE_MONITOR_CONNECTION_STRING:-TODO: connection string real de Application Insights}"
echo "  ✓ postgresql/organization (instancia core)"

vault kv put "secret/rni/${ENV}/postgresql/patient" \
  ConnectionStrings__ReadWriteConnection="Host=${DB_HOST_PATIENT};Port=${DB_PORT_PATIENT};Database=patientdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Host=${DB_HOST_PATIENT};Port=${DB_PORT_PATIENT};Database=patientdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  DB_PASSWORD="${PATIENT_DB_PASSWORD_LEGACY}"
echo "  ✓ postgresql/patient (instancia patient)"

vault kv put "secret/rni/${ENV}/postgresql/practitioner" \
  ConnectionStrings__ReadWriteConnection="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=practitionerdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=practitionerdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true"
echo "  ✓ postgresql/practitioner (instancia core)"

# Buckets A-D: mismo fix pragmático que dev/qa — el sharding real de immunization
# no está diseñado todavía, los 4 buckets apuntan a la misma conexión base.
vault kv put "secret/rni/${ENV}/postgresql/vaccination" \
  ConnectionStrings__ReadWriteConnection="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketA="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketA="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketB="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketB="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketC="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketC="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketD="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketD="Host=${DB_HOST_VACCINATION};Port=${DB_PORT_VACCINATION};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true"
echo "  ✓ postgresql/vaccination (instancia vaccination, + 4 buckets apuntando a la misma conexión, pendiente rediseño real de sharding)"

vault kv put "secret/rni/${ENV}/postgresql/notifications" \
  NotificationsDb="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=notifications_write;Username=${DB_USER};Password=${DB_PASS};Search Path=notifications;Include Error Detail=true" \
  JWT_ALGORITHM="RS256" \
  KEYCLOAK_ISSUER="${KEYCLOAK_ISSUER}" \
  RABBITMQ_HOST="rabbit-notifications.pre-master.svc.cluster.local" \
  RABBITMQ_PASS="${RABBIT_NOTIF_SERVICE_PASS}" \
  RABBITMQ_PORT="5672" \
  RABBITMQ_USER="notifications_service" \
  REDIS_HOST="redis-notifications-service.pre-master.svc.cluster.local" \
  REDIS_PORT="6379"
echo "  ✓ postgresql/notifications (instancia core)"

vault kv put "secret/rni/${ENV}/postgresql/versionmanager" \
  database-connection="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=versioning;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__VersionesDb="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=versioning;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true"
echo "  ✓ postgresql/versionmanager (instancia core)"

# consumer_* usan la instancia AUDIT (auditdb_write es propia, no vive en core).
# producer_listener_* en cambio escuchan directo las DBs de organization/patient/
# practitioner via outbox (Postgres NOTIFY) — cada uno usa el host de SU instancia
# de origen, no el de audit.
vault kv put "secret/rni/${ENV}/postgresql/audit" \
  consumer_primary="Host=${DB_HOST_AUDIT};Port=${DB_PORT_AUDIT};Database=auditdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_replica="Host=${DB_HOST_AUDIT};Port=${DB_PORT_AUDIT};Database=auditdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_analytics="Host=${DB_HOST_AUDIT};Port=${DB_PORT_AUDIT};Database=auditdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_broker_user="svc-audit-consumer" \
  consumer_broker_password="${RABBIT_AUDIT_CONSUMER_PASS}" \
  producer_listener_0="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=organizationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_listener_1="Host=${DB_HOST_PATIENT};Port=${DB_PORT_PATIENT};Database=patientdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_listener_2="Host=${DB_HOST_CORE};Port=${DB_PORT_CORE};Database=practitionerdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_broker_user="svc-audit-producer" \
  producer_broker_password="${RABBIT_AUDIT_PRODUCER_PASS}"
echo "  ✓ postgresql/audit (instancia audit para consumer_*, core/patient para producer_listener_* — ver comentario arriba)"

vault kv put "secret/rni/${ENV}/postgresql/reporting" \
  ConnectionStrings__ReportingDb="Host=${DB_HOST_REPORTING};Port=${DB_PORT_REPORTING};Database=reportingdb;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__VaccinationRead="${REPORTING_VACCINATION_READ_CONNECTION:-TODO: crear usuario de solo lectura real sobre vaccinationdb_write (instancia vaccination, host=\$DB_HOST_VACCINATION) antes de fijar este valor}"
echo "  ✓ postgresql/reporting (instancia reporting)"

# ============================================================
# RabbitMQ
# ============================================================

vault kv put "secret/rni/${ENV}/rabbitmq/backend" \
  admin_password="${RABBIT_ADMIN_PASS}" \
  organization_user="svc-organization" \
  organization_password="${RABBIT_ORG_PASS}" \
  patient_user="svc-patient" \
  patient_password="${RABBIT_PATIENT_PASS}" \
  vaccination_password="${RABBIT_VACCINATION_PASS}" \
  audit_consumer_password="${RABBIT_AUDIT_CONSUMER_PASS}" \
  audit_producer_password="${RABBIT_AUDIT_PRODUCER_PASS}" \
  reporting_user="svc-reporting" \
  reporting_password="${RABBIT_REPORTING_PASS}"
echo "  ✓ rabbitmq/backend"

vault kv put "secret/rni/${ENV}/rabbitmq/notifications-infra" \
  admin_password="${RABBIT_NOTIF_ADMIN_PASS}" \
  erlang_cookie="${RABBIT_NOTIF_COOKIE}" \
  notifications_service_password="${RABBIT_NOTIF_SERVICE_PASS}" \
  email_service_password="${RABBIT_EMAIL_SERVICE_PASS}" \
  sms_service_password="${RABBIT_SMS_SERVICE_PASS}" \
  monitoring_user_password="${RABBIT_MONITORING_PASS}"
echo "  ✓ rabbitmq/notifications-infra"

vault kv put "secret/rni/${ENV}/rabbitmq/security" \
  admin_password="${RABBIT_SECURITY_ADMIN_PASS}" \
  erlang_cookie="${RABBIT_SECURITY_COOKIE}" \
  apigateway_password="${RABBIT_APIGATEWAY_PASS}"
echo "  ✓ rabbitmq/security"

# ============================================================
# Keycloak
# ============================================================

# No lo lee ningún manifiesto hoy (el ClientSecret real se lee desde
# postgresql/organization arriba) — se carga por paridad con dev/qa.
vault kv put "secret/rni/${ENV}/keycloak/clients/organization" \
  ClientSecret="${ORGANIZATION_KEYCLOAK_CLIENT_SECRET:-TODO: client secret de organization en Keycloak PRE (igual al de postgresql/organization arriba)}"
echo "  ✓ keycloak/clients/organization"

vault kv put "secret/rni/${ENV}/keycloak/clients/gateway" \
  ClientSecret="${GATEWAY_KEYCLOAK_CLIENT_SECRET:-TODO: client secret de apigateway en Keycloak PRE}" \
  InternalClientSecret="${GATEWAY_INTERNAL_CLIENT_SECRET:-TODO: internal client secret}" \
  AccessKey="${GATEWAY_ACCESS_KEY:-0DdrT08xEM}" \
  JwtSecret="${GATEWAY_JWT_SECRET:-TODO: JWT signing secret RS256}"
echo "  ✓ keycloak/clients/gateway (AccessKey tomado de version/pre-master.yml: apiGateway__internalAccessKey)"

# ============================================================
# Redis
# ============================================================

vault kv put "secret/rni/${ENV}/redis/security" \
  Password="${REDIS_SECURITY_PASS}" \
  REDIS_PASSWORD="${REDIS_SECURITY_PASS}" \
  ConnectionString="redis-security-service.pre-master.svc.cluster.local:6379,password=${REDIS_SECURITY_PASS}"
echo "  ✓ redis/security"

vault kv put "secret/rni/${ENV}/redis/notifications" \
  REDIS_PASSWORD="${REDIS_NOTIFICATIONS_PASS}"
echo "  ✓ redis/notifications"

vault kv put "secret/rni/${ENV}/redis/versionmanager" \
  REDIS_PASSWORD="${REDIS_VERSIONMANAGER_PASS}"
echo "  ✓ redis/versionmanager"

# ============================================================
# Azure Monitor (sin consumidor propio — ver nota en postgresql/organization)
# ============================================================

vault kv put "secret/rni/${ENV}/azure/monitor" \
  ConnectionString="${AZURE_MONITOR_CONNECTION_STRING:-TODO: InstrumentationKey=XXXX;IngestionEndpoint=https://...}"
echo "  ✓ azure/monitor"

# ============================================================
# MINSAL EMPI
# ============================================================

vault kv put "secret/rni/${ENV}/minsal/empi" \
  ClientId="${MINSAL_CLIENT_ID:-TODO: client id MINSAL}" \
  ClientSecret="${MINSAL_CLIENT_SECRET:-TODO: client secret MINSAL}"
echo "  ✓ minsal/empi"

# ============================================================
# OPA (sin consumidor propio hoy — ver nota en secrets-backend-vault-azure.md)
# ============================================================

vault kv put "secret/rni/${ENV}/opa/auth" \
  admin_token="${OPA_ADMIN_TOKEN:-TODO: JWT token de admin OPA}" \
  api_key="${OPA_API_KEY:-TODO: API key OPA}" \
  jwt_secret="${OPA_JWT_SECRET:-TODO: JWT secret para validar tokens}" \
  jwt_issuer="${KEYCLOAK_ISSUER}" \
  jwt_audience="opa-service"
echo "  ✓ opa/auth"

echo ""
echo "✅ Secretos PRE cargados en secret/rni/${ENV}/."
echo ""
echo "🔑 Passwords internas autogeneradas — guardarlas YA en el gestor de secretos"
echo "   corporativo, no quedan en ningún otro lado:"
echo "   RABBIT_ADMIN_PASS=${RABBIT_ADMIN_PASS}"
echo "   RABBIT_ORG_PASS=${RABBIT_ORG_PASS}"
echo "   RABBIT_PATIENT_PASS=${RABBIT_PATIENT_PASS}"
echo "   RABBIT_VACCINATION_PASS=${RABBIT_VACCINATION_PASS}"
echo "   RABBIT_AUDIT_CONSUMER_PASS=${RABBIT_AUDIT_CONSUMER_PASS}"
echo "   RABBIT_AUDIT_PRODUCER_PASS=${RABBIT_AUDIT_PRODUCER_PASS}"
echo "   RABBIT_REPORTING_PASS=${RABBIT_REPORTING_PASS}"
echo "   RABBIT_NOTIF_ADMIN_PASS=${RABBIT_NOTIF_ADMIN_PASS}"
echo "   RABBIT_NOTIF_COOKIE=${RABBIT_NOTIF_COOKIE}"
echo "   RABBIT_NOTIF_SERVICE_PASS=${RABBIT_NOTIF_SERVICE_PASS}"
echo "   RABBIT_EMAIL_SERVICE_PASS=${RABBIT_EMAIL_SERVICE_PASS}"
echo "   RABBIT_SMS_SERVICE_PASS=${RABBIT_SMS_SERVICE_PASS}"
echo "   RABBIT_MONITORING_PASS=${RABBIT_MONITORING_PASS}"
echo "   RABBIT_SECURITY_ADMIN_PASS=${RABBIT_SECURITY_ADMIN_PASS}"
echo "   RABBIT_SECURITY_COOKIE=${RABBIT_SECURITY_COOKIE}"
echo "   RABBIT_APIGATEWAY_PASS=${RABBIT_APIGATEWAY_PASS}"
echo "   REDIS_SECURITY_PASS=${REDIS_SECURITY_PASS}"
echo "   REDIS_NOTIFICATIONS_PASS=${REDIS_NOTIFICATIONS_PASS}"
echo "   REDIS_VERSIONMANAGER_PASS=${REDIS_VERSIONMANAGER_PASS}"
echo ""
echo "⚠️  IMPORTANTE — estos users de RabbitMQ (admin, svc-organization, svc-patient,"
echo "   svc-vaccination, svc-audit-consumer, svc-audit-producer, svc-reporting,"
echo "   notifications_service, email_service, sms_service, monitoring_user,"
echo "   apigateway_user) todavía NO EXISTEN en los brokers reales de PRE — estas"
echo "   passwords quedan en Vault, pero hay que crear/actualizar esos usuarios en"
echo "   RabbitMQ (via definitions.json en el primer arranque, o rabbitmqctl si el"
echo "   broker ya está corriendo) con estos mismos valores."
echo ""
echo "⚠️  Valores pendientes con placeholder \"TODO\" — resolver con valores reales"
echo "   ANTES de dar PRE por operativo (no dejar en TODO como en dev/qa):"
echo "   - Keycloak__ClientSecret de organization (\$ORGANIZATION_KEYCLOAK_CLIENT_SECRET)"
echo "   - AzureMonitor__ConnectionString (\$AZURE_MONITOR_CONNECTION_STRING)"
echo "   - Keycloak ClientSecret/InternalClientSecret/JwtSecret de gateway"
echo "     (\$GATEWAY_KEYCLOAK_CLIENT_SECRET / \$GATEWAY_INTERNAL_CLIENT_SECRET / \$GATEWAY_JWT_SECRET)"
echo "   - ConnectionStrings__VaccinationRead de reporting — requiere crear antes un"
echo "     usuario de PostgreSQL de solo lectura real sobre vaccinationdb_write"
echo "     (\$REPORTING_VACCINATION_READ_CONNECTION)"
echo "   - DB_PASSWORD legado de patient (\$PATIENT_DB_PASSWORD_LEGACY)"
echo "   - MINSAL ClientId/ClientSecret (\$MINSAL_CLIENT_ID / \$MINSAL_CLIENT_SECRET)"
echo "   - OPA admin_token/api_key/jwt_secret (sin consumidor todavía, no bloquea el arranque)"
