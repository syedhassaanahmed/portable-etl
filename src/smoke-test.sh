#!/usr/bin/env bash
set -euo pipefail

docker compose down
docker compose up -d

RETRIES=60
MIN_ROW_COUNT=5
TABLE_NAME="dbo.ProcessedData"

# shellcheck source=/dev/null
source .env

for i in $(seq 1 1 $RETRIES)
do
    # "-h -1" SQLCMD flag is used to remove column headers from the output
    # "SET NOCOUNT ON;" before the intended SQL query is used to remove output such as "n row(s) affected"
    # xargs removes the leading and trailing spaces from the output
    SQL_CMD="/opt/mssql-tools/bin/sqlcmd -S localhost -U SA -P \"$MSSQL_SA_PASSWORD\" -d \"$DB_NAME\" -h -1 -Q \
        \"SET NOCOUNT ON; SELECT COUNT(1) FROM $TABLE_NAME\" | xargs"

    ROW_COUNT=$(docker compose exec sql-server bash -c "$SQL_CMD" || true)
    echo "$TABLE_NAME row count is $ROW_COUNT"

    if [[ $ROW_COUNT =~ ^[0-9]+$ && $ROW_COUNT -ge $MIN_ROW_COUNT ]];
    then
        echo "PySpark App is running and processing the data successfully."
        break
    else
        echo "Waiting for the PySpark App.. Attempt [${i}/${RETRIES}]"
        if [ "$i" = $RETRIES ];
        then
            echo "Found less than ${MIN_ROW_COUNT} rows in $TABLE_NAME"
            docker compose logs spark
            docker compose down
            exit 1
        else
            sleep 1
        fi
    fi
done

docker compose down
