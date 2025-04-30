#!/bin/bash

# Include the configuration functions
source "./config_db.sh"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message"
}

# Validate that required variables are set
if [[ -z "$DBNAME" || -z "$DBUSER" || -z "$DBHOST" || -z "$DBPORT" ]]; then
    log_message "Error: One or more required configuration values are missing."
    exit 1
fi
# Ask for the password interactively
read -s -p "Enter PostgreSQL password for user $DBUSER: " DBPASS
echo ""  # Move to the next line after password entry

# Export PostgreSQL password for session authentication
export PGPASSWORD="$DBPASS"

# Define the output directory dynamically based on DBNAME
read -p "Enter the output directory: " OP_DIR
mkdir -p "$OP_DIR"
TIMESTAMP=$(date "+%Y_%m_%d_%H_%M") 
OUTPUT_DIR="$OP_DIR/${DBNAME}/${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

# Define log and output files
LOG_FILE="$OUTPUT_DIR/${TIMESTAMP}_list.log"
ALL_TABLES_FILE="$OUTPUT_DIR/alltables.txt"
CONTAINS_DATA_FILE="$OUTPUT_DIR/contains_data.txt"
EMPTY_TABLES_FILE="$OUTPUT_DIR/empty.txt"

# Redirect stdout and stderr to the log file
exec > >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE")

log_message "Testing database connection..."
psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -c "SELECT 1;" &>/dev/null
if [[ $? -ne 0 ]]; then
    log_message "Error: Unable to connect to database $DBNAME"
    exit 1
fi

log_message "Starting script execution."

# Get list of all tables
log_message "Fetching list of all tables..."
psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -t -c \
"SELECT tablename FROM pg_tables WHERE schemaname = 'public';" > "$ALL_TABLES_FILE"

if [[ ! -s "$ALL_TABLES_FILE" ]]; then
    log_message "No tables found in database $DBNAME."
    exit 0
fi

log_message "Checking tables for data..."

# Categorize tables based on whether they contain data
while read -r table; do
    row_count=$(psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -t -c "SELECT COUNT(*) FROM \"$table\";")
    row_count=$(echo "$row_count" | xargs)  # Remove leading/trailing spaces
    log_message "Table: $table | Rows: $row_count"
    if [[ "$row_count" -gt 0 ]]; then
        echo "$table" >> "$CONTAINS_DATA_FILE"
    else
        echo "$table" >> "$EMPTY_TABLES_FILE"
    fi
done < "$ALL_TABLES_FILE"

log_message "Script execution completed successfully."
log_message "Tables with data stored in: $CONTAINS_DATA_FILE"
log_message "Empty tables stored in: $EMPTY_TABLES_FILE"

# Unset the password after execution for security
unset PGPASSWORD
