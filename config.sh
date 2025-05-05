#!/bin/bash

# Get the mode from argument (should be 'backup' or 'restore')
MODE="$1"
if [[ "$MODE" != "backup" && "$MODE" != "restore" ]]; then
    echo "Usage: $0 [backup|restore]"
    exit 1
fi

# Set config file path based on mode
CONFIG_FILE=~/.${MODE}_config

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message"
}

# Function to prompt user for configuration details
prompt_config() {
    read -p "Enter ${MODE} database name: " DBNAME
    if [[ -z "$DBNAME" ]]; then
        log_message "ERROR: Database name cannot be empty."
        exit 1
    fi

    read -p "Enter PostgreSQL username: " DBUSER
    if [[ -z "$DBUSER" ]]; then
        log_message "ERROR: Username cannot be empty."
        exit 1
    fi

    read -p "Enter host (default: localhost): " DBHOST
    DBHOST=${DBHOST:-localhost}

    read -p "Enter port (default: 5432): " DBPORT
    DBPORT=${DBPORT:-5432}

    read -p "Enter path to the exclude file (leave blank if not needed): " EXCLUDE_FILE
    if [[ -n "$EXCLUDE_FILE" && ! -f "$EXCLUDE_FILE" ]]; then
        log_message "ERROR: Specified exclude file '$EXCLUDE_FILE' does not exist."
        exit 1
    fi

    # Save configuration to file
    {
        echo "DBNAME=$DBNAME"
        echo "DBUSER=$DBUSER"
        echo "DBHOST=$DBHOST"
        echo "DBPORT=$DBPORT"
    } > "$CONFIG_FILE"

    if [[ -n "$EXCLUDE_FILE" ]]; then
        echo "EXCLUDE_FILE=$EXCLUDE_FILE" >> "$CONFIG_FILE"
    fi

    log_message "Configuration saved to $CONFIG_FILE."
}

# Function to load existing configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "Loaded existing $MODE configuration:"
        echo "Database Name: $DBNAME"
        echo "Username: $DBUSER"
        echo "Host: $DBHOST"
        echo "Port: $DBPORT"

        if [[ -n "$EXCLUDE_FILE" ]]; then
            echo "Exclude File: $EXCLUDE_FILE"
        else
            echo "No exclude file specified."
        fi

        read -p "Do you want to continue with this configuration? (y/n): " confirm
        if [[ "$confirm" =~ ^[Nn]$ ]]; then
            log_message "User chose to update the configuration."
            prompt_config
        else
            log_message "Continuing with the existing configuration."
        fi
    else
        log_message "Configuration file not found. Prompting for configuration details..."
        prompt_config
    fi
}

# Main logic
load_config

