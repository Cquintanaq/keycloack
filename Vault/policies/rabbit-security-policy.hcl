path "secret/data/rni/dev/rabbitmq/security" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/rabbitmq/security" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/rabbitmq/security" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
