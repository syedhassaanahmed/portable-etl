terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.48.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "=1.13.0"
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

locals {
  unique_id = "portable-etl-${random_string.unique.result}"
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.unique_id}"
  location = "West Europe"
}

resource "azurerm_eventhub_namespace" "evhns" {
  name                = "evhns-${local.unique_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Standard"
  capacity            = 1
}

resource "azurerm_eventhub" "evh" {
  name                = "evh-${local.unique_id}"
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
  name                         = "sql-${local.unique_id}"
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
  name      = "sqldb-${local.unique_id}"
  server_id = azurerm_mssql_server.sql.id
  sku_name  = "S0"
}

resource "azurerm_container_group" "sql" {
  name                = "ci-sql-${local.unique_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  restart_policy      = "OnFailure"

  container {
    name   = "sql-setup"
    image  = "mcr.microsoft.com/mssql-tools"
    cpu    = "1.0"
    memory = "1.5"

    # Port is not used anywhere but must be exposed due to this issue
    # https://github.com/hashicorp/terraform-provider-azurerm/issues/1697#issuecomment-609028721
    ports {
      port     = 443
      protocol = "TCP"
    }

    environment_variables = {
      MSSQL_HOST        = azurerm_mssql_server.sql.fully_qualified_domain_name
      MSSQL_SA_USER     = azurerm_mssql_server.sql.administrator_login
      MSSQL_SA_PASSWORD = azurerm_mssql_server.sql.administrator_login_password
      DB_NAME           = azurerm_mssql_database.sqldb.name
    }

    volume {
      name       = "config"
      mount_path = "/db"

      secret = {
        create_table = filebase64("${path.module}/db/create_table.sql")
      }
    }

    commands = [
      "/bin/bash", "-c", <<-EOT
        /opt/mssql-tools/bin/sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -d "$DB_NAME" -i /db/create_table
      EOT
    ]
  }
}

resource "azurerm_container_group" "simulator" {
  name                = "ci-simulator-${local.unique_id}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  os_type             = "Linux"
  depends_on          = [databricks_job.main]

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
            "deviceTimestamp": "$.Time", 
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
