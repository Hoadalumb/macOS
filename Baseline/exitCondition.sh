#!/usr/bin/env bash
set -e

# Path to the exit-condition file
EXIT_PATH="/Library/Application Support/APITMS365/.baseline_completed"

# Create parent directory if it doesn't exist
mkdir -p "/Library/Application Support/APITMS365"

# Create the hidden file
touch "$EXIT_PATH"

# Set restrictive permissions (root read/write only)
chmod 755 "$EXIT_PATH"
chown root:wheel "$EXIT_PATH"

echo "Created exit-condition file: $EXIT_PATH"
