#!/usr/bin/env bash
# Carga inicial de secretos en Vault QA.
# Valores extraídos en vivo de los Secrets/ConfigMaps reales de qa-sprint-1 (worker-qa).
# NUNCA commitear este archivo — está en .gitignore.
#
# IMPORTANTE: las claves de cada `vault kv put` deben coincidir EXACTAMENTE
# con lo que cada agent-inject-template lee en los manifiestos K8s — son los
# MISMOS manifiestos que usa dev (configurador.py reescribe automáticamente
# rni/dev/... -> rni/qa/... y auth/kubernetes-dev -> auth/kubernetes-qa al
# generar el output para namespace QA), así que las claves deben ser
# idénticas a las de load-secrets-dev.sh.
#
# Uso:
#   export VAULT_ADDR=http://localhost:8200
#   export VAULT_TOKEN=<root-token-qa>
#   bash load-secrets-qa.sh

set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:?Definir VAULT_ADDR}"
VAULT_TOKEN="${VAULT_TOKEN:?Definir VAULT_TOKEN}"
ENV="qa"

export VAULT_ADDR VAULT_TOKEN

# Servidor PostgreSQL compartido de QA — confirmado en version/qa-sprint-1.yml
# y en los Secret K8s reales de qa-sprint-1.
DB_HOST="172.16.1.74"
DB_PORT="5432"
DB_USER="RNI_QA_BD"
DB_PASS="Rayen2026\$"

echo "==> Cargando secretos en secret/rni/${ENV}/..."

# ============================================================
# PostgreSQL
# ============================================================

# Confirmado real en miniservice-organization-secrets (qa-sprint-1).
# AzureMonitor__ConnectionString: real (no placeholder) pero el InstrumentationKey
# fue redactado al leerlo — copiar el valor real desde Rancher si hace falta usarlo.
# Keycloak__ClientSecret: placeholder sin sustituir en vivo (${KC_CLIENT_SECRET}) —
# nunca se configuró un valor real, igual que en dev.
vault kv put "secret/rni/${ENV}/postgresql/organization" \
  ConnectionStrings__ReadWriteConnection="Host=${DB_HOST};Port=${DB_PORT};Database=organizationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Host=${DB_HOST};Port=${DB_PORT};Database=organizationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  Keycloak__ClientSecret="TODO: client secret de organization en Keycloak QA" \
  AzureMonitor__ConnectionString="TODO: copiar el valor real desde Rancher > Secret miniservice-organization-secrets (existe en vivo, redactado para mí)"
echo "  ✓ postgresql/organization"

# Confirmado real en miniservice-patient-secrets. DB_PASSWORD="postgres" (plano,
# distinto del password compartido) igual que en dev — se mantiene el valor real.
vault kv put "secret/rni/${ENV}/postgresql/patient" \
  ConnectionStrings__ReadWriteConnection="Host=${DB_HOST};Port=${DB_PORT};Database=patientdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Host=${DB_HOST};Port=${DB_PORT};Database=patientdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  DB_PASSWORD="postgres"
echo "  ✓ postgresql/patient"

# Confirmado real en miniservice-practitioner-secrets — solo DB_PASSWORD.
vault kv put "secret/rni/${ENV}/postgresql/practitioner" \
  ConnectionStrings__ReadWriteConnection="Host=${DB_HOST};Port=${DB_PORT};Database=practitionerdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Host=${DB_HOST};Port=${DB_PORT};Database=practitionerdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  DB_PASSWORD="postgres"
echo "  ✓ postgresql/practitioner"

# Confirmado real en miniservice-vaccination-secrets.
# Buckets A-D: fix pragmático 2026-07-24 — el feature de bucketing/sharding real
# nunca se terminó de diseñar (tampoco existe en dev), así que los 4 buckets
# apuntan a la MISMA conexión base por ahora (decisión explícita del usuario,
# revisar el diseño real de sharding el próximo lunes). Sin esto la app no
# levanta: BucketConnectionExtensions.AddImmunizationBucketing revienta con
# "Format of the initialization string does not conform to specification" si
# falta cualquiera de estas 8 claves.
vault kv put "secret/rni/${ENV}/postgresql/vaccination" \
  ConnectionStrings__ReadWriteConnection="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnection="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketA="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketA="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketB="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketB="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketC="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketC="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadWriteConnectionBucketD="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__ReadOnlyConnectionBucketD="Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true"
echo "  ✓ postgresql/vaccination (buckets A-D apuntando a la conexión base — pendiente diseño real de sharding)"

# Agregado 2026-07-24 — nunca existió en QA (servicio nuevo del sprint 7,
# "reporting" no estaba en la lista de servicios cuando se armó este script
# originalmente). Mismas claves que load-secrets-dev.sh.
# NOTA 2026-07-27: la base real se llama "reportingdb" (sin sufijo _write) en
# DEV y QA — confirmado con el equipo de desarrollo, no afecta en nada usar
# el nombre real en vez de seguir la convención "_write" de los demás servicios.
vault kv put "secret/rni/${ENV}/postgresql/reporting" \
  ConnectionStrings__ReportingDb="Host=${DB_HOST};Port=${DB_PORT};Database=reportingdb;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__VaccinationRead="TODO: crear usuario de solo lectura real sobre vaccinationdb_write — Host=${DB_HOST};Port=${DB_PORT};Database=vaccinationdb_write;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true"
