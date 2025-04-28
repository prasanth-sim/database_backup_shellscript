
#!/bin/bash

# Config and Log Paths
CONFIG_FILE=~/.backup_config
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')

# Log function
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message" | tee -a "$LOG_FILE"
}

# Prompt or load config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "Loaded config: $DBNAME@$DBHOST:$DBPORT as $DBUSER"
        read -p "Use these settings? (y/n): " USE_PREVIOUS
        [ "$USE_PREVIOUS" != "y" ] && prompt_config
    else
        prompt_config
    fi
}

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

# DB connection and creation if needed
test_or_create_database() {
    if ! psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -c "\q" 2>/dev/null; then
        log_message "Database $DBNAME not found. Creating..."
        createdb -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" "$DBNAME"
        if [ $? -ne 0 ]; then
            log_message "ERROR: Failed to create database $DBNAME"
            exit 1
        fi
    else
        log_message "Connected to database $DBNAME."
    fi
}

# Prompt for directory and prepare
setup_output_directory() {
    read -p "Enter the output directory: " OUTPUT_DIR
    mkdir -p "$OUTPUT_DIR/logs"
    LOG_FILE="$OUTPUT_DIR/logs/backup_$TIMESTAMP.log"
    BACKUP_BASE="$OUTPUT_DIR/backups/$DBNAME/$TIMESTAMP"
    mkdir -p "$BACKUP_BASE"
}

# Backup views
backup_views() {
    log_message "Backing up views..."
    pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -s \
        $(psql -At -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" \
        -c "SELECT '-t ' || quote_ident(schemaname) || '.' || quote_ident(viewname) FROM pg_views WHERE schemaname NOT IN ('pg_catalog', 'information_schema');") \
        -f "$BACKUP_BASE/views.sql"
}

# Backup materialized views
backup_materialized_views() {
    log_message "Backing up materialized views..."
    pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -s \
        $(psql -At -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" \
        -c "SELECT '-t ' || quote_ident(schemaname) || '.' || quote_ident(matviewname) FROM pg_matviews;") \
        -f "$BACKUP_BASE/materialized_views.sql"
}

# Backup sequences
backup_sequences() {
    log_message "Backing up sequences..."
    pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -s \
        $(psql -At -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" \
        -c "SELECT '-t ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE relkind = 'S';") \
        -f "$BACKUP_BASE/sequences.sql"
}

# Backup functions
backup_functions() {
    log_message "Backing up functions..."
    pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -s | grep -i "create function" > "$BACKUP_BASE/functions.sql"
}

# Backup tables with or without data
backup_tables() {
    echo "Table Backup Options:"
    echo "1. Backup Tables WITH Data"
    echo "2. Backup Tables WITHOUT Data"
    read -p "Choose (1 or 2): " TABLE_OPTION
    read -p "Enter schema name (e.g., public): " TABLE_SCHEMA
    read -p "Enter table names (comma-separated) or 'all': " TABLE_NAMES

    mkdir -p "$BACKUP_BASE/tables"

    if [ "$TABLE_NAMES" == "all" ]; then
        TABLE_LIST=$(psql -At -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" \
            -c "SELECT tablename FROM pg_tables WHERE schemaname = '$TABLE_SCHEMA';")
    else
        IFS=',' read -ra TABLE_LIST <<< "$TABLE_NAMES"
    fi

    for table in ${TABLE_LIST[@]}; do
        DUMP_FILE="$BACKUP_BASE/tables/${table}.sql"

        if [ "$TABLE_OPTION" == "1" ]; then
            log_message "Backing up table $table WITH data..."
            pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" \
                -t "$TABLE_SCHEMA.$table" -f "$DUMP_FILE"
        else
            log_message "Backing up table $table WITHOUT data..."
            pg_dump -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" \
                -t "$TABLE_SCHEMA.$table" --schema-only -f "$DUMP_FILE"
        fi
    done
    log_message "Tables backup completed."
}

# Full schema backup
full_schema_backup() {
    read -p "Enter schema to backup (e.g. public): " SCHEMA
    read -p "Schema only? (y/n): " SCHEMA_ONLY
    mkdir -p "$BACKUP_BASE/schema"

    DUMP_CMD="pg_dump -h \"$DBHOST\" -p \"$DBPORT\" -U \"$DBUSER\" -d \"$DBNAME\" -n \"$SCHEMA\" -Fd -j $(nproc) \
        --no-owner --no-privileges --no-tablespaces -f \"$BACKUP_BASE/schema/$SCHEMA\""
    [ "$SCHEMA_ONLY" == "y" ] && DUMP_CMD="$DUMP_CMD --schema-only"

    log_message "Executing schema backup for $SCHEMA"
    eval "$DUMP_CMD"

    tar -czf "$BACKUP_BASE/${SCHEMA}_schema.tar.gz" -C "$BACKUP_BASE/schema/$SCHEMA" .
    rm -rf "$BACKUP_BASE/schema/$SCHEMA"
    log_message "Schema $SCHEMA backed up and compressed."
}

# Write backup metadata
write_metadata() {
    METADATA_FILE="$BACKUP_BASE/backup_metadata.txt"
    {
        echo "Environment: $(read -p 'Enter environment (dev/stage/prod): ' env && echo $env)"
        echo "Application: $(read -p 'Enter application name: ' app && echo $app)"
        echo "Date: $TIMESTAMP"
        echo "Database: $DBNAME"
        echo "Host: $DBHOST"
        echo "Port: $DBPORT"
        echo "Output Directory: $OUTPUT_DIR"
        echo "Schema: $SCHEMA"
    } > "$METADATA_FILE"
    log_message "Backup metadata saved to $METADATA_FILE"
}

# Execution
load_config
read -s -p "Enter password: " DBPASS
echo
export PGPASSWORD="$DBPASS"
test_or_create_database
setup_output_directory

# Choose backup path
echo "Backup Options:"
echo "1. Backup Views"
echo "2. Backup Materialized Views"
echo "3. Backup Sequences"
echo "4. Backup Functions"
echo "5. Full Schema Backup"
echo "6. Backup Tables"
read -p "Enter choices (e.g., 1,3,5): " BACKUP_CHOICES

IFS=',' read -ra CHOICES <<< "$BACKUP_CHOICES"
for CHOICE in "${CHOICES[@]}"; do
    case "$CHOICE" in
        1) backup_views ;;
        2) backup_materialized_views ;;
        3) backup_sequences ;;
        4) backup_functions ;;
        5) full_schema_backup ;;
        6) backup_tables ;;
        *) log_message "Invalid choice: $CHOICE" ;;
    esac
done

write_metadata
log_message "Backup completed."
