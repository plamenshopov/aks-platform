################################################################################
# Virtual network, subnets, network security groups and private DNS.
#
# Subnet layout:
#   10.60.0.0/22   system node pool      (1022 usable — sized for overlay CNI)
#   10.60.4.0/22   user node pool        (1022 usable)
#   10.60.8.0/24   private endpoints
#   10.60.9.0/24   ingress tier          (reserved, no resources yet)
#
# Pod addresses come from an overlay CIDR and are not routable on this network,
# so node subnets only need to be sized for nodes and private endpoints, not for
# pods.
################################################################################

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

################################################################################
# Subnets
################################################################################

resource "azurerm_subnet" "system_nodes" {
  name                 = "snet-system-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_system_nodes_cidr]

  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
  ]
}

resource "azurerm_subnet" "user_nodes" {
  name                 = "snet-user-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_user_nodes_cidr]

  service_endpoints = [
    "Microsoft.Storage",
    "Microsoft.KeyVault",
  ]
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_private_endpoints_cidr]

  # Network policies stay disabled on this subnet so that private endpoint
  # traffic is not filtered before it reaches the endpoint NIC.
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet" "ingress" {
  name                 = "snet-ingress"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_ingress_cidr]
}

################################################################################
# Network security groups
#
# AKS manages its own rules on the node network interfaces. The rules below are
# additive and documentary: they make the expected traffic explicit for auditors
# without narrowing anything AKS relies on. Adding deny rules to a node subnet
# is a well-known way to break cluster provisioning — do not do it here without
# validating against the AKS outbound requirements first.
################################################################################

resource "azurerm_network_security_group" "system_nodes" {
  name                = "nsg-${local.name_prefix}-system-nodes"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowVnetInbound"
    description                = "Intra-cluster and cross-subnet traffic within the platform network."
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    description                = "Health probes from the Azure load balancer."
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    description                = "Control plane, image pulls and Azure service dependencies."
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowNtpOutbound"
    description                = "Time synchronisation. Clock skew breaks token validation."
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "123"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "user_nodes" {
  name                = "nsg-${local.name_prefix}-user-nodes"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowVnetInbound"
    description                = "Intra-cluster and cross-subnet traffic within the platform network."
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerInbound"
    description                = "Health probes from the Azure load balancer."
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAzureCloudOutbound"
    description                = "Control plane, image pulls and Azure service dependencies."
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureCloud"
  }

  security_rule {
    name                       = "AllowNtpOutbound"
    description                = "Time synchronisation. Clock skew breaks token validation."
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "123"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "ingress" {
  name                = "nsg-${local.name_prefix}-ingress"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowHttpsInbound"
    description                = "Public HTTPS to the ingress tier."
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGatewayManagerInbound"
    description                = "Azure control traffic for the managed gateway."
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyAllOtherInbound"
    description                = "Everything not explicitly permitted above is dropped."
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

################################################################################
# Network security group associations
################################################################################

resource "azurerm_subnet_network_security_group_association" "system_nodes" {
  subnet_id                 = azurerm_subnet.system_nodes.id
  network_security_group_id = azurerm_network_security_group.system_nodes.id
}

resource "azurerm_subnet_network_security_group_association" "user_nodes" {
  subnet_id                 = azurerm_subnet.user_nodes.id
  network_security_group_id = azurerm_network_security_group.user_nodes.id
}

resource "azurerm_subnet_network_security_group_association" "ingress" {
  subnet_id                 = azurerm_subnet.ingress.id
  network_security_group_id = azurerm_network_security_group.ingress.id
}

################################################################################
# Private DNS
#
# One zone for the storage private endpoint and one internal zone that
# external-dns writes service records into from inside the cluster.
################################################################################

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-${local.name_prefix}-blob"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_zone" "internal" {
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "internal" {
  name                  = "link-${local.name_prefix}-internal"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = local.common_tags
}
