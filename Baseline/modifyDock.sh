#!/bin/bash

# Definierte Variablen für Script
application="/usr/local/bin/dockutil"
scriptname="addAppstoDock"
logfile="dockutil.log"
logdir="/Library/Logs/Microsoft/IntuneScripts/"
log="$HOME/$logfile"

# Funktion zur Erstellung Logverzeichnis
createlogdir() {
	if [[ -d $logdir ]]; then
		# Logverzeichnis existiert
		echo "# $(date) | Logverzeichnis $logdir existiert"
	else
		# Logverzeichnis existiert nicht
		echo "# $(date) | Logverzeichnis $logdir wird angelegt"
		mkdir -p "$logdir"
		echo "# $(date) | Logverzeichnis $logdir erfolgreich angelegt"
	fi
	
}

# Array der Programme die hinzugefügt werden sollen

dockapps=(
	"Microsoft Edge"
	"Microsoft Outlook"
	"Microsoft Teams"
	"Company Portal"
	"Privileges"
)

# Start Loging
createlogdir 
exec &> >(tee -a "$log")

# Start des Scripts
echo ""
echo "##############################################################"
echo "# $(date) | Starting $scriptname"
echo "##############################################################"
echo ""

# Überprüfung ob alle Apps installiert wurden
# Maximum number of timeouts (in seconds)
max_timeout=300 # 5 minutes

# Loop through the list of applications
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


#Überprufung ob Dockutil bereits installiert wurde
if [[ -e $application ]]; then
	echo "# $(date) | Dockutil wurde gefunden"
	for i in "${dockapps[@]}";do
		if [[ -e $i ]]; then
			echo "# $(date) | Die Applikation [$i] wird zum Dock hinzugefügt"
			dockutil --add "$i"
			
		fi
		
	done
else
	echo "# $(date) | Dockutil wurde nicht gefunden Vorgang wird abgebrochen"
	exit 1
fi
exit 0
