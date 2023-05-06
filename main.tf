terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.60"
    }
  }
}



provider "azurerm" {
  features {}
}


locals {
  storage_account_prefix = "boot"
  route_table_name       = "DefaultRouteTable"
  route_name             = "RouteToAzureFirewall"
}

data "azurerm_client_config" "current" {
}

resource "azurerm_resource_group" "rg" {
  name     = "my-aks-rg"
  location = "westeurope"
}

module "aks_network" {
  source                       = "./modules/virtual_network"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = "westeurope"
  vnet_name                    = "aks-vnet"
  address_space                = ["10.0.0.0/16"]

  subnets = [
    {
      name : "default_node_pool_subnet_name"
      address_prefixes : ["10.0.0.0/21"]
      enforce_private_link_endpoint_network_policies : false
      enforce_private_link_service_network_policies : false
    },
    {
      name : "additional_node_pool_subnet_name"
      address_prefixes : ["10.0.16.0/20"]
      enforce_private_link_endpoint_network_policies : false
      enforce_private_link_service_network_policies : false
    },
  ]
}

module "container_registry" {
  source                       = "./modules/container_registry"
  name                         = "keshavaksacr"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = "westeurope"
  sku                          = "Basic"
  georeplication_locations     = ["eastus"]
}

module "routetable" {
  source               = "./modules/route_table"
  resource_group_name  = azurerm_resource_group.rg.name
  location             = "westeurope"
  route_table_name     = "aks-rt"
  route_name           = local.route_name
  subnets_to_associate = {
    ("default_node_pool_subnet_name") = {
      subscription_id      = data.azurerm_client_config.current.subscription_id
      resource_group_name  = azurerm_resource_group.rg.name
      virtual_network_name = module.aks_network.name
    }
    ("additional_node_pool_subnet_name") = {
      subscription_id      = data.azurerm_client_config.current.subscription_id
      resource_group_name  = azurerm_resource_group.rg.name
      virtual_network_name = module.aks_network.name
    }
  }
}

module "aks_cluster" {
  source                                   = "./modules/aks"
  name                                     = "my-aks-cluster"
  location                                 = "westeurope"
  resource_group_name                      = azurerm_resource_group.rg.name
  resource_group_id                        = azurerm_resource_group.rg.id
  kubernetes_version                       = "1.22.6"
  dns_prefix                               = "my-aks-cluster"
  private_cluster_enabled                  = false
  automatic_channel_upgrade                = "stable"
  sku_tier                                 = "Free"
  default_node_pool_name                   = "defaultpool"
  default_node_pool_vm_size                = "Standard_B2s"
  vnet_subnet_id                           = module.aks_network.subnet_ids["default_node_pool_subnet_name"]
  default_node_pool_availability_zones     = ["1", "2", "3"]
  default_node_pool_enable_auto_scaling    = true
  default_node_pool_enable_host_encryption = false
  default_node_pool_enable_node_public_ip  = true
  default_node_pool_max_pods               = 200
  default_node_pool_max_count              = 3
  default_node_pool_min_count              = 2
  default_node_pool_node_count             = 2
  default_node_pool_os_disk_type           = "Managed"
  network_docker_bridge_cidr               = "172.17.0.1/16"
  network_dns_service_ip                   = "10.2.0.10"
  network_plugin                           = "azure"
  outbound_type                            = "loadBalancer"
  network_service_cidr                     = "10.2.0.0/24"
  role_based_access_control_enabled        = true
  tenant_id                                = data.azurerm_client_config.current.tenant_id
  admin_group_object_ids                   = ["cc636be7-1d36-4cc4-a709-541271bb49e6"]
  azure_rbac_enabled                       = true
  admin_username                           = "keshav"
  ssh_public_key                           = "keshav"
  depends_on                               = [module.routetable]
  ingress_application_gateway_subnet_id    = module.aks_network.subnet_ids["additional_node_pool_subnet_name"]
}

resource "azurerm_role_assignment" "network_contributor" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Network Contributor"
  principal_id         = module.aks_cluster.aks_identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "acr_pull" {
  role_definition_name = "AcrPull"
  scope                = module.container_registry.id
  principal_id         = module.aks_cluster.kubelet_identity_object_id
  skip_service_principal_aad_check = true
}