echo "  ✓ postgresql/reporting"

# Confirmado real en miniservice-notifications-secret (qa-sprint-1).
# NOTA: RABBITMQ_USER/PASS reales en vivo son "notifications_user"/"notifications_secure_2026"
# — a diferencia de dev, en QA el broker de notifications NUNCA se migró a Vault
# (sigue con RABBITMQ_DEFAULT_USER=admin), así que aquí no hay el mismo problema
# de usuario "stale" que encontramos en dev. Usar el valor real tal cual.
vault kv put "secret/rni/${ENV}/postgresql/notifications" \
  NotificationsDb="Host=${DB_HOST};Port=${DB_PORT};Database=notifications_write;Username=${DB_USER};Password=${DB_PASS};Search Path=notifications;Include Error Detail=true" \
  JWT_ALGORITHM="RS256" \
  KEYCLOAK_ISSUER="http://keycloak.qa-sprint-1.svc.cluster.local:8080/realms/rni-realm" \
  RABBITMQ_HOST="rabbit-notifications.qa-sprint-1.svc.cluster.local" \
  RABBITMQ_PASS="notifications_secure_2026" \
  RABBITMQ_PORT="5672" \
  RABBITMQ_USER="notifications_user" \
  REDIS_HOST="redis-notifications-service.qa-sprint-1.svc.cluster.local" \
  REDIS_PORT="6379"
echo "  ✓ postgresql/notifications"

# Confirmado real en miniservice-versionmanager-secrets — ambas claves con el
# mismo valor (igual patrón que dev, tras la corrección que hicimos ahí).
vault kv put "secret/rni/${ENV}/postgresql/versionmanager" \
  database-connection="Host=${DB_HOST};Port=${DB_PORT};Database=versioning;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  ConnectionStrings__VersionesDb="Host=${DB_HOST};Port=${DB_PORT};Database=versioning;Username=${DB_USER};Password=${DB_PASS};Include Error Detail=true"
echo "  ✓ postgresql/versionmanager"

# Confirmado real en audit-consumer-secrets / audit-producer-secrets.
# ⚠️ MessageBroker__Password en ambos secrets sigue como placeholder sin sustituir
# (${RABBIT_CONSUMER_PASS} / ${RABBIT_PRODUCER_PASS}) — mismo problema que
# encontramos en dev con audit-consumer. La base "bd_practitioner_audit" además
# hay que confirmar si existe realmente en 172.16.1.74 (en dev NO existía bajo
# ese nombre) antes de dar esto por funcional — dejo el valor real tal cual está
# hoy, pero el consumidor probablemente falle igual que en dev hasta que se
# resuelva esa base y esas passwords.
vault kv put "secret/rni/${ENV}/postgresql/audit" \
  consumer_primary="Server=${DB_HOST};Port=${DB_PORT};Database=bd_practitioner_audit;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_replica="Server=${DB_HOST};Port=${DB_PORT};Database=bd_practitioner_audit;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_analytics="Server=${DB_HOST};Port=${DB_PORT};Database=bd_practitioner_audit;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  consumer_broker_host="rabbitmq://rabbit-general-backend.qa-sprint-1.svc.cluster.local" \
  consumer_broker_user="svc-audit-consumer" \
  consumer_broker_password="TODO: resolver \${RABBIT_CONSUMER_PASS} sin sustituir en vivo" \
  producer_listener_0="Server=${DB_HOST};Port=${DB_PORT};Database=organizationdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_listener_1="Server=${DB_HOST};Port=${DB_PORT};Database=patientdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_listener_2="Server=${DB_HOST};Port=${DB_PORT};Database=practitionerdb_write;User Id=${DB_USER};Password=${DB_PASS};Include Error Detail=true" \
  producer_broker_host="rabbitmq://rabbit-general-backend.qa-sprint-1.svc.cluster.local" \
  producer_broker_user="svc-audit-producer" \
  producer_broker_password="TODO: resolver \${RABBIT_PRODUCER_PASS} sin sustituir en vivo"
echo "  ✓ postgresql/audit"

# ============================================================
# RabbitMQ
# ============================================================

