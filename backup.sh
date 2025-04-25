#!/bin/bash

# Configuration file path
CONFIG_FILE=~/.backup_config

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

# Function to load existing config or prompt user
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

# Function to prompt user for configuration details
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

# Load configuration
load_config

# Prompt for password
read -s -p "Enter password: " DBPASS
echo

# Export password
export PGPASSWORD="$DBPASS"

# Test database connection
read -p "Enter the output directory: " OUTPUT_DIR
mkdir -p "$OUTPUT_DIR/logs"

# Create unique log file
SCRIPT_NAME=$(basename "$0" | sed 's/\.sh//')
LOG_FILE="$OUTPUT_DIR/logs/$(date +'%Y_%m_%d_%H_%M')_${SCRIPT_NAME}.log"
test_connection

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
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
BACKUP_DIR="$OUTPUT_DIR/backups/$TIMESTAMP"

# Ask user for backup type
echo "Select backup type:"
echo "1. Tables with data"
echo "2. Schema-only"
echo "3. Both"
read -p "Enter choice (1/2/3): " CHOICE

# Ask for path based on user choice
case "$CHOICE" in
    1)
        read -p "Enter path to the 'withdata' table list file: " TABLE_WITH_DATA
        if [ ! -f "$TABLE_WITH_DATA" ]; then
            log_message "ERROR: The 'withdata' table list file does not exist at the provided path: $TABLE_WITH_DATA"
            exit 1
        fi
        BACKUP_DIR="$OUTPUT_DIR/backups/withdata/$TIMESTAMP"
        mkdir -p "$BACKUP_DIR"
        ;;
    2)
        read -p "Enter path to the 'withoutdata' table list file: " TABLE_WITHOUT_DATA
        if [ ! -f "$TABLE_WITHOUT_DATA" ]; then
            log_message "ERROR: The 'withoutdata' table list file does not exist at the provided path: $TABLE_WITHOUT_DATA"
            exit 1
        fi
        BACKUP_DIR="$OUTPUT_DIR/backups/withoutdata/$TIMESTAMP"
        mkdir -p "$BACKUP_DIR"
        ;;
    3)
        read -p "Enter path to the 'withdata' table list file: " TABLE_WITH_DATA
        read -p "Enter path to the 'withoutdata' table list file: " TABLE_WITHOUT_DATA
        if [ ! -f "$TABLE_WITH_DATA" ]; then
            log_message "ERROR: The 'withdata' table list file does not exist at the provided path: $TABLE_WITH_DATA"
            exit 1
        fi
        if [ ! -f "$TABLE_WITHOUT_DATA" ]; then
            log_message "ERROR: The 'withoutdata' table list file does not exist at the provided path: $TABLE_WITHOUT_DATA"
            exit 1
        fi
        BACKUP_DIR="$OUTPUT_DIR/backups/both/$TIMESTAMP"
        mkdir -p "$BACKUP_DIR"
        ;;
    *)
        log_message "ERROR: Invalid choice."
        exit 1
        ;;
esac

# Backup function
backup_table() {
    local table="$1"
    local type="$2"
    local backup_dir="$BACKUP_DIR/${table}_${type}_backup"
    local compressed_file="${backup_dir}.tar.gz"

    mkdir -p "$backup_dir"

    log_message "Backing up $type for table: $table -> $backup_dir"
    if [ "$type" == "withdata" ]; then
        pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" --table="$table" -Fd -j "$JOBS" -f "$backup_dir"
    elif [ "$type" == "withoutdata" ]; then
        pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" --table="$table" -Fd -j "$JOBS" -f "$backup_dir" --schema-only
    fi

    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to backup $type for table: $table"
        return
    fi

    log_message "Compressing backup for table: $table -> $compressed_file"
    tar -czf "$compressed_file" -C "$backup_dir" .
    rm -rf "$backup_dir"

    log_message "SUCCESS: $type for $table backed up and compressed to $compressed_file"
}

# Process based on choice
case "$CHOICE" in
    1)
        while IFS= read -r table; do
            backup_table "$table" "withdata"
        done < "$TABLE_WITH_DATA"
        ;;
    2)
        while IFS= read -r table; do
            backup_table "$table" "withoutdata"
        done < "$TABLE_WITHOUT_DATA"
        ;;
    3)
        while IFS= read -r table; do
            backup_table "$table" "withdata"
        done < "$TABLE_WITH_DATA"
        while IFS= read -r table; do
            backup_table "$table" "withoutdata"
        done < "$TABLE_WITHOUT_DATA"
        ;;
    *)
        log_message "ERROR: Invalid choice."
        exit 1
        ;;
esac

log_message "Backup process completed!"
