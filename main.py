import os
from pyspark.sql import SparkSession, functions as F
from pyspark.sql.types import *

if __name__ == "__main__":

    spark = SparkSession.builder.appName("MyPySparkStreamingApp").getOrCreate()
    spark.sparkContext.setLogLevel("ERROR")

    df_rooms = spark.read.csv("/metadata/rooms.csv", header=True, inferSchema=True)

    kafka_broker = os.environ["KAFKA_BROKER"]
    kafka_topic = os.environ["KAFKA_TOPIC"]

    df_stream = spark \
        .readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", kafka_broker) \
        .option("subscribe", kafka_topic) \
        .load()

    schema = StructType([
        StructField("deviceId", StringType()),
        StructField("time", TimestampType()),
        StructField("doubleValue", DoubleType())
    ])

    df_stream = df_stream.selectExpr("CAST(value AS STRING)") \
        .select(F.from_json(F.col("value"), schema).alias("data")) \
        .select("data.*")

    windowSpec = F.window("time", "5 seconds")

    # Watermarking handles late arrivals
    # https://spark.apache.org/docs/latest/structured-streaming-programming-guide.html#handling-late-data-and-watermarking
    df_stream_agg = df_stream \
        .withWatermark("time", "5 seconds") \
        .groupBy(windowSpec, "deviceId") \
        .agg(F.avg("doubleValue").alias("avgValue")) \
        .join(df_rooms, on="deviceId") \
        .selectExpr("deviceId", "roomId", "avgValue", "window.start as start", "window.end as end")

    # Uncomment for stdout debugging
    # query = df_stream_agg \
    #     .writeStream \
    #     .outputMode("append") \
    #     .format("console") \
    #     .start()

    mssql_host = os.environ["MSSQL_HOST"]
    mssql_sa_password = os.environ["MSSQL_SA_PASSWORD"]

    # Using foreachBatch because the sql-spark-connector doesn't directly support writing streams
    query = df_stream_agg.writeStream \
        .outputMode("append") \
        .foreachBatch(lambda df, epoch_id: 
            df.write \
                .format("com.microsoft.sqlserver.jdbc.spark") \
                .mode("append") \
                # The driver option is buried deep into this issue https://github.com/microsoft/sql-spark-connector/issues/177
                .option("driver", "com.microsoft.sqlserver.jdbc.SQLServerDriver") \
                .option("url", f"jdbc:sqlserver://{mssql_host};databaseName=master;") \
                .option("dbtable", "dbo.telemetry") \
                .option("user", "sa") \
                .option("password", mssql_sa_password) \
                .save()
        ).start()

    query.awaitTermination()
