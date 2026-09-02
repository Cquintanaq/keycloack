path "secret/data/rni/dev/postgresql/practitioner" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/postgresql/practitioner" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/postgresql/practitioner" {
  capabilities = ["read"]
}
path "secret/data/rni/dev/keycloak/clients/gateway" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/keycloak/clients/gateway" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/keycloak/clients/gateway" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
