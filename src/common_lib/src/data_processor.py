from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    TimestampType,
    DoubleType
)


class DataProcessor:
    def __init__(self) -> None:
        self.schema = StructType([
            StructField("deviceId", StringType()),
            StructField("deviceTimestamp", TimestampType()),
            StructField("doubleValue", DoubleType())
        ])

    def process(self, df_metadata: DataFrame,
                df_raw_data: DataFrame) -> DataFrame:
        # The output schema should match the
        # Table definition in ../../db/create_table.sql
        return (df_raw_data
                .withColumn("data", F.from_json(F.col("value").cast("STRING"),
                            self.schema))
                .selectExpr("data.*")
                .join(df_metadata, on="deviceId")
                .withColumn("ingestionTimestamp", F.current_timestamp()))
