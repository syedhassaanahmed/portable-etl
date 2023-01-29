# Databricks notebook source
from pyspark.sql import DataFrame

# COMMAND ----------

dbutils.widgets.text("secretsScopeName", "")
dbutils.widgets.text("dltPipelineStorage", "")

# COMMAND ----------

dlt_pipeline_storage = dbutils.widgets.get("dltPipelineStorage")
df_stream_processed = spark.readStream.format("delta").load(f"dbfs:{dlt_pipeline_storage}/tables/stream_processed")

display(df_stream_processed)

# COMMAND ----------

scope_name = dbutils.widgets.get("secretsScopeName")
db_server = dbutils.secrets.get(scope_name, "DB_SERVER")
db_name = dbutils.secrets.get(scope_name, "DB_NAME")
db_user = dbutils.secrets.get(scope_name, "DB_USER")
db_password = dbutils.secrets.get(scope_name, "DB_PASSWORD")

# The "driver" option is buried deep into this issue
# https://github.com/microsoft/sql-spark-connector/issues/177
sql_server_options = {
    "driver": "com.microsoft.sqlserver.jdbc.SQLServerDriver",
    "url": f"jdbc:sqlserver://{db_server};databaseName={db_name};",
    "dbtable": "dbo.telemetry",
    "user": db_user,
    "password": db_password
}

# COMMAND ----------

def write_to_sql_server(df: DataFrame, epoch_id: int) -> None:
    (df.write
     .format("com.microsoft.sqlserver.jdbc.spark")
     .mode("append")
     .options(**sql_server_options)
     .save())

# COMMAND ----------

(df_stream_processed.writeStream
                    .outputMode("append")
                    .foreachBatch(write_to_sql_server)
                    .start()
                    .awaitTermination())
