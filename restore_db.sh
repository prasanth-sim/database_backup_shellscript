#!/bin/bash

# Source the configuration script
source ./config_db.sh

# ----------------------------------
# General Helper Functions
# ----------------------------------

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message"
}

# Function to test database connection
test_connection() {
    log_message "Testing database connection..."
    if ! psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d postgres -c "\q" &>/dev/null; then
        log_message "ERROR: Failed to authenticate with the database. Please check your credentials."
        exit 1
    fi
}

# ----------------------------------
# Database Management
# ----------------------------------

# Function to check if the database exists
check_database() {
    log_message "Checking if database '$DBNAME' exists..."
    DATABASE_EXISTS=$(psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -tAc "SELECT 1 FROM pg_database WHERE datname = '$DBNAME';")

    if [ "$DATABASE_EXISTS" == "1" ]; then
        log_message "Database '$DBNAME' already exists."
        manage_existing_database
    else
        log_message "Database '$DBNAME' does not exist. Creating it now..."
        create_database
    fi
}

# Function to manage an existing database
manage_existing_database() {
    echo "Select action for the existing database:"
    echo "1. Skip (keep existing database)"
    echo "2. Recreate (drop and create a new database)"
    read -p "Enter choice (1/2): " DB_ACTION

    case "$DB_ACTION" in
        1)
            log_message "Skipping database creation. Existing database will be used."
            ;;
        2)
            log_message "Recreating database '$DBNAME'..."
            dropdb -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" "$DBNAME"
            create_database
            ;;
        *)
            log_message "ERROR: Invalid choice. Exiting."
            exit 1
            ;;
    esac
}

# Function to create a new database
create_database() {
    createdb -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" "$DBNAME"
    if [ $? -eq 0 ]; then
        log_message "Database '$DBNAME' has been successfully created."
    else
        log_message "ERROR: Failed to create database '$DBNAME'."
        exit 1
    fi
}

# ----------------------------------
# Restore Operations
# ----------------------------------

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

# Function to prompt for the restore type
restore_type_prompt() {
    echo "Select restore type:"
    echo "1. Schema Only"
    echo "2. Schema with Data"
    read -p "Enter choice (1/2): " RESTORE_TYPE

    case "$RESTORE_TYPE" in
        1)
            log_message "Schema-only restore selected."
            restore_schema_only
            ;;
        2)
            log_message "Schema-with-data restore selected."
            restore_schema_with_data
            ;;
        *)
            log_message "ERROR: Invalid choice. Please select either 1 or 2."
            exit 1
            ;;
    esac
}

# Function to restore schema only
restore_schema_only() {
    read -p "Enter the path to the schema-only backup directory: " BACKUP_DIR
    if [ ! -d "$BACKUP_DIR" ]; then
        log_message "ERROR: Backup directory '$BACKUP_DIR' does not exist."
        exit 1
    fi

    log_message "Restoring schema-only backup from: $BACKUP_DIR..."
    pg_restore -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" --clean --if-exists --no-owner --no-privileges --no-data -Fd -j "$JOBS" "$BACKUP_DIR"
    if [ $? -eq 0 ]; then
        log_message "Schema-only restore completed successfully."
    else
        log_message "ERROR: Schema-only restore failed."
        exit 1
    fi
}

# Function to restore schema with data
restore_schema_with_data() {
    read -p "Enter the path to the schema-with-data backup directory: " BACKUP_DIR
    if [ ! -d "$BACKUP_DIR" ]; then
        log_message "ERROR: Backup directory '$BACKUP_DIR' does not exist."
        exit 1
    fi

    log_message "Restoring schema-with-data backup from: $BACKUP_DIR..."

    # Notify user about excluded tables
    if [ -f "$EXCLUDE_FILE" ]; then
        log_message "Excluded tables during the backup:"
        while read -r table; do
            log_message " - $table (Data excluded during backup, structure will remain intact)"
        done < "$EXCLUDE_FILE"
    else
        log_message "WARNING: Exclude file '$EXCLUDE_FILE' not found. All tables may be restored."
    fi

    # Perform the restore
    pg_restore -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" $EXCLUDE_CMD --clean --if-exists --no-owner --no-privileges -Fd -j "$JOBS" "$BACKUP_DIR"
    if [ $? -eq 0 ]; then
        log_message "Schema-with-data restore completed successfully."
    else
        log_message "ERROR: Schema-with-data restore failed."
        exit 1
    fi
}

# ----------------------------------
# Main Script Execution
# ----------------------------------

# Prompt for password
read -s -p "Enter password: " DBPASS
echo

# Export password for PostgreSQL commands
export PGPASSWORD="$DBPASS"

# Load configuration
load_config

# Test database connection
test_connection

# Check and manage database existence
check_database

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

# Prompt for restore type
restore_type_prompt

# Final log message
LOG_DIR="${PWD}/logs"
log_message "Restore process completed successfully!"
log_message "Database restored to: $DBNAME"
log_message "Logs are stored in: $LOG_DIR"
