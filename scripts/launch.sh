#!/bin/bash
# Starts ReSkate's launcher (and from it, skate.) in the ReSkate for Mac Windows environment.
# "skate. (ReSkate).app" runs this. Every session is logged to ~/Library/Logs/ReSkate for Mac/game-<date>.log.
#
#   launch.sh            normal start
#   launch.sh --debug    log Wine's errors, warnings and loaded DLLs too (for bug reports)
#   launch.sh --hud      show Apple's Metal performance HUD (frame rate, GPU time)
#   launch.sh --online   start without ReSkate's --offline flag (needs Windows Steam in the environment)

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"

reskate_args=(--offline)
for arg in "$@"; do
    case "$arg" in
        --debug) export RESKATEM_DEBUG=1 ;;
        --hud) export MTL_HUD_ENABLED=1 ;;
        --online) reskate_args=() ;;
    esac
done

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/game-$(date '+%Y%m%d-%H%M%S').log"
# Keep the 20 newest game logs.
ls -1t "$LOG_DIR"/game-*.log 2>/dev/null | tail -n +21 | while read -r old; do rm -f "$old"; done

game="$(game_dir)"
alert() { # alert "message": a macOS dialog, since the app has no terminal
    osascript -e "display dialog \"$1\" buttons {\"Open Log\", \"OK\"} default button \"OK\" with title \"skate. (ReSkate)\" with icon caution" \
        -e 'if button returned of result is "Open Log" then do shell script "open -R " & quoted form of "'"$LOG_FILE"'"' >/dev/null 2>&1 || true
}

{
    echo "== skate. (ReSkate) on $(date '+%Y-%m-%d %H:%M:%S')"
    echo "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"
    echo "Game: $game"
    echo "Engine: Game Porting Toolkit $ENGINE_VERSION ($WINE_BIN)"
    echo "Arguments: ${reskate_args[*]:-}"
} > "$LOG_FILE"

[ -x "$WINE_BIN/wine64" ] || { alert "The compatibility layer is missing. Run the ReSkate for Mac installer again."; exit 1; }
[ -f "$game/ReSkateLauncher.exe" ] || { alert "ReSkate is not installed in $game. Run the ReSkate for Mac installer again."; exit 1; }
arch -x86_64 /usr/bin/true 2>/dev/null || { alert "Rosetta 2 is missing. Run the ReSkate for Mac installer again; it installs it."; exit 1; }

cd "$game" || exit 1
wine_env
started=$(date +%s)
"$WINE_BIN/wine64" "$game/ReSkateLauncher.exe" "${reskate_args[@]}" >> "$LOG_FILE" 2>&1
status=$?
wineserver_wait
elapsed=$(( $(date +%s) - started ))
echo "== exited with status $status after ${elapsed}s" >> "$LOG_FILE"

# A quick non-zero exit means it never really started; say so instead of failing silently.
if [ "$status" -ne 0 ] && [ "$elapsed" -lt 30 ]; then
    alert "skate. (ReSkate) stopped right after starting (status $status). Open the log for details, or run Collect Diagnostics and share the zip when asking for help."
fi
exit "$status"
