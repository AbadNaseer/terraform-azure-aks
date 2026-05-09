# terraform-azure-aks

Production-ready **Azure Kubernetes Service (AKS)** cluster provisioned with **Terraform**. Includes system and user node pools, Azure CNI networking, Workload Identity, Azure Monitor integration, and Key Vault secrets management.

## Architecture

```
Azure Subscription
└── Resource Group: rg-aks-prod
    ├── AKS Cluster (aks-prod)
    │   ├── System Node Pool  (Standard_D2s_v3 × 2, reserved for system pods)
    │   └── User Node Pool    (Standard_D4s_v3 × 2–10, auto-scaled)
    ├── Azure Container Registry (ACR)
    ├── Azure Key Vault (secrets + TLS certs)
    ├── Log Analytics Workspace (Container Insights)
    ├── Virtual Network + Subnets (Azure CNI)
    └── Managed Identity (Workload Identity for pod-level Azure RBAC)
```

## Stack

| Component | Tool |
|-----------|------|
| IaC | Terraform >= 1.5 |
| Provider | hashicorp/azurerm ~> 3.90 |
| CNI | Azure CNI |
| Identity | Workload Identity (OIDC) |
| Secrets | External Secrets Operator + Azure Key Vault |
| Monitoring | Azure Monitor Container Insights + Prometheus |
| Ingress | Nginx Ingress Controller |
| TLS | cert-manager + Let's Encrypt |

## Repository Structure

```
terraform-azure-aks/
├── main.tf                 # Root module: resource group, AKS, ACR
├── variables.tf
├── outputs.tf
├── providers.tf            # AzureRM + Kubernetes providers
├── versions.tf
├── modules/
│   ├── aks/
│   │   ├── main.tf         # AKS cluster, node pools, OIDC issuer
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── networking/
│   │   ├── main.tf         # VNet, subnets, NSGs
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── keyvault/
│       ├── main.tf         # Key Vault + access policies
│       ├── variables.tf
│       └── outputs.tf
├── environments/
│   ├── dev.tfvars
│   ├── staging.tfvars
│   └── prod.tfvars
├── .github/
│   └── workflows/
│       ├── terraform-plan.yaml   # PR: terraform plan
│       └── terraform-apply.yaml  # Main: terraform apply
└── README.md
```

## Quick Start

### Prerequisites
```bash
az login
az account set --subscription "<SUBSCRIPTION_ID>"
terraform -v   # >= 1.5.0
```

### Create backend (one-time)
```bash
# Storage account for remote state
az group create --name rg-terraform-state --location eastus
az storage account create --name stterraformaks --resource-group rg-terraform-state \
  --sku Standard_LRS --encryption-services blob
az storage container create --name tfstate --account-name stterraformaks
```

### Deploy
```bash
cd terraform-azure-aks/

terraform init \
  -backend-config="storage_account_name=stterraformaks" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=prod.terraform.tfstate"

terraform plan -var-file="environments/prod.tfvars" -out=tfplan
terraform apply tfplan
```

### Connect to cluster
```bash
az aks get-credentials --resource-group rg-aks-prod --name aks-prod
kubectl get nodes
```

## Key Variables (`prod.tfvars`)

```hcl
environment         = "prod"
location            = "eastus"
resource_group_name = "rg-aks-prod"
cluster_name        = "aks-prod"
kubernetes_version  = "1.29"

system_node_pool = {
  name       = "system"
  node_count = 2
  vm_size    = "Standard_D2s_v3"
}

user_node_pool = {
  name           = "user"
  min_count      = 2
  max_count      = 10
  vm_size        = "Standard_D4s_v3"
  enable_auto_scaling = true
}

network_plugin     = "azure"
network_policy     = "calico"
enable_oidc_issuer = true
enable_workload_identity = true
log_analytics_workspace_id = "/subscriptions/.../workspaces/law-aks-prod"
```

## Workload Identity Setup

```bash
# Create managed identity
az identity create --name mi-api-service --resource-group rg-aks-prod

# Federate with Kubernetes service account
az identity federated-credential create \
  --name fc-api-service \
  --identity-name mi-api-service \
  --resource-group rg-aks-prod \
  --issuer "$(terraform output -raw oidc_issuer_url)" \
  --subject "system:serviceaccount:default:api-service-sa"

# Grant Key Vault access
az keyvault set-policy --name kv-aks-prod \
  --object-id "$(az identity show --name mi-api-service -g rg-aks-prod --query principalId -o tsv)" \
  --secret-permissions get list
```

## CI/CD (GitHub Actions)

```yaml
# .github/workflows/terraform-plan.yaml (excerpt)
- name: Terraform Plan
  run: |
    terraform plan \
      -var-file="environments/prod.tfvars" \
      -out=tfplan \
      -detailed-exitcode
  env:
    ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
    ARM_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
    ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
```

## Cost Optimization

- System pool uses spot-ineligible SKU (system pods require stable nodes)
- User pool runs Spot VMs in dev/staging (`priority = "Spot"`, `eviction_policy = "Delete"`)
- Cluster autoscaler removes underutilized nodes after 10 min
- Azure Advisor recommendations reviewed weekly

## Outputs

```hcl
output "kube_config"           # Base64 kubeconfig (sensitive)
output "cluster_fqdn"          # AKS API server FQDN
output "oidc_issuer_url"       # For Workload Identity federation
output "acr_login_server"      # Container registry URL
output "node_resource_group"   # MC_ resource group
```
