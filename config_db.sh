#!/bin/bash

# Configuration file path
CONFIG_FILE=~/.backup_config

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date "+%H:%M:%S") $message"
}

# Function to prompt user for configuration details
prompt_config() {
    read -p "Enter database name: " DBNAME
    read -p "Enter PostgreSQL user: " DBUSER
    read -p "Enter host (default: localhost): " DBHOST
    DBHOST=${DBHOST:-localhost}
    read -p "Enter port (default: 5432): " DBPORT
    DBPORT=${DBPORT:-5432}
    read -p "Enter the path to the exclude file (leave blank if not needed): " EXCLUDE_FILE

    # Save configuration to file
    {
        echo "DBNAME=$DBNAME"
        echo "DBUSER=$DBUSER"
        echo "DBHOST=$DBHOST"
        echo "DBPORT=$DBPORT"
    } > "$CONFIG_FILE"

    # Save EXCLUDE_FILE only if provided
    if [[ -n "$EXCLUDE_FILE" ]]; then
        echo "EXCLUDE_FILE=$EXCLUDE_FILE" >> "$CONFIG_FILE"
    fi

    log_message "Configuration saved to $CONFIG_FILE."
}

# Function to load existing configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        echo "Loaded existing configuration:"
        echo "Database Name: $DBNAME"
        echo "User: $DBUSER"
        echo "Host: $DBHOST"
        echo "Port: $DBPORT"

        # Check if EXCLUDE_FILE is set before displaying it
        if [[ -n "$EXCLUDE_FILE" ]]; then
            echo "Exclude File: $EXCLUDE_FILE"
        else
            echo "No exclude file specified."
        fi

        # Ask if the user wants to continue with this configuration
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
