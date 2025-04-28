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

# Create unique folder for this restore run
read -p "Enter the output directory: " OUTPUT_DIR
mkdir -p "$OUTPUT_DIR/logs"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')"
RESTORE_DIR="$OUTPUT_DIR/restores/$TIMESTAMP"
mkdir -p "$RESTORE_DIR"

# Test database connection
test_connection

# Ask the user for restore type
echo "Select restore type:"
echo "1. Only Schema"
echo "2. Schema with Data"
read -p "Enter choice (1/2): " RESTORE_TYPE

case "$RESTORE_TYPE" in
    1)
        log_message "Schema-only restore selected."
        log_message "Starting schema-only restore..."
        pg_restore -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" --clean --if-exists --no-owner --no-privileges --no-data -Fd -j "$JOBS" "$RESTORE_DIR/schema_only_backup"
        if [ $? -eq 0 ]; then
            log_message "Schema-only restore completed successfully."
        else
            log_message "ERROR: Schema-only restore failed."
            exit 1
        fi
        ;;
    2)
        log_message "Schema-with-data restore selected."
        read_excluded_tables
        log_message "Starting schema-with-data restore..."
        pg_restore -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" $EXCLUDE_CMD --clean --if-exists --no-owner --no-privileges -Fd -j "$JOBS" "$RESTORE_DIR/schema_with_data_backup"
        if [ $? -eq 0 ]; then
            log_message "Schema-with-data restore completed successfully."
        else
            log_message "ERROR: Schema-with-data restore failed."
            exit 1
        fi
        ;;
    *)
        log_message "ERROR: Invalid choice. Please select either 1 or 2."
        exit 1
        ;;
esac

# Final log message
log_message "Restore process completed!"
log_message "Restores are stored in: $RESTORE_DIR"
log_message "Logs are stored in: $OUTPUT_DIR/logs"