# NOTA: a diferencia de dev, el broker rabbit-general-backend de QA NUNCA se
# migró a Vault (sigue leyendo RABBITMQ_DEFAULT_USER/PASS de su propio Secret
# K8s en texto plano, admin-audit-2026). Cargamos igual este path porque los
# manifiestos compartidos (miniservice-vaccination.yml, etc.) SÍ lo leen para
# la password de la app — el admin_password de aquí NO se usa todavía por el
# broker mismo (eso es Fase 3, deliberadamente fuera de esta pasada).
# vaccination_password confirmado real en miniservice-vaccination-configmap
# (viene en el ConfigMap en texto plano hoy, no en Vault).
vault kv put "secret/rni/${ENV}/rabbitmq/backend" \
  admin_password="admin-audit-2026" \
  vaccination_password="vaccination_secret" \
  audit_consumer_password="TODO: resolver \${RABBIT_CONSUMER_PASS}" \
  audit_producer_password="TODO: resolver \${RABBIT_PRODUCER_PASS}" \
  reporting_user="svc-reporting" \
  reporting_password="TODO: el usuario svc-reporting ya existía en rabbit-general-backend-server-0; el 2026-07-24 se le reseteó la contraseña en vivo (rabbitmqctl change_password) porque no se podía leer la anterior, pero ese valor nunca se guardó en ningún lado (a propósito, para no exponerlo). Hay que volver a resetearla con VPN + kubectl exec y recién ahí poner el valor real acá."
echo "  ✓ rabbitmq/backend (reporting_password pendiente resync — ver TODO)"

# Confirmado real en rabbit-notifications-secret.
vault kv put "secret/rni/${ENV}/rabbitmq/notifications-infra" \
  admin_password="admin-notifications-2026" \
  erlang_cookie="rabbit-notifications-cookie-2026"
echo "  ✓ rabbitmq/notifications-infra"

# Confirmado real en rabbit-security-secret.
vault kv put "secret/rni/${ENV}/rabbitmq/security" \
  admin_password="admin-secure-2026" \
  erlang_cookie="rabbit-security-cookie-2026"
echo "  ✓ rabbitmq/security"

# ============================================================
# Keycloak
# ============================================================

vault kv put "secret/rni/${ENV}/keycloak/clients/organization" \
  ClientSecret="TODO: client secret de organization en Keycloak QA"
echo "  ✓ keycloak/clients/organization"

# Confirmado real en apigateway-secrets: Keycloak__ClientSecret y Jwt__Secret
# son placeholders/valores de ejemplo, no credenciales reales de Keycloak QA
# (igual que en dev).
vault kv put "secret/rni/${ENV}/keycloak/clients/gateway" \
  ClientSecret="TODO: client secret de apigateway en Keycloak QA" \
  InternalClientSecret="TODO: internal client secret" \
  AccessKey="0DdrT08xEM" \
  JwtSecret="TODO: JWT signing secret RS256"
echo "  ✓ keycloak/clients/gateway (AccessKey tomado de version/qa-master.yml: apiGateway__internalAccessKey)"

# ============================================================
# Redis
# ============================================================

# Confirmado real: los 3 Redis de QA comparten la MISMA password que dev
# (redis_strong_pass_2026) — mismo patrón de riesgo (falta de aislamiento por
# instancia), ya documentado como pendiente en dev también.
REDIS_QA_PASS="redis_strong_pass_2026"
vault kv put "secret/rni/${ENV}/redis/security" \
  Password="${REDIS_QA_PASS}" \
  REDIS_PASSWORD="${REDIS_QA_PASS}" \
  ConnectionString="redis-security-service.qa-sprint-1.svc.cluster.local:6379,password=${REDIS_QA_PASS}"
echo "  ✓ redis/security"

vault kv put "secret/rni/${ENV}/redis/notifications" \
  REDIS_PASSWORD="${REDIS_QA_PASS}"
echo "  ✓ redis/notifications"

vault kv put "secret/rni/${ENV}/redis/versionmanager" \
  REDIS_PASSWORD="${REDIS_QA_PASS}"
echo "  ✓ redis/versionmanager"

# ============================================================
# Azure Monitor
# ============================================================

vault kv put "secret/rni/${ENV}/azure/monitor" \
  ConnectionString="TODO: copiar desde Rancher > Secret miniservice-organization-secrets (redactado para mí)"
echo "  ✓ azure/monitor"

# ============================================================
# MINSAL EMPI
# ============================================================

# Confirmado real en miniservice-integrations-secrets: ambas claves vacías —
# MINSAL nunca se configuró en QA tampoco.
vault kv put "secret/rni/${ENV}/minsal/empi" \
  ClientId="TODO: client id MINSAL" \
  ClientSecret="TODO: client secret MINSAL"
echo "  ✓ minsal/empi"

# ============================================================
# OPA
# ============================================================

vault kv put "secret/rni/${ENV}/opa/auth" \
  admin_token="TODO: JWT token de admin OPA" \
  api_key="TODO: API key OPA" \
  jwt_secret="TODO: JWT secret para validar tokens" \
  jwt_issuer="TODO: https://keycloak.../realms/rni" \
  jwt_audience="opa-service"
echo "  ✓ opa/auth"

echo ""
echo "✅ Secretos QA cargados."
echo "   IMPORTANTE: los TODO marcados (Keycloak client secrets, MINSAL, OPA,"
echo "   AzureMonitor, y las passwords \${RABBIT_*_PASS} de audit) siguen sin"
echo "   resolver — mismos huecos que en dev, requieren valores reales del equipo"
echo "   antes de que esos flujos específicos funcionen end-to-end."
