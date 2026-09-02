path "secret/data/rni/dev/postgresql/integrations" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/postgresql/integrations" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/postgresql/integrations" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/minsal/empi" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/minsal/empi" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/minsal/empi" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/rabbitmq/integrations" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/rabbitmq/integrations" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/rabbitmq/integrations" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/keycloak/clients/integrations" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/keycloak/clients/integrations" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/keycloak/clients/integrations" {
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
