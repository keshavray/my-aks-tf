terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
    }
  }

  required_version = ">= 0.14.9"
}

resource "azurerm_user_assigned_identity" "aks_identity" {
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  name = "${var.name}Identity"

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_kubernetes_cluster" "aks_cluster" {
  name                      = var.name
  location                  = var.location
  resource_group_name       = var.resource_group_name
  kubernetes_version        = var.kubernetes_version
  dns_prefix                = var.dns_prefix
  private_cluster_enabled   = var.private_cluster_enabled
  automatic_channel_upgrade = var.automatic_channel_upgrade
  sku_tier                  = var.sku_tier

  default_node_pool {
    name                   = var.default_node_pool_name
    vm_size                = var.default_node_pool_vm_size
    vnet_subnet_id         = var.vnet_subnet_id
    availability_zones     = var.default_node_pool_availability_zones
    enable_auto_scaling    = var.default_node_pool_enable_auto_scaling
    enable_host_encryption = var.default_node_pool_enable_host_encryption
    enable_node_public_ip  = var.default_node_pool_enable_node_public_ip
    max_pods               = var.default_node_pool_max_pods
    max_count              = var.default_node_pool_max_count
    min_count              = var.default_node_pool_min_count
    node_count             = var.default_node_pool_node_count
    os_disk_type           = var.default_node_pool_os_disk_type
    tags                   = var.tags
  }


  identity {
    type = "UserAssigned"
    user_assigned_identity_id = azurerm_user_assigned_identity.aks_identity.id
  }

  network_profile {
    docker_bridge_cidr = var.network_docker_bridge_cidr
    dns_service_ip     = var.network_dns_service_ip
    network_plugin     = var.network_plugin
    outbound_type      = var.outbound_type
    service_cidr       = var.network_service_cidr
  }

  addon_profile {
    ingress_application_gateway {
      enabled                    = true
      subnet_id                  = var.ingress_application_gateway_subnet_id
    }
    aci_connector_linux {
      enabled                    = var.aci_connector_linux.enabled
      subnet_name                = var.aci_connector_linux.subnet_name
    }
    azure_policy {
      enabled                    = var.azure_policy.enabled
    }
    http_application_routing {
      enabled                    = var.http_application_routing.enabled
    }
    kube_dashboard {
      enabled                    = var.kube_dashboard.enabled
    }
  }
  
  role_based_access_control {
    enabled = var.role_based_access_control_enabled

    azure_active_directory {
      managed                = true
      tenant_id              = var.tenant_id
      admin_group_object_ids = var.admin_group_object_ids
      azure_rbac_enabled     = var.azure_rbac_enabled
    }
  }

  lifecycle {
    ignore_changes = [
      kubernetes_version,
      tags
    ]
  }
}
