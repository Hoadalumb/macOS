#!/bin/bash

# Varibales for the script
msupdate="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
logdir="/var/log/troubleshooting"
logfile="msupdate.log"
log="$logdir/$logfile"

# Function for log directory creation
createlogdir() {
    if [[ -d $logdir ]]; then
        # Logdirectory existing
        echo "# $(date) | Found Logdirectory $logdir"
        else
        # Logdirectory not found
        echo "# $(date) | Logdirectory $logdir will be created"
        mkdir -p "$logdir"
        echo "# $(date) | Logdirectory $logdir successfully created"
    fi
    
}

# Start Logging
createlogdir
exec &> >(tee -a "$log")

# Check if Microsoft Company Portal app is open
companyPortalpid=$(pgrep -f "Company Portal")

if [ -n "$companyPortalpid" ]; then
# Close Microsoft Company Portal app
kill "$companyPortalpid"
echo "Closed Microsoft Company Portal app."
fi

# Check if Microsoft OneDrive app is open
oneDrivePID=$(pgrep -f "OneDrive")

if [ -n "$oneDrivePID" ]; then
# Close Microsoft OneDrive app
kill "$oneDrivePID"
echo "Closed Microsoft OneDrive app."
fi

# Update Microsoft applications using msupdate
"$msupdate" --install --apps ONDR18 IMCP01