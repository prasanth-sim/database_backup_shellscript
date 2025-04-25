#!/bin/bash

# Include the configuration functions
source "./config.sh"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message" | tee -a "$LOG_FILE"
}

# Test database connection
test_connection() {
    log_message "Testing database connection..."
    if ! psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -c "\q" &>/dev/null; then
        log_message "ERROR: Failed to authenticate with the database. Please check your credentials."
        exit 1
    fi
}

# Load existing config if available
load_config

if [ -n "$DBNAME" ] && [ -n "$DBUSER" ] && [ -n "$DBHOST" ] && [ -n "$DBPORT" ] && [ -n "$OUTDIR" ]; then
    confirm_config
else
    CONFIRM="n"
fi

if [ "$CONFIRM" == "n" ]; then
    get_new_config
fi

# Always ask for the password
read -s -p "Enter password: " DBPASS
echo

# Timestamp for unique directory creation
TIMESTAMP=$(date "+%Y_%m_%d_%H_%M")
RUN_DIR="$OUTDIR/$DBNAME/$TIMESTAMP"
mkdir -p "$RUN_DIR"

# Log file location within the run directory
LOG_FILE="$RUN_DIR/${TIMESTAMP}_list_script.log"

# Export password for psql
export PGPASSWORD="$DBPASS"

# Test the database connection before proceeding
test_connection

log_message "Starting script execution."

# Get all user tables and save to alltables.txt
ALLTABLES_FILE="$RUN_DIR/alltables.txt"
psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -Atc \
    "SELECT schemaname || '.' || tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');" \
    > "$ALLTABLES_FILE"
log_message "Generated list of all tables."

# Files for data presence
CONTAINS_DATA_FILE="$RUN_DIR/contains_data.txt"
EMPTY_FILE="$RUN_DIR/empty.txt"
> "$CONTAINS_DATA_FILE"
> "$EMPTY_FILE"

# Loop through tables and check for data
log_message "Checking tables for data..."
while IFS= read -r table; do
    count=$(psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -Atc "SELECT COUNT(*) FROM $table;")
    if [ "$count" -gt 0 ]; then
        echo "$table" >> "$CONTAINS_DATA_FILE"
        log_message "Table $table contains $count rows."
    else
        echo "$table" >> "$EMPTY_FILE"
        log_message "Table $table is empty."
    fi
done < "$ALLTABLES_FILE"


log_message "Script execution completed successfully."

