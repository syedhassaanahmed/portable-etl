# portable-etl
![CI](https://github.com/syedhassaanahmed/portable-etl/actions/workflows/ci.yml/badge.svg)

## Why?
Workload portability is important to manufacturing customers, as it allows them to operate solutions across different environments without the need to re-architect or re-write large sections of code. They can easily move from the Edge to the cloud, depending on their specific requirements. It also enables them to analyze and make real-time decisions at the source of the data and reduces their dependency on a central location for data processing. [Apache Spark](https://spark.apache.org/docs/latest/)'s rich ecosystem of data connectors, availability in [the cloud](https://azure.microsoft.com/en-us/products/databricks) and the Edge ([Docker](https://hub.docker.com/r/apache/spark-py) & [Kubernetes](https://spark.apache.org/docs/latest/running-on-kubernetes.html)), and a [thriving open source community](https://github.com/apache/spark) makes it an ideal candidate for portable ETL workloads. In this sample we'll showcase an E2E data pipeline leveraging [Spark's Structured Streaming](https://spark.apache.org/docs/latest/structured-streaming-programming-guide.html#overview) capabilities.

## Edge
In the Edge version, we orchestrate everything with `Docker Compose`. The pipeline begins with [Azure IoT Device Telemetry Simulator](https://github.com/Azure-Samples/Iot-Telemetry-Simulator) sending synthetic Time Series data to a [Confluent Community Kafka Server](https://docs.confluent.io/platform/current/platform-quickstart.html#ce-docker-quickstart). A PySpark app then processes the Time Series, applies some metadata and writes the aggregated results to a SQL DB hosted in [SQL Server 2022 Linux container](https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-docker?view=sql-server-ver16&pivots=cs1-bash). To validate that the E2E Edge pipeline is working correctly, we can execute the script `smoke-test.sh`.

<div align="center">
    <img src="./docs/edge-architecture.png">
</div>

## Cloud
In the Cloud version, we orchestrate everything with Terraform. The IoT Telemetry Simulator runs in [Azure Container Instances](https://azure.microsoft.com/en-us/products/container-instances). It sends generated data to a Kafka head, [exposed through Azure Event Hubs](https://learn.microsoft.com/en-us/azure/event-hubs/azure-event-hubs-kafka-overview). Spark job is hosted in Azure Databricks and the aggregated output is streamed to an [Azure SQL DB](https://azure.microsoft.com/en-us/products/azure-sql/database/). The key point to note here is that the stream processing logic is encapsulated in `steam_processor.py` and is reused between the Edge and the Cloud.

<div align="center">
    <img src="./docs/cloud-architecture.png">
</div>

## Codespaces
This solution supports GitHub Codespaces through the VS Code Dev Containers. The minimum required machine type configuration is `4-core`.