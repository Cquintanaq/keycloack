path "secret/data/rni/dev/opa/auth" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/opa/auth" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/opa/auth" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
