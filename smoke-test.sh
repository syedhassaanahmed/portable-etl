#!/usr/bin/env bash
set -euo pipefail

echo "Stopping all containers if exist..."
docker compose down

echo "Starting all containers..."
docker compose up -d

RETRIES=60
MIN_ROW_COUNT=5

source .env

for i in $(seq 1 1 $RETRIES)
do
    # "-h -1" SQLCMD flag is used to remove column headers from the output
    # "SET NOCOUNT ON;" before the intended SQL query is used to remove output such as "n row(s) affected"
    # xargs removes the leading and trailing spaces from the output
    SQL_CMD="/opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P \"$MSSQL_SA_PASSWORD\" -d \"master\" -h -1 -Q \
        \"SET NOCOUNT ON; SELECT COUNT(1) FROM dbo.Telemetry\" | xargs"

    ROW_COUNT=$(docker compose exec sql-server bash -c "$SQL_CMD" || true)
    echo "Table row count is $ROW_COUNT"

    if [[ $ROW_COUNT =~ ^[0-9]+$ && $ROW_COUNT -ge $MIN_ROW_COUNT ]];
    then
        echo "PySpark App is running and processing the IoT stream successfully."
        break
    else
        echo "Waiting for the PySpark App.. Attempt [${i}/${RETRIES}]"
        if [ $i = $RETRIES ];
        then
            echo "Found less than ${MIN_ROW_COUNT} rows in the table."
            docker logs spark
            exit 1
        else
            sleep 1
        fi
    fi
done

echo "Stopping all containers"
docker compose down
