#!/bin/bash
# Starts Windows Steam in the ReSkate for Mac Windows environment, with the fix that lets its browser run
# (see steam_cef_fix in common.sh), and re-applies that fix whenever a Steam update replaces libcef.dll.
# Runs until Steam quits. Logged to ~/Library/Logs/ReSkate for Mac/steam-<date>.log.
#
#   steam.sh           start Steam (if it is not already running) and keep the fix applied
#   steam.sh --fix     only apply the fix once and exit

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"

steam_installed || { echo "Windows Steam is not installed in $PREFIX_DIR." >&2; exit 1; }
[ -f "$CEF_SHIM" ] || { echo "$CEF_SHIM is missing. Run the ReSkate for Mac installer again." >&2; exit 1; }

if [ "${1:-}" = --fix ]; then
    steam_cef_fix
    exit $?
fi

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/steam-$(date '+%Y%m%d-%H%M%S').log"
ls -1t "$LOG_DIR"/steam-*.log 2>/dev/null | tail -n +11 | while read -r old; do rm -f "$old"; done
log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG_FILE"; }

steam_running() { pgrep -if 'Steam\\steam\.exe' >/dev/null; }
# Changes whenever any browser folder's libcef.dll is replaced.
cef_signature() { stat -f '%i:%m' "$STEAM_DIR"/bin/cef/cef.*/libcef.dll 2>/dev/null | tr '\n' ' '; }

log "Steam in $PREFIX_DIR"
steam_cef_fix >> "$LOG_FILE" 2>&1 || log "Could not apply the Steam browser fix"
if ! steam_running; then
    log "Starting Steam"
    wine_env
    "$WINE_BIN/wine64" "C:\\Program Files (x86)\\Steam\\steam.exe" >> "$LOG_FILE" 2>&1 &
fi

# Steam restarts itself after updating, so allow a gap of up to a minute before deciding it has quit.
last_seen=$(date +%s)
signature="$(cef_signature)"
while [ $(( $(date +%s) - last_seen )) -lt 60 ]; do
    sleep 3
    steam_running && last_seen=$(date +%s)
    now="$(cef_signature)"
    if [ "$now" != "$signature" ]; then
        log "Steam replaced its browser files; re-applying the fix"
        steam_cef_fix >> "$LOG_FILE" 2>&1 || log "Could not apply the Steam browser fix"
        signature="$(cef_signature)"
    fi
done
log "Steam has quit"
