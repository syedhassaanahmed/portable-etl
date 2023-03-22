import os
from pyspark.sql import SparkSession, DataFrame
from data_processor import DataProcessor

if __name__ == "__main__":

    spark = SparkSession.builder.appName("MyPySparkApp").getOrCreate()
    spark.sparkContext.setLogLevel("ERROR")

    df_metadata = spark.read.csv("/metadata/rooms.csv",
                                 header=True,
                                 inferSchema=True)

    kafka_options = {
        "kafka.bootstrap.servers": os.environ["KAFKA_BROKER"],
        "subscribe": os.environ["KAFKA_TOPIC"]
    }

    df_raw_data = (spark.readStream
                   .format("kafka")
                   .options(**kafka_options)
                   .load())

    processor = DataProcessor()
    df_output = processor.process(df_metadata, df_raw_data)

    mssql_host = os.environ["MSSQL_HOST"]
    db_name = os.environ["DB_NAME"]
    mssql_url = f"jdbc:sqlserver://{mssql_host};databaseName={db_name};"

    # The "driver" option is buried deep into this issue
    # https://github.com/microsoft/sql-spark-connector/issues/177
    # "schemaCheckEnabled": False
    # because https://github.com/microsoft/sql-spark-connector/issues/5
    sql_server_options = {
        "driver": "com.microsoft.sqlserver.jdbc.SQLServerDriver",
        "url": mssql_url,
        "dbtable": "dbo.ProcessedData",
        "user": "sa",
        "password": os.environ["MSSQL_SA_PASSWORD"],
        "trustServerCertificate": True,
        "schemaCheckEnabled": False
    }

    def write_to_sql_server(df: DataFrame, epoch_id: int) -> None:
        (df.write
           .format("com.microsoft.sqlserver.jdbc.spark")
           .mode("append")
           .options(**sql_server_options)
           .save())

        df.show()

    # Using foreachBatch because the sql-spark-connector
    # doesn't directly support writing streams
    query = (df_output
             .writeStream
             .outputMode("append")
             .foreachBatch(write_to_sql_server)
             .start()
             .awaitTermination())
