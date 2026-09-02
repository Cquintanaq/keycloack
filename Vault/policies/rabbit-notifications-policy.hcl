path "secret/data/rni/dev/rabbitmq/notifications-infra" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/rabbitmq/notifications-infra" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/rabbitmq/notifications-infra" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
