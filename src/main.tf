terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.41.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "1.9.1"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "random_string" "unique" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${random_string.unique.result}"
  location = "West Europe"
}

resource "azurerm_eventhub_namespace" "evhns" {
  name                = "evhns-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_eventhub" "evh" {
  name                = "evh-${random_string.unique.result}"
  namespace_name      = azurerm_eventhub_namespace.evhns.name
  resource_group_name = azurerm_resource_group.rg.name
  partition_count     = 3
  message_retention   = 1
}

# https://learn.microsoft.com/en-us/sql/relational-databases/security/password-policy?redirectedfrom=MSDN&view=sql-server-ver16#password-complexity
resource "random_password" "sql" {
  length           = 8
  special          = true
  override_special = "!$#%"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "azurerm_mssql_server" "sql" {
  name                         = "sql-${random_string.unique.result}"
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = random_password.sql.result
}

# Allow access to Azure services
resource "azurerm_mssql_firewall_rule" "sql" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_database" "sqldb" {
  name      = "sqldb-${random_string.unique.result}"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "S0"
}

resource "azurerm_container_group" "ci" {
  name                = "ci-${random_string.unique.result}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"

  container {
    name   = "iot-telemetry-simulator"
    image  = "mcr.microsoft.com/oss/azure-samples/azureiot-telemetrysimulator"
    cpu    = "1.0"
    memory = "1.5"

    # Port is not used anywhere but must be exposed due to this issue
    # https://github.com/hashicorp/terraform-provider-azurerm/issues/1697#issuecomment-609028721
    ports {
      port     = 443
      protocol = "TCP"
    }
    environment_variables = {
      EventHubConnectionString = "${azurerm_eventhub_namespace.evhns.default_primary_connection_string};EntityPath=${azurerm_eventhub.evh.name}"
      DeviceCount              = azurerm_eventhub.evh.partition_count
      MessageCount             = 0
      Template                 = <<-EOT
        { 
            "deviceId": "$.DeviceId", 
            "time": "$.Time", 
            "doubleValue": $.DoubleValue 
        }
      EOT
      Variables                = <<-EOT
        [{
            "name": "DoubleValue", 
            "randomDouble": true, 
            "min":0.22, 
            "max":1.25
        }]
      EOT
    }
  }
}
