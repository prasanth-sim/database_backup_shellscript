#!/bin/bash

# Source the configuration script
source ./config.sh

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message" | tee -a "$LOG_FILE"
}

# Function to test database connection
test_connection() {
    log_message "Testing database connection..."
    if ! psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -c "\q" &>/dev/null; then
        log_message "ERROR: Failed to authenticate with the database. Please check your credentials."
        exit 1
    fi
}

# Function to read excluded tables (optional for full DB backup)
read_excluded_tables() {
    log_message "Reading excluded tables from: $EXCLUDE_FILE"
    if [ -f "$EXCLUDE_FILE" ]; then
        EXCLUDE_CMD=$(awk '{print "--exclude-table-data=" $1}' "$EXCLUDE_FILE" | tr '\n' ' ')
        log_message "Excluded tables: $(awk '{print $1}' "$EXCLUDE_FILE" | paste -sd', ' -)"
    else
        log_message "Exclude file not found, taking full backup (no exclusions)."
        EXCLUDE_CMD=""
    fi
}

# Prompt for password
read -s -p "Enter password: " DBPASS
echo
export PGPASSWORD="$DBPASS"

# Create backup directory and log file
read -p "Enter the output directory: " OUTPUT_DIR
mkdir -p "$OUTPUT_DIR/logs"
SCRIPT_NAME=$(basename "$0" | sed 's/\.sh//')
LOG_FILE="$OUTPUT_DIR/logs/$(date +'%Y_%m_%d_%H_%M')_${SCRIPT_NAME}.log"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
BACKUP_DIR="$OUTPUT_DIR/backups/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

# Test DB connection
test_connection

# Prompt for parallel jobs
CPU_CORES=$(nproc)
read -p "Enter number of parallel jobs (max: $CPU_CORES): " JOBS
if (( JOBS > CPU_CORES )); then
    log_message "Specified jobs exceed available CPU cores. Setting jobs to $CPU_CORES."
    JOBS=$CPU_CORES
elif (( JOBS < 1 )); then
    log_message "Invalid input for jobs. Setting jobs to 1."
    JOBS=1
fi
log_message "Using $JOBS parallel jobs."

# Backup type menu
echo "Select backup type:"
echo "1. Only Schema (entire DB)"
echo "2. Schema with Data (entire DB)"
echo "3. Single Table (schema + data)"
read -p "Enter choice (1/2/3): " BACKUP_TYPE

case "$BACKUP_TYPE" in
    1)
        log_message "Schema-only backup selected."
        log_message "Starting schema-only backup..."
        pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" --schema-only -Fd -j "$JOBS" -f "$BACKUP_DIR/schema_only_backup"
        if [ $? -eq 0 ]; then
            log_message "Schema-only backup completed successfully."
        else
            log_message "ERROR: Schema-only backup failed."
            exit 1
        fi
        ;;
    2)
        log_message "Schema-with-data backup selected."
        read_excluded_tables
        log_message "Starting schema-with-data backup..."
        pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" $EXCLUDE_CMD -Fd -j "$JOBS" -f "$BACKUP_DIR/schema_with_data_backup"
        if [ $? -eq 0 ]; then
            log_message "Schema-with-data backup completed successfully."
        else
            log_message "ERROR: Schema-with-data backup failed."
            exit 1
        fi
        ;;
    3)
        read -p "Enter the table name to back up: " TABLE_NAME
        log_message "Single-table backup selected for table: $TABLE_NAME"
        pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -t "$TABLE_NAME" -Fd -j "$JOBS" -f "$BACKUP_DIR/table_${TABLE_NAME}_backup"
        if [ $? -eq 0 ]; then
            log_message "Table backup completed successfully."
        else
            log_message "ERROR: Table backup failed."
            exit 1
        fi
        ;;
    *)
        log_message "ERROR: Invalid choice. Please select 1, 2, or 3."
        exit 1
        ;;
esac

# Final message
log_message "Backup process completed!"
log_message "Backups are stored in: $BACKUP_DIR"
log_message "Logs are stored in: $OUTPUT_DIR/logs"

