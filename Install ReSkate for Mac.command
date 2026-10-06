#!/bin/bash
# Double-click to run. Opens Terminal and runs scripts/install.sh; see README.md.
cd "$(dirname "$0")" || exit 1
bash "scripts/install.sh" "$@"
status=$?
echo
read -r -p "Press Enter to close this window... " _
exit $status
