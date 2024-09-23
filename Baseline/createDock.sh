#!/bin/bash

# Define variables for exetuction
scriptname="addAppstoDock"
logfile="dockutil.log"
logdir="/var/log/troubleshooting"
log="$logdir/$logfile"
max_timeout=600
loggedInUser=$(stat -f%Su /dev/console)
dockutil="/usr/local/bin/dockutil"


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

# Array of Applications to add to dock

APPS=(
    "Microsoft Edge.app"
    "Microsoft Outlook.app"
    "Microsoft Teams.app"
    "Company Portal.app"
)

#Start Logging
createlogdir
exec &> >(tee -a "$log")

#Start Body of the Script

echo ""
echo "##############################################################"
echo "# $(date) | Starting $scriptname"
echo "##############################################################"
echo "# $(date) | Current logged-in user $loggedInUser"
echo "##############################################################"


# Check if all apps are successfully installed
# Loop through the array of applications

# Function to check if an application is installed

check_app_installed() {
    local app_name=$1
    local app_path="/Applications/$app_name"
    if [ -d "$app_path" ]; then
        return 0  # Return true if the app is found
    else
        return 1  # Return false if the app is not found
    fi
}

# Keep checking until all applications are installed
while true; do
    all_installed=true  # Assume all are installed

    # Iterate over each app in the list
    for app in "${APPS[@]}"; do
        if check_app_installed "$app"; then
            echo "# $(date) | $app is installed."
        else
            echo "# $(date) |$app is NOT installed yet. Checking again in 30 seconds..."
            all_installed=false  # Set flag to false if any app is not found
        fi
    done

    # Break the loop if all applications are installed
    if $all_installed; then
        echo "# $(date) | All applications are installed!"
        break
    fi

    # Wait for 30 seconds before checking again
    sleep 30
done

# Check for dockutil

if [[ -e $dockutil ]]; then
	echo "# $(date) | Dockutil wurde gefunden"
	else
	echo "# $(date) | Dockutil wurde nicht gefunden Vorgang wird abgebrochen"
	exit 1
fi
for app in "${APPS[@]}"; do
	echo "# $(date) | Die Applikation [$app] wird zum Dock hinzugefügt"
	sudo -u "$loggedInUser" $dockutil --add "/Applications/$app" --no-restart	
done

#Remove Bloatware from dock
echo "# $(date) | Starting remove Musik from Dock"
sudo -u "$loggedInUser" $dockutil --remove "Musik" --no-restart
echo "# $(date) | Starting remove TV from Dock"
sudo -u "$loggedInUser" $dockutil --remove "TV" --no-restart
echo "# $(date) | Starting remove Freeform from Dock"
sudo -u "$loggedInUser" $dockutil --remove "Freeform" --no-restart
killall Dock

exit 0
