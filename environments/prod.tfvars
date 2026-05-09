environment         = "prod"
location            = "eastus"
resource_group_name = "rg-aks-prod"
cluster_name        = "aks-prod"
kubernetes_version  = "1.29"
vpc_name            = "vpc-aks-prod"
subnet_cidr         = "10.0.0.0/20"

system_node_pool = {
  name       = "system"
  node_count = 2
  vm_size    = "Standard_D2s_v3"
}

user_node_pool = {
  name                = "user"
  vm_size             = "Standard_D4s_v3"
  min_count           = 2
  max_count           = 10
  enable_auto_scaling = true
}

enable_oidc_issuer       = true
enable_workload_identity = true

log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-aks-prod"
