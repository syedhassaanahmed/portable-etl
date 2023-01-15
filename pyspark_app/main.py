import os
from pyspark.sql import SparkSession
from stream_processor import StreamProcessor

if __name__ == "__main__":

    spark = SparkSession.builder.appName("MyPySparkStreamingApp").getOrCreate()
    spark.sparkContext.setLogLevel("ERROR")

    df_metadata = spark.read.csv("/metadata/rooms.csv",
                                 header=True,
                                 inferSchema=True)

    kafka_broker = os.environ["KAFKA_BROKER"]
    kafka_topic = os.environ["KAFKA_TOPIC"]

    df_raw_stream = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", kafka_broker) \
        .option("subscribe", kafka_topic) \
        .load()

    processor = StreamProcessor(df_metadata, df_raw_stream)
    df_output_stream = processor.process_stream()

    # Uncomment for stdout debugging
    # query = df_output_stream \
    #     .writeStream \
    #     .outputMode("append") \
    #     .format("console") \
    #     .start()

    mssql_host = os.environ["MSSQL_HOST"]
    mssql_sa_password = os.environ["MSSQL_SA_PASSWORD"]
    mssql_url = f"jdbc:sqlserver://{mssql_host};databaseName=master;"

    # Using foreachBatch because the sql-spark-connector
    # doesn't directly support writing streams
    # The "driver" option is buried deep into this issue
    # https://github.com/microsoft/sql-spark-connector/issues/177
    query = df_output_stream.writeStream \
        .outputMode("append") \
        .foreachBatch(lambda df, epoch_id:
                      df.write
                        .format("com.microsoft.sqlserver.jdbc.spark")
                        .mode("append")
                        .option("driver",
                                "com.microsoft.sqlserver.jdbc.SQLServerDriver")
                        .option("url", mssql_url)
                        .option("dbtable", "dbo.telemetry")
                        .option("user", "sa")
                        .option("password", mssql_sa_password)
                        .save()
                      ).start()

    query.awaitTermination()
