#!/bin/bash

CONFIG_FILE="./restore_config.cfg"

# Log message function
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message"
}

load_config() {
    # Load previously saved configuration if it exists
    if [[ -f "$CONFIG_FILE" ]]; then
        log_message "Found existing configuration file: $CONFIG_FILE"
        source "$CONFIG_FILE"

        echo "Previously saved configuration:"
        echo "  Database Host: $DBHOST"
        echo "  Database Port: $DBPORT"
        echo "  Database Name: $DBNAME"
        echo "  Database User: $DBUSER"
        echo "  Exclude File: $EXCLUDE_FILE"
        echo

        read -p "Would you like to reuse the previous configuration? (yes/no): " REUSE_CONFIG
        if [[ "$REUSE_CONFIG" == "yes" ]]; then
            log_message "Reusing previous configuration."
            return
        else
            log_message "Updating configuration..."
        fi
    fi

    # Prompt for database host
    read -p "Enter database host (default: localhost): " DBHOST
    DBHOST=${DBHOST:-localhost}

    # Prompt for database port
    read -p "Enter database port (default: 5432): " DBPORT
    DBPORT=${DBPORT:-5432}

    # Prompt for database name
    read -p "Enter target database name: " DBNAME
    if [[ -z "$DBNAME" ]]; then
        log_message "ERROR: Database name cannot be empty."
        exit 1
    fi

    # Prompt for database username
    read -p "Enter database username: " DBUSER
    if [[ -z "$DBUSER" ]]; then
        log_message "ERROR: Username cannot be empty."
        exit 1
    fi

    # Prompt for excluded tables file path
    read -p "Enter path to the file with tables to exclude (optional): " EXCLUDE_FILE
    if [[ ! -z "$EXCLUDE_FILE" && ! -f "$EXCLUDE_FILE" ]]; then
        log_message "ERROR: Specified exclude file '$EXCLUDE_FILE' does not exist."
        exit 1
    fi

    # Save the configuration
    log_message "Saving configuration to $CONFIG_FILE..."
    cat > "$CONFIG_FILE" <<EOL
DBHOST=$DBHOST
DBPORT=$DBPORT
DBNAME=$DBNAME
DBUSER=$DBUSER
EXCLUDE_FILE=$EXCLUDE_FILE
EOL

    log_message "Configuration saved successfully."
}

