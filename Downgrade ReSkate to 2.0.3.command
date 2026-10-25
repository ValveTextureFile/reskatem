#!/bin/bash
# Double-click to run. Opens Terminal and runs scripts/pin-reskate.sh; see README.md.
cd "$(dirname "$0")" || exit 1
bash "scripts/pin-reskate.sh" 2.0.3 "$@"
status=$?
echo
read -r -p "Press Enter to close this window... " _
exit $status
