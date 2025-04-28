#!/bin/bash

# Source the configuration script
source ./config_db.sh

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message"
}

# Function to test database connection
test_connection() {
    log_message "Testing database connection..."
    if ! psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -c "\q" &>/dev/null; then
        log_message "ERROR: Failed to authenticate with the database. Please check your credentials."
        exit 1
    fi
}

# Function to read excluded tables from the file
read_excluded_tables() {
    if [ ! -f "$EXCLUDE_FILE" ]; then
        log_message "ERROR: Exclude file '$EXCLUDE_FILE' does not exist."
        exit 1
    fi

    log_message "Reading excluded tables from: $EXCLUDE_FILE"
    EXCLUDE_CMD=$(awk '{print "--exclude-table-data=" $1}' "$EXCLUDE_FILE" | tr '\n' ' ')
    log_message "Excluded tables: $(awk '{print $1}' "$EXCLUDE_FILE" | tr '\n' ', ')"
}

# Prompt for password
read -s -p "Enter password: " DBPASS
echo

# Export password for PostgreSQL commands
export PGPASSWORD="$DBPASS"

# Prompt user for parallel jobs
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

# Create unique folder for this backup run
read -p "Enter the output directory: " OUTPUT_DIR
mkdir -p "$OUTPUT_DIR/logs"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')"
BACKUP_DIR="$OUTPUT_DIR/backups/$TIMESTAMP"
mkdir -p "$BACKUP_DIR"

# Test database connection
test_connection

# Ask the user for backup type
echo "Select backup type:"
echo "1. Only Schema"
echo "2. Schema with Data"
read -p "Enter choice (1/2): " BACKUP_TYPE

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
    *)
        log_message "ERROR: Invalid choice. Please select either 1 or 2."
        exit 1
        ;;
esac

# Compress the backups
log_message "Compressing backups..."
if [ "$BACKUP_TYPE" -eq 1 ]; then
    tar -czf "$OUTPUT_DIR/schema_only_backup.tar.gz" -C "$BACKUP_DIR/schema_only_backup" .
elif [ "$BACKUP_TYPE" -eq 2 ]; then
    tar -czf "$OUTPUT_DIR/schema_with_data_backup.tar.gz" -C "$BACKUP_DIR/schema_with_data_backup" .
fi
log_message "Backups compressed successfully."

# Final log message
log_message "Backup process completed!"
log_message "Backups are stored in: $BACKUP_DIR"
log_message "Logs are stored in: $OUTPUT_DIR/logs"
