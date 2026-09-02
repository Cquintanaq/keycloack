path "secret/data/rni/dev/postgresql/patient" {
  capabilities = ["read"]
}
path "secret/data/rni/qa/postgresql/patient" {
  capabilities = ["read"]
}
path "secret/data/rni/pre/postgresql/patient" {
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
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
