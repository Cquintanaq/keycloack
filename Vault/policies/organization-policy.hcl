path "secret/data/rni/dev/postgresql/organization" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/postgresql/organization" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/postgresql/organization" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/keycloak/clients/organization" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/keycloak/clients/organization" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/keycloak/clients/organization" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/rabbitmq/backend" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/rabbitmq/backend" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/rabbitmq/backend" {
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
