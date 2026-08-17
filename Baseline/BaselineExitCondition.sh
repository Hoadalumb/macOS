#!/bin/bash
# FinalScript: mark Baseline enrollment complete
MARKER="/private/var/db/.baseline_enrollment_complete"

/usr/bin/touch "$MARKER"
/usr/sbin/chown root:wheel "$MARKER"
/bin/chmod 644 "$MARKER"

/usr/bin/logger "Baseline: enrollment marker written at $MARKER"
exit 0
