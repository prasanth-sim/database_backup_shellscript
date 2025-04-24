#!/bin/bash

# Configuration
CONFIG_FILE=~/.restore_config

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message" | tee -a "$LOG_FILE"
}

# Load config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "Loaded existing configuration:"
        echo "Database Name: $DBNAME"
        echo "User: $DBUSER"
        echo "Host: $DBHOST"
        echo "Port: $DBPORT"
        read -p "Use these settings? (y/n): " USE_PREVIOUS
        if [ "$USE_PREVIOUS" != "y" ]; then
            prompt_config
        fi
    else
        prompt_config
    fi
}

# Prompt for new configuration
prompt_config() {
    read -p "Enter database name: " DBNAME
    read -p "Enter PostgreSQL user: " DBUSER
    read -p "Enter host (default: localhost): " DBHOST
    DBHOST=${DBHOST:-localhost}
    read -p "Enter port (default: 5432): " DBPORT
    DBPORT=${DBPORT:-5432}
    echo "DBNAME=$DBNAME" > "$CONFIG_FILE"
    echo "DBUSER=$DBUSER" >> "$CONFIG_FILE"
    echo "DBHOST=$DBHOST" >> "$CONFIG_FILE"
    echo "DBPORT=$DBPORT" >> "$CONFIG_FILE"
}

# Function to test connection
test_connection() {
    log_message "Testing connection to database '$DBNAME'..."
    if PGPASSWORD="$DBPASS" psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -c '\q' 2>/dev/null; then
        log_message "SUCCESS: Connection to '$DBNAME' is successful."
    else
        log_message "ERROR: Unable to connect to database '$DBNAME'. Check credentials and network."
        exit 1
    fi
}

# Load configuration
load_config

# Prompt for password
read -s -p "Enter password: " DBPASS
echo
export PGPASSWORD="$DBPASS"

# Test database connection
test_connection

# Prompt for output/log directory
read -p "Enter the log/output directory: " OUTPUT_DIR
mkdir -p "$OUTPUT_DIR/logs"

# Create log file
SCRIPT_NAME=$(basename "$0" | sed 's/\.sh//')
LOG_FILE="$OUTPUT_DIR/logs/$(date +'%Y_%m_%d_%H_%M')_${SCRIPT_NAME}.log"

# Check if database exists
log_message "Checking if database '$DBNAME' exists..."
if ! psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -tAc "SELECT 1 FROM pg_database WHERE datname = '$DBNAME'" | grep -q 1; then
    log_message "Database not found. Creating..."
    createdb -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" "$DBNAME"
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to create database."
        exit 1
    fi
else
    log_message "Database already exists."
fi

# Determine parallel jobs
CPU_CORES=$(nproc)
read -p "Enter number of parallel jobs for restore (max: $CPU_CORES): " JOBS
if (( JOBS > CPU_CORES )); then
    log_message "Specified jobs exceed available CPU cores. Setting to $CPU_CORES."
    JOBS=$CPU_CORES
elif (( JOBS < 1 )); then
    log_message "Invalid input. Setting jobs to 1."
    JOBS=1
fi
log_message "Using $JOBS parallel jobs for restore."

# Number of files
read -p "Enter number of backup files to restore: " NUMFILES

# Restore loop
for (( i=1; i<=NUMFILES; i++ )); do
    read -p "Enter path to backup file #$i (.tar.gz): " BACKUPFILE

    if [ ! -f "$BACKUPFILE" ]; then
        log_message "ERROR: File not found - $BACKUPFILE"
        continue
    fi

    EXTRACTED_DIR=$(mktemp -d)
    log_message "Extracting $BACKUPFILE..."
    tar -xzf "$BACKUPFILE" -C "$EXTRACTED_DIR"
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to extract $BACKUPFILE"
        rm -rf "$EXTRACTED_DIR"
        continue
    fi

    log_message "Restoring $BACKUPFILE into $DBNAME..."
    pg_restore -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -j "$JOBS" --clean --if-exists --no-owner --no-privileges "$EXTRACTED_DIR"
    if [ $? -eq 0 ]; then
        log_message "SUCCESS: Restored $BACKUPFILE"
    else
        log_message "ERROR: Failed to restore $BACKUPFILE"
    fi

    rm -rf "$EXTRACTED_DIR"
done

log_message "Restore process completed."
unset PGPASSWORD

