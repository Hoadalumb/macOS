#!/bin/bash

# Check if Microsoft Company Portal app is open
company_portal_pid=$(pgrep -f "Company Portal")

if [ -n "$company_portal_pid" ]; then
# Close Microsoft Company Portal app
kill "$company_portal_pid"
echo "Closed Microsoft Company Portal app."
fi
  # Update Microsoft applications using msupdate
  /Library/Application\ Support/Microsoft/MAU2.0/Microsoft\ AutoUpdate.app/Contents/MacOS/msupdate --install --apps only