# Databricks notebook source
from pyspark.sql import DataFrame
from stream_processor import StreamProcessor

# COMMAND ----------

dbutils.widgets.text("secretsScopeName", "")

# COMMAND ----------

scope_name = dbutils.widgets.get("secretsScopeName")

eh_name = dbutils.secrets.get(scope_name, "EH_NAME")
eh_namespace = dbutils.secrets.get(scope_name, "EH_NAMESPACE")
eh_connection_string = dbutils.secrets.get(scope_name, "EH_CONNECTION_STRING")

bootstrap_server = f"{eh_namespace}.servicebus.windows.net:9093"
eh_sasl = f'org.apache.kafka.common.security.plain.PlainLoginModule required username="$ConnectionString" password="{eh_connection_string}";'

kafka_options = {
    "kafka.bootstrap.servers": bootstrap_server,
    "subscribe": eh_name,
    "kafka.sasl.mechanism": "PLAIN",
    "kafka.security.protocol": "SASL_SSL",
    "kafka.sasl.jaas.config": eh_sasl,
}

# COMMAND ----------

df_raw_stream = spark.readStream.format("kafka").options(**kafka_options).load()
display(df_raw_stream)

# COMMAND ----------

df_metadata = spark.read.csv("dbfs:/metadata/rooms.csv", header=True, inferSchema=True)
display(df_metadata)

# COMMAND ----------

processor = StreamProcessor()
df_output_stream = processor.process_stream(df_metadata, df_raw_stream)
display(df_output_stream)

# COMMAND ----------

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
    "schemaCheckEnabled": False,
}

# COMMAND ----------

def write_to_sql_server(df: DataFrame, epoch_id: int) -> None:
    df.write.format("com.microsoft.sqlserver.jdbc.spark").mode("append").options(
        **sql_server_options
    ).save()

# COMMAND ----------

# Using foreachBatch because the sql-spark-connector doesn't directly support writing streams
df_output_stream.writeStream.outputMode("append").option(
    "checkpointLocation", "dbfs:/checkpointdir"
).foreachBatch(write_to_sql_server).start().awaitTermination()
