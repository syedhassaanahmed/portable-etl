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

resource "databricks_library" "kafka" {
  cluster_id = databricks_cluster.this.id
  maven {
    coordinates = "org.apache.spark:spark-sql-kafka-0-10_2.12:3.1.3"
  }
}

resource "databricks_library" "sql" {
  cluster_id = databricks_cluster.this.id
  maven {
    coordinates = "com.microsoft.azure:spark-mssql-connector_2.12:1.2.0"
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

resource "databricks_library" "wheel" {
  cluster_id = databricks_cluster.this.id
  whl        = databricks_dbfs_file.wheel.dbfs_path
}

resource "databricks_notebook" "main" {
  path           = "${local.notebooks_path}/main_databricks"
  language       = "PYTHON"
  content_base64 = filebase64("${path.module}/notebooks/main_databricks.py")
  depends_on     = [databricks_library.wheel]
}

resource "databricks_notebook" "secrets" {
  path     = "${local.notebooks_path}/load_secrets"
  language = "PYTHON"
  content_base64 = base64encode(<<-EOT
    scope_name = "${databricks_secret_scope.this.name}"
    eh_name = dbutils.secrets.get(scope_name, "${databricks_secret.ehname.key}")
    eh_namespace = dbutils.secrets.get(scope_name, "${databricks_secret.ehnamespace.key}")
    eh_connection_string = dbutils.secrets.get(scope_name, "${databricks_secret.ehconnection.key}")
    db_server = dbutils.secrets.get(scope_name, "${databricks_secret.dbserver.key}")
    db_name = dbutils.secrets.get(scope_name, "${databricks_secret.dbname.key}")
    db_user = dbutils.secrets.get(scope_name, "${databricks_secret.dbuser.key}")
    db_password = dbutils.secrets.get(scope_name, "${databricks_secret.dbpassword.key}")
    EOT
  )
}

resource "databricks_dbfs_file" "metadata" {
  source = "${path.module}/metadata/rooms.csv"
  path   = "/metadata/rooms.csv"
}

resource "databricks_job" "this" {
  name                = "pyspark_streaming_job"
  existing_cluster_id = databricks_cluster.this.id
  always_running      = true
  notebook_task {
    notebook_path = databricks_notebook.main.path
  }
}