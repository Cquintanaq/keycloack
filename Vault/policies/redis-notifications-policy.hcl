path "secret/data/rni/dev/redis/notifications" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/redis/notifications" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/redis/notifications" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
