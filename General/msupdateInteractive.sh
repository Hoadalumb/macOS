#!/bin/bash

# Check if Microsoft Company Portal app is open
company_portal_pid=$(pgrep -f "Company Portal")

if [ -n "$company_portal_pid" ]; then
# Close Microsoft Company Portal app
dialog --title "Microsoft Update" --message "Please close all opened Microsoft Apps" --bannerimage /Users/juergen.miedl/OneDrive\ -\ anyplace\ IT\ GmbH/anyplace\ IT-Logos/anyplace\ IT\ Logo_weiss_1.png --button1text "Enter to Continue"
kill "$company_portal_pid"
echo "Closed Microsoft Company Portal app."
fi
  # Update Microsoft applications using msupdate
  /Library/Application\ Support/Microsoft/MAU2.0/Microsoft\ AutoUpdate.app/Contents/MacOS/msupdate --install --apps only