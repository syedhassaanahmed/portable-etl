from pyspark.sql import SparkSession
from pyspark.sql.types import StringType
import pytest
from common_lib.src.data_processor import DataProcessor


@pytest.fixture
def spark():
    return SparkSession.builder.appName("MyPySparkTests").getOrCreate()


def test_data_processor(spark):
    metadata = spark.read.csv("rooms.csv", header=True, inferSchema=True)

    test_data = spark.createDataFrame(
        data=['{"deviceId": "sim000001","deviceTimestamp":"2023-01-01T10:10:11.5091350Z", "doubleValue": 0.2}',  # noqa: E501
              '{"deviceId": "sim000002", "deviceTimestamp":"2023-01-01T10:10:11.6091350Z", "doubleValue": 0.24}',  # noqa: E501
              '{"deviceId": "sim000003", "deviceTimestamp":"2023-01-01T10:10:11.6091350Z", "doubleValue": 0.25}'],  # noqa: E501
        schema=StringType()
    )

    data_processor = DataProcessor()
    results = data_processor.process(df_metadata=metadata,
                                     df_raw_data=test_data)

    expected = ["room1", "room1", "room2"]
    assert [row.roomId for row in results.collect()] == expected
