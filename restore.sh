#!/bin/bash

CONFIG_FILE="$HOME/.backup_config"

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "Loaded existing configuration:"
    source "$CONFIG_FILE"
    echo "Database Name: $DB_NAME"
    echo "User: $DB_USER"
    echo "Host: $DB_HOST"
    echo "Port: $DB_PORT"
    echo "Exclude File: $EXCLUDE_FILE"
    read -p "Do you want to continue with this configuration? (y/n): " answer
    if [[ "$answer" != "y" ]]; then
      update_config
    fi
  else
    update_config
  fi
}

update_config() {
  read -p "Enter database name: " DB_NAME
  read -p "Enter PostgreSQL user: " DB_USER
  read -p "Enter host (default: localhost): " DB_HOST
  DB_HOST=${DB_HOST:-localhost}
  read -p "Enter port (default: 5432): " DB_PORT
  DB_PORT=${DB_PORT:-5432}
  read -p "Enter the path to the exclude file: " EXCLUDE_FILE

  echo "DB_NAME=$DB_NAME" > "$CONFIG_FILE"
  echo "DB_USER=$DB_USER" >> "$CONFIG_FILE"
  echo "DB_HOST=$DB_HOST" >> "$CONFIG_FILE"
  echo "DB_PORT=$DB_PORT" >> "$CONFIG_FILE"
  echo "EXCLUDE_FILE=$EXCLUDE_FILE" >> "$CONFIG_FILE"
}

load_config

read -s -p "Enter password: " DB_PASS
echo

read -p "Enter number of parallel jobs (max: 4): " PARALLEL_JOBS
PARALLEL_JOBS=${PARALLEL_JOBS:-2}
echo "$(date +%H:%M:%S) Using $PARALLEL_JOBS parallel jobs."

read -p "Enter the output directory: " OUTPUT_DIR

echo "$(date +%H:%M:%S) Testing database connection..."
PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" -c '\q'
if [[ $? -ne 0 ]]; then
  echo "ERROR: Could not connect to the database."
  exit 1
fi

echo "Select restore type:"
echo "1. Only Schema"
echo "2. Schema with Data"
read -p "Enter choice (1/2): " CHOICE

if [[ "$CHOICE" == "1" ]]; then
  echo "$(date +%H:%M:%S) Schema-only restore selected."
  pg_restore -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" \
    -s -j "$PARALLEL_JOBS" --verbose "$OUTPUT_DIR"/backups/*/schema_with_data_backup > restore.log 2>&1

  if [[ $? -ne 0 ]]; then
    echo "$(date +%H:%M:%S) ERROR: Schema-only restore failed."
    exit 1
  fi

  echo "$(date +%H:%M:%S) Schema-only restore completed successfully."

elif [[ "$CHOICE" == "2" ]]; then
  echo "$(date +%H:%M:%S) Schema-with-data restore selected."
  echo "$(date +%H:%M:%S) Reading excluded tables from: $EXCLUDE_FILE"

  excluded_tables=$(grep -v '^\s*$' "$EXCLUDE_FILE" | paste -sd, -)
  echo "$(date +%H:%M:%S) Excluded tables: $excluded_tables"

  echo "$(date +%H:%M:%S) Starting schema-with-data restore..."
  pg_restore -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" \
    -j "$PARALLEL_JOBS" --verbose "$OUTPUT_DIR"/backups/*/schema_with_data_backup > restore.log 2>&1

  if [[ $? -ne 0 ]]; then
    echo "$(date +%H:%M:%S) ERROR: Schema-with-data restore failed."
    exit 1
  fi

  # Truncate excluded tables after restore
  if [[ -n "$excluded_tables" ]]; then
    echo "$(date +%H:%M:%S) Truncating excluded tables after restore..."
    PGPASSWORD="$DB_PASS" psql -U "$DB_USER" -h "$DB_HOST" -p "$DB_PORT" -d "$DB_NAME" \
      -c "TRUNCATE $excluded_tables;"
  fi

  echo "$(date +%H:%M:%S) Schema-with-data restore completed successfully."

else
  echo "Invalid choice. Exiting."
  exit 1
fi
