resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = local.common_tags
}

module "networking" {
  source = "./modules/networking"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  environment         = var.environment
  vpc_name            = var.vpc_name
  subnet_cidr         = var.subnet_cidr
  tags                = local.common_tags
}

module "aks" {
  source = "./modules/aks"

  resource_group_name    = azurerm_resource_group.main.name
  location               = var.location
  cluster_name           = var.cluster_name
  kubernetes_version     = var.kubernetes_version
  environment            = var.environment
  subnet_id              = module.networking.aks_subnet_id
  system_node_pool       = var.system_node_pool
  user_node_pool         = var.user_node_pool
  log_analytics_workspace_id = var.log_analytics_workspace_id
  enable_oidc_issuer     = var.enable_oidc_issuer
  enable_workload_identity = var.enable_workload_identity
  tags                   = local.common_tags
}

module "keyvault" {
  source = "./modules/keyvault"

  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  environment         = var.environment
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.common_tags
}

resource "azurerm_container_registry" "main" {
  name                = "acr${var.environment}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Premium"
  admin_enabled       = false

  georeplications {
    location                = "westeurope"
    zone_redundancy_enabled = true
  }

  tags = local.common_tags
}

# Grant AKS kubelet identity pull access to ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = module.aks.kubelet_identity_object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "aks-platform"
    Owner       = "platform-team"
  }
}
