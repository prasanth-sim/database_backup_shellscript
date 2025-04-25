#!/bin/bash

# Default config file path
CONFIG_FILE="${HOME}/.db_script_config"

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

# Prompt for new configuration if not confirmed or missing
get_new_config() {
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
}

