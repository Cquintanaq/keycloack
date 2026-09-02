path "secret/data/rni/dev/*" {
  capabilities = ["read", "list"]
}
path "secret/data/rni/qa/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/rni/dev/*" {
  capabilities = ["list"]
}
path "secret/metadata/rni/qa/*" {
  capabilities = ["list"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
