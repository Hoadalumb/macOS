#!/bin/bash

# Varibales for the script
logdir="/var/log/troubleshooting"
logfile="mdeschedulesscan.log"
log="$logdir/$logfile"
defenderStatus=$(mdatp health | grep healthy | awk '{print $NF}')

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

# Check if MDE is installed and running
if [ "$defenderStatus" = "true" ] ; then
  echo "# $(date) | Microsoft Defender is healthy."
else
  echo "# $(date) | Microsoft Defender is not healthy."
  exit 1
fi

# Schedule daily quick scan
echo "# $(date) | Set daily quickscan to 13:00 Uhr"
mdatp config scheduled-scan quick-scan time-of-day --value 780

# Schedule weekly full scan
echo "# $(date) ] Set weekly full scan to friday 13:00 Uhr"
mdatp config scheduled-scan weekly-scan --day-of-week 6 --time-of-day 780 -scan-type full
exit 0
