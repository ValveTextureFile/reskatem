#!/bin/bash
# Removes ReSkate for Mac: the app, the compatibility layer, the Windows environment and (if you agree)
# the game files and logs. It never touches anything outside its own folders.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"

game="$(game_dir)"
cat <<EOF

${BOLD}Uninstall $PRODUCT${RESET}

This removes:
  - the app:                  $APP_PATH
  - the compatibility layer, Windows environment and tools in:
                              $BASE_DIR
EOF
if [ "$game" != "$DEFAULT_GAME_DIR" ]; then
    echo "  (your own game folder $game is kept; only ReSkate's two files are removed from it)"
fi
echo
confirm "Uninstall?" || { echo "Nothing was removed."; exit 0; }

# Stop anything still running in the environment first.
if [ -x "$WINE_BIN/wineserver" ]; then wine_env; "$WINE_BIN/wineserver" -k 2>/dev/null || true; fi

if [ "$game" = "$DEFAULT_GAME_DIR" ] && [ -f "$game/Skate.exe" ]; then
    size="$(du -sh "$game" 2>/dev/null | cut -f1)"
    if ! confirm "Also delete the skate. game files ($size)? Say no to keep them for a later reinstall."; then
        kept="$HOME/skate. game files (kept by ReSkate for Mac uninstall)"
        mv "$game" "$kept" && echo "Game files moved to: $kept  (reinstall with: install.sh --game-dir \"$kept\")"
    fi
elif [ "$game" != "$DEFAULT_GAME_DIR" ]; then
    rm -f "$game/ReSkateLauncher.exe" "$game/ReSkate.dll" "$game/launcher.json"
fi

rm -rf "$APP_PATH" && echo "Removed the app."
rm -rf "$BASE_DIR" && echo "Removed $BASE_DIR."
if confirm "Delete the logs in $LOG_DIR too?"; then rm -rf "$LOG_DIR" && echo "Removed the logs."; fi
echo
echo "${GREEN}$PRODUCT is uninstalled.${RESET}"
echo "Rosetta 2 stays installed (other apps may use it). Your Steam account is not affected."
