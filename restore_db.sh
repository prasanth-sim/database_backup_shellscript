#!/bin/bash
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message"
}

if [ -f "./config_restore.sh" ]; then
    source ./config_restore.sh
    log_message "Configuration loaded from config_restore.sh."
else
    log_message "ERROR: Configuration file 'config_restore.sh' not found."
    exit 1
fi

test_connection() {
    log_message "Testing database connection..."
    if ! psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d postgres -c "\q" &>/dev/null; then
        log_message "ERROR: Failed to connect to PostgreSQL. Check credentials or connection."
        exit 1
    fi
}

check_database() {
    log_message "Checking if database '$DBNAME' exists..."
    local exists
    exists=$(psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DBNAME';")

    if [[ "$exists" == "1" ]]; then
        log_message "Database '$DBNAME' already exists."
        manage_existing_database
    else
        log_message "Database '$DBNAME' does not exist. Creating..."
        create_database
    fi
}

manage_existing_database() {
    echo "1. Skip (use existing)"
    echo "2. Recreate (drop and recreate)"
    read -p "Enter choice (1/2): " choice
    case "$choice" in
        1) log_message "Using existing database." ;;
        2)
            log_message "Dropping and recreating '$DBNAME'..."
            dropdb -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" "$DBNAME"
            create_database
            ;;
        *) log_message "ERROR: Invalid choice."; exit 1 ;;
    esac
}

create_database() {
    createdb -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" "$DBNAME"
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to create database '$DBNAME'."
        exit 1
    fi
}

read_excluded_tables() {
    if [ ! -f "$EXCLUDE_FILE" ]; then
        log_message "ERROR: Exclude file '$EXCLUDE_FILE' does not exist."
        exit 1
    fi

    log_message "Reading excluded tables from: $EXCLUDE_FILE"
    EXCLUDE_CMD=$(awk '{print "--exclude-table-data=" $1}' "$EXCLUDE_FILE" | tr '\n' ' ')
    log_message "Excluded tables: $(awk '{print $1}' "$EXCLUDE_FILE" | tr '\n' ', ')"
}

# Restore Operations

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

restore_schema_with_data() {
    read -p "Enter the path to the schema-with-data backup directory: " BACKUP_DIR
    if [ ! -d "$BACKUP_DIR" ]; then
        log_message "ERROR: Backup directory '$BACKUP_DIR' does not exist."
        exit 1
    fi

    read_excluded_tables

    log_message "Restoring schema-with-data backup from: $BACKUP_DIR..."

    if [ -f "$EXCLUDE_FILE" ]; then
        log_message "Excluded tables during the backup:"
        while read -r table; do
            log_message " - $table (Data excluded during backup, structure will remain intact)"
        done < "$EXCLUDE_FILE"
    else
        log_message "WARNING: Exclude file '$EXCLUDE_FILE' not found. All tables may be restored."
    fi

    pg_restore -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" --clean --if-exists --no-owner --no-privileges -Fd -j "$JOBS" "$BACKUP_DIR"
    if [ $? -eq 0 ]; then
        log_message "Schema-with-data restore completed successfully."
    else
        log_message "ERROR: Schema-with-data restore failed."
        exit 1
    fi
}


# Prompt for password
read -s -p "Enter password for $DBUSER: " DBPASS
echo
export PGPASSWORD="$DBPASS"

# Test connection and prepare database
test_connection
check_database

# Create logs directory
read -p "Enter the log directory: " OUTPUT_DIR
mkdir -p "$OUTPUT_DIR/logs"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
LOG_DIR="$OUTPUT_DIR/$TIMESTAMP"
mkdir -p "$LOG_DIR"

# Set number of parallel jobs
CPU_CORES=$(nproc)
read -p "Enter number of parallel jobs (max $CPU_CORES): " JOBS
JOBS=$(( JOBS > CPU_CORES ? CPU_CORES : (JOBS < 1 ? 1 : JOBS) ))
log_message "Using $JOBS parallel jobs."

# Launch restore type prompt
restore_type_prompt

# Done
log_message "Restore script completed."
log_message "Logs stored in: $LOG_DIR"

