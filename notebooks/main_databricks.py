# Databricks notebook source
# MAGIC %run ./stream_processor.py

# COMMAND ----------

# MAGIC %run ./load_secrets.py

# COMMAND ----------

bootstrap_server = f"{eh_namespace}.servicebus.windows.net:9093"
eh_sasl = f'org.apache.kafka.common.security.plain.PlainLoginModule required username="$ConnectionString" password="{eh_connection_string}";'

kafka_options = {
    "kafka.bootstrap.servers": bootstrap_server,
    "subscribe": eh_name,
    "kafka.sasl.mechanism": "PLAIN",
    "kafka.security.protocol": "SASL_SSL",
    "kafka.sasl.jaas.config": eh_sasl
}

processor = StreamProcessor(spark, "dbfs:/metadata/rooms.csv", kafka_options)

# COMMAND ----------

df_output_stream = processor.process_stream()
display(df_output_stream)

# COMMAND ----------

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
    df.write \
      .format("com.microsoft.sqlserver.jdbc.spark") \
      .mode("append") \
      .options(**sql_server_options) \
      .save()

# COMMAND ----------

# Using foreachBatch because the sql-spark-connector doesn't directly support writing streams
query = df_output_stream.writeStream \
    .outputMode("append") \
    .option("checkpointLocation", "dbfs:/checkpointdir") \
    .foreachBatch(write_to_sql_server) \
    .start() \
    .awaitTermination()
