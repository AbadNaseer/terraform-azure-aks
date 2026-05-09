resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.cluster_name}-dns"
  kubernetes_version  = var.kubernetes_version

  # System node pool — reserved for kube-system pods
  default_node_pool {
    name                 = var.system_node_pool.name
    node_count           = var.system_node_pool.node_count
    vm_size              = var.system_node_pool.vm_size
    vnet_subnet_id       = var.subnet_id
    only_critical_addons_enabled = true
    os_disk_size_gb      = 50
    os_disk_type         = "Ephemeral"
    zones                = ["1", "2", "3"]

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # OIDC + Workload Identity
  oidc_issuer_enabled       = var.enable_oidc_issuer
  workload_identity_enabled = var.enable_workload_identity

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  azure_policy_enabled = true

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  maintenance_window {
    allowed {
      day   = "Sunday"
      hours = [2, 3, 4]
    }
  }

  auto_scaler_profile {
    balance_similar_node_groups      = true
    expander                         = "least-waste"
    scale_down_delay_after_add       = "10m"
    scale_down_unneeded              = "10m"
    scale_down_utilization_threshold = "0.5"
  }

  tags = var.tags
}

# User node pool — workload pods
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = var.user_node_pool.name
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.user_node_pool.vm_size
  vnet_subnet_id        = var.subnet_id
  enable_auto_scaling   = var.user_node_pool.enable_auto_scaling
  min_count             = var.user_node_pool.min_count
  max_count             = var.user_node_pool.max_count
  os_disk_type          = "Ephemeral"
  zones                 = ["1", "2", "3"]

  node_labels = {
    "workload-type" = "application"
  }

  upgrade_settings {
    max_surge = "33%"
  }

  tags = var.tags
}
