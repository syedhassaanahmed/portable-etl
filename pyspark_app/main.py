import os
from pyspark.sql import SparkSession, DataFrame
from stream_processor import StreamProcessor

if __name__ == "__main__":

    spark = SparkSession.builder.appName("MyPySparkStreamingApp").getOrCreate()
    spark.sparkContext.setLogLevel("ERROR")

    kafka_options = {
        "kafka.bootstrap.servers": os.environ["KAFKA_BROKER"],
        "subscribe": os.environ["KAFKA_TOPIC"]
    }

    processor = StreamProcessor(spark, "/metadata/rooms.csv", kafka_options)
    df_output_stream = processor.process_stream()

    mssql_host = os.environ["MSSQL_HOST"]
    db_name = os.environ["DB_NAME"]

    # The "driver" option is buried deep into this issue
    # https://github.com/microsoft/sql-spark-connector/issues/177
    sql_server_options = {
        "driver": "com.microsoft.sqlserver.jdbc.SQLServerDriver",
        "url": f"jdbc:sqlserver://{mssql_host};databaseName={db_name};",
        "dbtable": os.environ["TABLE_NAME"],
        "user": "sa",
        "password": os.environ["MSSQL_SA_PASSWORD"]
    }

    def write_to_sql_server(df: DataFrame, epoch_id: int) -> None:
        df.write \
          .format("com.microsoft.sqlserver.jdbc.spark") \
          .mode("append") \
          .options(**sql_server_options) \
          .save()

        df.show()

    # Using foreachBatch because the sql-spark-connector
    # doesn't directly support writing streams
    query = df_output_stream.writeStream \
        .outputMode("append") \
        .foreachBatch(write_to_sql_server) \
        .start() \
        .awaitTermination()
