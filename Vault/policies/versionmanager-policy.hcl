path "secret/data/rni/dev/postgresql/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/postgresql/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/postgresql/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/rabbitmq/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/rabbitmq/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/rabbitmq/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/redis/backend" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/redis/backend" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/redis/backend" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/keycloak/clients/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/keycloak/clients/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/keycloak/clients/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/azure/monitor" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/azure/monitor" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/azure/monitor" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
