#!/bin/bash

# Define variables for exetuction
application="/usr/local/bin/dockutil"
scriptname="addAppstoDock"
logfile="dockutil.log"
logdir="/var/log/troubleshooting"
log="$logdir/$logfile"
max_timeout=300
killall="/usr/bin/killall"
loggedInUser=$( ls -l /dev/console | awk '{print $3}' )
LoggedInUserHome="/Users/$loggedInUser"
UserPlist=$LoggedInUserHome/Library/Preferences/com.apple.dock.plist
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

# Array of Applications to check

dockapps=(
    Microsoft Edge
    Microsoft Outlook
    Microsoft Teams
    Privileges
)

# Array of Applications to add to dock

appToadd=(
    "/Applications/Microsoft Edge.app"
    "/Applications/Microsoft Outlook.app"
    "/Applications/Microsoft Teams.app"
    "/Applications/Privileges.app"
)

#Start Logging
createlogdir
exec &> >(tee -a "$log")

#Start Body od´f the Script

echo ""
echo "##############################################################"
echo "# $(date) | Starting $scriptname"
echo "##############################################################"
echo "# $(date) | Current logged-in user $loggedInUser"
echo "##############################################################"


# Check if all apps are successfully installed
# Loop through the array of applications

for app in "${dockapps[@]}"; do
	echo "Waiting for $app to be installed..."
	timeout_count=0
	while true; do
		# Use the `mdfind` command to search for the application
		if mdfind "kMDItemCFBundleIdentifier == '$app'" &> /dev/null; then
			echo "$app is installed."
			break
		else
			echo -n "."
			sleep 1
			((timeout_count++))
			if [ $timeout_count -ge $max_timeout ]; then
				echo "Timeout reached: $app not installed after $max_timeout seconds."
				break
			fi
		fi
	done
done

# Check for dockutil

if [[ -e $application ]]; then
	echo "# $(date) | Dockutil wurde gefunden"
	for i in "${appToadd[@]}";do
		if [[ -e $i ]]; then
			echo "# $(date) | Die Applikation [$i] wird zum Dock hinzugefügt"
			sudo -u "$loggedInUser" $dockutil --add "$i" --no-restart "$UserPlist"
			
		fi
		
	done
else
	echo "# $(date) | Dockutil wurde nicht gefunden Vorgang wird abgebrochen"
	exit 1
fi

#Remove Bloatware from dock

sudo -u "$loggedInUser" $dockutil --remove "Musik"
sudo -u "$loggedInUser" $dockutil --remove "TV"
sudo -u "$loggedInUser" $dockutil --remove "Freeform"

sudo -u "$loggedInUser" $killall Dock

exit 0
