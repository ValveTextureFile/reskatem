#!/bin/bash
# EXPERIMENTAL: starts Windows Steam in the online setup (made by online-setup.sh), with the wrapper that lets
# its window draw (see steam_wrapper_fix in common.sh), and puts the wrapper back whenever a Steam update
# replaces Steam's browser. Runs until Steam quits. Logged to ~/Library/Logs/ReSkate for Mac/steam-<date>.log.
#
#   steam.sh           start Steam (if it is not already running) and keep the wrapper in place
#   steam.sh --fix     only put the wrapper in place once and exit

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"

online_ready || { echo "The online setup is not ready. Run online-setup.sh first (see STEAM-TESTING.md)." >&2; exit 1; }
[ -f "$STEAM_WRAPPER" ] || { echo "$STEAM_WRAPPER is missing. Run the ReSkate for Mac installer again." >&2; exit 1; }

if [ "${1:-}" = --fix ]; then
    steam_wrapper_fix
    exit $?
fi

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/steam-$(date '+%Y%m%d-%H%M%S').log"
ls -1t "$LOG_DIR"/steam-*.log 2>/dev/null | tail -n +11 | while read -r old; do rm -f "$old"; done
log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG_FILE"; }

steam_running() { pgrep -if 'Steam\\steam\.exe' >/dev/null; }
# Changes whenever a Steam update replaces any browser folder's steamwebhelper.exe.
browser_signature() { stat -f '%i:%m' "$STEAM_DIR"/bin/cef/cef.*/steamwebhelper.exe 2>/dev/null | tr '\n' ' '; }

log "Steam in $ONLINE_PREFIX_DIR"
steam_wrapper_fix >> "$LOG_FILE" 2>&1 || log "Could not put the browser wrapper in place"
if ! steam_running; then
    log "Starting Steam"
    online_wine_env
    # -noverifyfiles: Steam would otherwise restore its own steamwebhelper.exe at every start.
    "$ONLINE_WINE_DIR/bin/wine" "C:\\Program Files (x86)\\Steam\\steam.exe" -noverifyfiles >> "$LOG_FILE" 2>&1 &
fi

# Steam restarts itself after updating, so allow a gap of up to a minute before deciding it has quit.
last_seen=$(date +%s)
signature="$(browser_signature)"
while [ $(( $(date +%s) - last_seen )) -lt 60 ]; do
    sleep 3
    steam_running && last_seen=$(date +%s)
    now="$(browser_signature)"
    if [ "$now" != "$signature" ]; then
        log "Steam replaced its browser; putting the wrapper back"
        steam_wrapper_fix >> "$LOG_FILE" 2>&1 || log "Could not put the browser wrapper in place"
        signature="$(browser_signature)"
    fi
done
log "Steam has quit"
