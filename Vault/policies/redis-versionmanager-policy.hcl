path "secret/data/rni/dev/redis/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/redis/versionmanager" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/redis/versionmanager" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
