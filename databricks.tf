resource "azurerm_databricks_workspace" "dbw" {
  name                        = "dbw-${random_string.unique.result}"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  sku                         = "premium"
  managed_resource_group_name = "dbw-rg-${random_string.unique.result}"
}

provider "databricks" {
  host                        = azurerm_databricks_workspace.dbw.workspace_url
  azure_workspace_resource_id = azurerm_databricks_workspace.dbw.id
}

# Until this issue is resolved, we're stuck at Spark 3.1
# https://github.com/microsoft/sql-spark-connector/issues/191
data "databricks_spark_version" "spark31" {
  spark_version = "3.1"
  depends_on    = [azurerm_databricks_workspace.dbw]
}

data "databricks_node_type" "smallest" {
  local_disk = true
  depends_on = [azurerm_databricks_workspace.dbw]
}

resource "databricks_secret_scope" "this" {
  name = "MyPySparkStreamingAppSecrets"
}

resource "databricks_secret" "ehname" {
  string_value = azurerm_eventhub.evh.name
  scope        = databricks_secret_scope.this.name
  key          = "EH_NAME"
}

resource "databricks_secret" "ehnamespace" {
  string_value = azurerm_eventhub_namespace.evhns.name
  scope        = databricks_secret_scope.this.name
  key          = "EH_NAMESPACE"
}

resource "databricks_secret" "ehconnection" {
  string_value = azurerm_eventhub_namespace.evhns.default_primary_connection_string
  scope        = databricks_secret_scope.this.name
  key          = "EH_CONNECTION_STRING"
}

resource "databricks_secret" "dbserver" {
  string_value = azurerm_mssql_server.sql.fully_qualified_domain_name
  scope        = databricks_secret_scope.this.name
  key          = "DB_SERVER"
}

resource "databricks_secret" "dbname" {
  string_value = azurerm_mssql_database.sqldb.name
  scope        = databricks_secret_scope.this.name
  key          = "DB_NAME"
}

resource "databricks_secret" "dbuser" {
  string_value = azurerm_mssql_server.sql.administrator_login
  scope        = databricks_secret_scope.this.name
  key          = "DB_USER"
}

resource "databricks_secret" "dbpassword" {
  string_value = azurerm_mssql_server.sql.administrator_login_password
  scope        = databricks_secret_scope.this.name
  key          = "DB_PASSWORD"
}

resource "databricks_cluster" "this" {
  cluster_name            = "Exploration Cluster"
  spark_version           = data.databricks_spark_version.spark31.id
  node_type_id            = data.databricks_node_type.smallest.id
  autotermination_minutes = 20
  autoscale {
    min_workers = 1
    max_workers = azurerm_eventhub.evh.partition_count
  }
}

locals {
  notebooks_path = "/Shared/pyspark_app"
  wheel_name     = "common_lib-0.0.1-py3-none-any.whl"
}

# The wheel should be built outside of Terraform by "sudo python3 -m build ./common_lib"
resource "databricks_dbfs_file" "wheel" {
  source = "${path.module}/common_lib/dist/${local.wheel_name}"
  path   = "/FileStore/${local.wheel_name}"
}

resource "databricks_dbfs_file" "metadata" {
  source = "${path.module}/metadata/rooms.csv"
  path   = "/metadata/rooms.csv"
}

resource "databricks_notebook" "main" {
  path           = "${local.notebooks_path}/main_dlt"
  language       = "PYTHON"
  content_base64 = filebase64("${path.module}/notebooks/main_dlt.py")
}

resource "databricks_pipeline" "dlt" {
  name    = "My DLT Pipeline"
  storage = "/my-dlt-pipeline"
  configuration = {
    secretsScopeName = databricks_secret_scope.this.name
    metadataPath     = databricks_dbfs_file.metadata.path
  }

  cluster {
    label = "default"
    autoscale {
      min_workers = 1
      max_workers = azurerm_eventhub.evh.partition_count
    }
  }

  library {
    notebook {
      path = databricks_notebook.main.path
    }
  }

  continuous = true

  depends_on = [
    databricks_dbfs_file.wheel
  ]
}

resource "databricks_library" "sql" {
  cluster_id = databricks_cluster.this.id
  maven {
    coordinates = "com.microsoft.azure:spark-mssql-connector_2.12:1.2.0"
  }
}

resource "databricks_notebook" "sql" {
  path           = "${local.notebooks_path}/output_to_sql_db"
  language       = "PYTHON"
  content_base64 = filebase64("${path.module}/notebooks/output_to_sql_db.py")
}

resource "databricks_job" "sql" {
  name                = "output_to_sql_db"
  existing_cluster_id = databricks_cluster.this.id
  always_running      = true
  notebook_task {
    notebook_path = databricks_notebook.sql.path

    base_parameters = {
      secretsScopeName   = databricks_secret_scope.this.name
      dltPipelineStorage = databricks_pipeline.dlt.storage
    }
  }
  depends_on = [
    databricks_library.sql,
    databricks_secret.dbserver
  ]
}