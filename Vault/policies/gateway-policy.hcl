path "secret/data/rni/dev/keycloak/clients/gateway" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/keycloak/clients/gateway" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/keycloak/clients/gateway" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/rabbitmq/security" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/rabbitmq/security" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/rabbitmq/security" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/redis/security" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/redis/security" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/redis/security" {
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
