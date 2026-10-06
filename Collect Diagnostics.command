#!/bin/bash
# Double-click to run. Opens Terminal and runs scripts/diagnose.sh; see README.md.
cd "$(dirname "$0")" || exit 1
bash "scripts/diagnose.sh" "$@"
status=$?
echo
read -r -p "Press Enter to close this window... " _
exit $status
