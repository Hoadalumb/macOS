#!/bin/bash

# Read the serial number from the device
SERIAL_NUMBER=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $3}')

# Print the serial number
echo "Serial Number: $SERIAL_NUMBER"

# Set the serial number
SERIAL_NUMBER="YOUR_SERIAL_NUMBER_HERE"

# Generate a password based on the serial number
NEW_ADMIN_PASSWORD=$(echo -n $SERIAL_NUMBER | sha256sum | base64 | head -c 12)

# Encrypt the password
ENCRYPTED_PASSWORD=$(perl -e 'print crypt($ARGV[0], "password"),"\n"' $NEW_ADMIN_PASSWORD)

# Print the generated password and its encrypted form
echo "Generated password: $NEW_ADMIN_PASSWORD"
echo "Encrypted password: $ENCRYPTED_PASSWORD"

# Create the new admin user
sudo dscl . -create /Users/newadmin
sudo dscl . -create /Users/newadmin UserShell /bin/bash
sudo dscl . -create /Users/newadmin RealName "New Admin"
sudo dscl . -create /Users/newadmin UniqueID 503
sudo dscl . -create /Users/newadmin PrimaryGroupID 80
sudo dscl . -create /Users/newadmin NFSHomeDirectory /Users/newadmin

# Set the encrypted password for the new admin user
sudo dscl . -passwd /Users/newadmin <<EOF
$ENCRYPTED_PASSWORD
$ENCRYPTED_PASSWORD
EOF