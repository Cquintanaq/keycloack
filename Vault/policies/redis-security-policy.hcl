path "secret/data/rni/dev/redis/security" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/redis/security" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/redis/security" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
