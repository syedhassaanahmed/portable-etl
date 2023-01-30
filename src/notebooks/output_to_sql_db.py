# Databricks notebook source
import time
from pyspark.sql import DataFrame


# COMMAND ----------

dbutils.widgets.text("secretsScopeName", "")
dbutils.widgets.text("dltDatabaseName", "")

# COMMAND ----------

# Wait for DLT to create the database
dlt_database_name = dbutils.widgets.get("dltDatabaseName")

d_counter = 0
while True:
    databases = spark.catalog.listDatabases()

    if any(d.name == dlt_database_name for d in databases):
        print(f"Database {dlt_database_name} found.")
        break
    elif d_counter > 30:
        print(f"Timeout expired, Database {dlt_database_name} not found.")
        break
        
    print(f"Database {dlt_database_name} not yet found...")
    d_counter += 1
    time.sleep(10)

# COMMAND ----------

# Wait for DLT to create the table
dlt_table_name = "stream_processed"
full_dlt_table_name = f"{dlt_database_name}.{dlt_table_name}"

t_counter = 0
while True:
    tables = spark.catalog.listTables(dlt_database_name)

    if any(t.name == dlt_table_name for t in tables):
        print(f"Table {full_dlt_table_name} found.")
        break
    elif t_counter > 30:
        print(f"Timeout expired, Table {full_dlt_table_name} not found.")
        break
        
    print(f"Table {full_dlt_table_name} not yet found...")
    t_counter += 1
    time.sleep(10)

# COMMAND ----------

df_stream_processed = spark.readStream.format("delta").table(f"{full_dlt_table_name}")
display(df_stream_processed)

# COMMAND ----------

scope_name = dbutils.widgets.get("secretsScopeName")
db_server = dbutils.secrets.get(scope_name, "DB_SERVER")
db_name = dbutils.secrets.get(scope_name, "DB_NAME")
db_user = dbutils.secrets.get(scope_name, "DB_USER")
db_password = dbutils.secrets.get(scope_name, "DB_PASSWORD")

# The "driver" option is buried deep into this issue
# https://github.com/microsoft/sql-spark-connector/issues/177
# "schemaCheckEnabled": False because https://github.com/microsoft/sql-spark-connector/issues/5
sql_server_options = {
    "driver": "com.microsoft.sqlserver.jdbc.SQLServerDriver",
    "url": f"jdbc:sqlserver://{db_server};databaseName={db_name};",
    "dbtable": "dbo.ProcessedStream",
    "user": db_user,
    "password": db_password,
    "schemaCheckEnabled": False
}

# COMMAND ----------

def write_to_sql_server(df: DataFrame, epoch_id: int) -> None:
    (df.write
     .format("com.microsoft.sqlserver.jdbc.spark")
     .mode("append")
     .options(**sql_server_options)
     .save())

# COMMAND ----------

(df_stream_processed
 .writeStream
 .outputMode("append")
 .foreachBatch(write_to_sql_server)
 .start()
 .awaitTermination())
