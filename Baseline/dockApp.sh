#!/bin/bash

#Definierte Variablen für Script
application="/usr/local/bin/dockutil"
scriptname="addAppstoDock"
logfile="dockutil.log"
logdir="/Library/Logs/Microsoft/IntuneScripts/"
log="$HOME/$logfile"

#Funktion zur Erstellung Logverzeichnis
createlogdir() {
	if [[ -d $logdir ]]; then
		#Logverzeichnis existiert
		echo "# $(date) | Logverzeichnis $logdir existiert"
	else
		#Logverzeichnis existiert nicht
		echo "# $(date) | Logverzeichnis $logdir wird angelegt"
		mkdir -p "$logdir"
		echo "# $(date) | Logverzeichnis $logdir erfolgreich angelegt"
	fi
	
}

#Array der Programme die hinzugefügt werden sollen

dockapps=(
	"/Applications/Microsoft Edge.app"
	"/Applications/Microsoft Outlook.app/"
	"/Applications/Microsoft Teams.app/"
	"/Applications/Company Portal.app/"
	"/Applications/Privileges.app/"
)

#Start Loging
createlogdir 
exec &> >(tee -a "$log")

#Start des Scripts
echo ""
echo "##############################################################"
echo "# $(date) | Starting $scriptname"
echo "##############################################################"
echo ""

#Überprüfung ob alle Apps installiert wurden

echo "$(date) | Looking for required applications"
while [[ $ready -ne 1 ]]; do
missingappcount=0

for i in "${dockapps[@]}";do
	if [[ -a $i ]]; then
		echo "# $(date) | Applikation $i ist installiert"
	else
		let missingappcount=$missingappcount+1
	fi
done

echo "# $(date) | [$missingappcount] application missing"

	if [[ $missingappcount -eq 0 ]]; then
		ready=1
		echo "# $(date) | All apps found lets prepare the dock"
	else
		echo "# $(date) | Waiting for 10 Seconds"
		sleep 10
	fi
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
