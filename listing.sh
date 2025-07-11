#!/bin/bash

# Default config file path
CONFIG_FILE="${HOME}/.db_listing_config"

# Load previous configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}
# Save current configuration
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat <<EOF > "$CONFIG_FILE"
DBNAME="$DBNAME"
DBUSER="$DBUSER"
DBHOST="$DBHOST"
DBPORT="$DBPORT"
OUTDIR="$OUTDIR"
EOF
}

# Ask user for confirmation to use existing config
confirm_config() {
    echo "Current configuration:"
    echo "Database Name: $DBNAME"
    echo "User: $DBUSER"
    echo "Host: $DBHOST"
    echo "Port: $DBPORT"
    echo "Output Directory: $OUTDIR"
    read -p "Do you want to use these settings? (y/n) [y]: " CONFIRM
    CONFIRM=${CONFIRM:-y}
}

# Test database connection
test_connection() {
    log_message "Testing database connection..."
    if ! psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -c "\q" &>/dev/null; then
        log_message "ERROR: Failed to authenticate with the database. Please check your credentials."
        exit 1
    fi
}

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message" | tee -a "$LOG_FILE"
}

# Load existing config if available
load_config

if [ -n "$DBNAME" ] && [ -n "$DBUSER" ] && [ -n "$DBHOST" ] && [ -n "$DBPORT" ] && [ -n "$OUTDIR" ]; then
    confirm_config
else
    CONFIRM="n"
fi

if [ "$CONFIRM" == "n" ]; then
    # Prompt for new configuration if not confirmed or missing
    read -p "Enter database name: " DBNAME
    read -p "Enter PostgreSQL user: " DBUSER
    read -p "Enter host [localhost]: " DBHOST
    DBHOST=${DBHOST:-localhost}
    read -p "Enter port [5432]: " DBPORT
    DBPORT=${DBPORT:-5432}
    read -p "Enter output directory [${HOME}]: " OUTDIR
    OUTDIR=${OUTDIR:-${HOME}}

    # Save the new configuration
    save_config
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

# Get all user tables and save to a timestamped alltables file
ALLTABLES_FILE="$RUN_DIR/alltables_$TIMESTAMP.txt"
psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -Atc \
    "SELECT schemaname || '.' || tablename FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');" \
    > "$ALLTABLES_FILE"
log_message "Generated list of all tables."

# Files for tables with and without data
WITHDATA_FILE="$RUN_DIR/withdata_$TIMESTAMP.txt"
WITHOUTDATA_FILE="$RUN_DIR/withoutdata_$TIMESTAMP.txt"

# Clear (or create) output files
> "$WITHDATA_FILE"
> "$WITHOUTDATA_FILE"

# Loop through tables and check for data
log_message "Checking tables for data..."
while IFS= read -r table; do
    count=$(psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -Atc "SELECT COUNT(*) FROM $table;")
    if [ "$count" -gt 0 ]; then
        echo "$table" >> "$WITHDATA_FILE"
        log_message "Table $table contains data."
    else
        echo "$table" >> "$WITHOUTDATA_FILE"
        log_message "Table $table does not contain data."
    fi
done < "$ALLTABLES_FILE"

log_message "Completed processing tables."

log_message "Files generated:"
log_message " - $ALLTABLES_FILE"
log_message " - $WITHDATA_FILE"
log_message " - $WITHOUTDATA_FILE"

log_message "Script execution completed successfully."
listing.txt
Displaying listing.txt.
