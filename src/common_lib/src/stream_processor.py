from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    DoubleType
)


class StreamProcessor:
    def __init__(self) -> None:
        self.stream_schema = StructType([
            StructField("deviceId", StringType()),
            StructField("deviceTimestamp", TimestampType()),
            StructField("doubleValue", DoubleType())
        ])

    def process_stream(self, df_metadata: DataFrame,
                       df_raw_stream: DataFrame) -> DataFrame:
        # The output schema should match the
        # Table definition in create_table.sql
        return (df_raw_stream
                .withColumn("data", F.from_json(F.col("value").cast("STRING"),
                            self.stream_schema))
                .selectExpr("data.*")
                .join(df_metadata, on="deviceId")
                .withColumn("ingestionTimestamp", F.current_timestamp()))
