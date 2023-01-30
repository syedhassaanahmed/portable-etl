#!/usr/bin/env bash

#do this in a loop because the timing for when the SQL instance is ready is indeterminate
for i in {1..60};
do
    /opt/mssql-tools/bin/sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD"

    if [ $? -eq 0 ]
    then
        echo "SQL Server initialize completed."
        break
    else
        echo "SQL Server not ready yet, attempt #$i..."
        sleep 1
    fi
done

/opt/mssql-tools/bin/sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -i create_db.sql -v DBName="$DB_NAME"
/opt/mssql-tools/bin/sqlcmd -S "$MSSQL_HOST" -U "$MSSQL_SA_USER" -P "$MSSQL_SA_PASSWORD" -d "$DB_NAME" -i create_table.sql
