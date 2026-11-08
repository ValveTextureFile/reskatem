#!/bin/bash
# Collects what is needed to help someone whose ReSkate for Mac install does not work into one zip on the
# Desktop: system details, what is installed and whether it checks out, and the recent logs.
# It does not include game files, your Steam login, or anything else from your home folder.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"

stamp_now="$(date '+%Y%m%d-%H%M%S')"
work="$(mktemp -d)/ReSkate-for-Mac-diagnostics-$stamp_now"
mkdir -p "$work/logs"
report="$work/report.txt"
game="$(game_dir)"

section() { printf '\n== %s\n' "$1" >> "$report"; }
line() { printf '%s\n' "$*" >> "$report"; }
check_file() { # check_file LABEL PATH [EXPECTED_SHA256]
    if [ -e "$2" ]; then
        if [ -n "${3:-}" ]; then
            if [ "$(sha256_of "$2")" = "$3" ]; then line "OK       $1"; else line "MISMATCH $1 ($2 is not the expected build)"; fi
        else line "OK       $1"; fi
    else line "MISSING  $1 ($2)"; fi
}

echo "Collecting diagnostics..."
line "ReSkate for Mac diagnostics, $(date '+%Y-%m-%d %H:%M:%S')"

section "System"
line "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
line "Model: $(sysctl -n hw.model), CPU: $(sysctl -n machdep.cpu.brand_string), memory: $(memory_gb) GB"
if low_memory_mode; then line "Low-memory mode: on"; else line "Low-memory mode: off"; fi
line "Memory now: $(memory_pressure -Q 2>/dev/null | awk -F': ' '/percentage/ {print $2}') free, swap: $(sysctl -n vm.swapusage)"
line "Apple Silicon: $(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)"
if arch -x86_64 /usr/bin/true 2>/dev/null; then line "Rosetta 2: installed"; else line "Rosetta 2: NOT installed"; fi
line "Free disk space: $(free_gb "$HOME") GB"
system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Chipset Model|Total Number of Cores|Metal' | sed 's/^ */GPU: /' >> "$report"

section "Installed components"
line "Install folder: $BASE_DIR"
check_file "Wine + D3DMetal (Game Porting Toolkit $ENGINE_VERSION)" "$WINE_BIN/wine64"
check_file "D3DMetal" "$WINE_BIN/../lib/external/D3DMetal.framework/D3DMetal"
[ -x "$WINE_BIN/wine64" ] && line "         $("$WINE_BIN/wine64" --version 2>&1 | head -1)"
check_file "Windows environment" "$PREFIX_DIR/drive_c/windows"
check_file "Visual C++ runtime" "$PREFIX_DIR/drive_c/windows/system32/msvcp140.dll"
line "Game folder: $game"
pinned="$STATE_DIR/launcher.json"
# check_reskate LABEL FILE KEY: ReSkate updates itself, so a file whose version differs from the one the
# installer set up is an update, not a bad file; only the same version with other contents is a mismatch.
check_reskate() {
    local installed expected
    installed="$(pe_version "$2")"
    expected="$(json_get "$pinned" "$3.version")"
    if [ -e "$2" ] && [ -n "$installed" ] && [ "$installed" != "$expected" ]; then
        line "UPDATED  $1 $installed (the installer set up $expected; ReSkate updated itself)"
    else
        check_file "$1${installed:+ $installed}" "$2" "$(json_get "$pinned" "$3.sha256")"
    fi
}
if [ -f "$pinned" ]; then
    line "ReSkate: $(pe_version "$game/ReSkate.dll" || true) installed; the installer set up $(json_get "$pinned" launcher.version), for skate. build $(json_get "$pinned" game.build_id)"
    check_file "Skate.exe (supported build)" "$game/Skate.exe" "$(json_get "$pinned" game.skate_sha256)"
    check_reskate "ReSkateLauncher.exe" "$game/ReSkateLauncher.exe" launcher
    check_reskate "ReSkate.dll" "$game/ReSkate.dll" runtime
    cp "$pinned" "$work/launcher.json"
    [ -n "$RESKATE_PINNED" ] && line "         pinned to $RESKATE_PINNED with pin-reskate.sh (ReSkate updates off)"
else
    line "ReSkate: not recorded (the installer has not finished)"
    check_file "Skate.exe" "$game/Skate.exe"
fi
if [ -f "$game/msimg32.dll" ]; then
    line "OK       msimg32.dll stand-in (SHA-256 $(sha256_of "$game/msimg32.dll"))"
else
    line "MISSING  msimg32.dll stand-in ($game/msimg32.dll): game speed and BCrypt crash fixes are off"
fi
if [ -d "$game/Data" ]; then line "Game data: $(du -sh "$game/Data" 2>/dev/null | cut -f1)"; fi
check_file "App" "$APP_PATH/Contents/MacOS/skate-reskate"
if [ -d "$game/Mods" ]; then line "Mods: $(ls -1 "$game/Mods" 2>/dev/null | tr '\n' ' ')"; fi

section "Running processes"
# Only the game's own processes: Wine, its server, the launcher and Skate.exe.
ps -axo pid,etime,command | grep -E '[w]ine64|[w]ineserver|[R]eSkateLauncher\.exe|[S]kate\.exe' | grep -v -- '-c ' | cut -c1-200 >> "$report" || line "(none)"

# The newest installer and game logs, ReSkate's own log from each of those game sessions (launch.sh keeps
# them as reskate-<date>.log), and its current log (the last start, which may have been only the launcher).
for pattern in install game reskate; do
    ls -1t "$LOG_DIR"/$pattern-*.log 2>/dev/null | head -3 | while read -r f; do cp "$f" "$work/logs/"; done
done
[ -f "$game/logs/ReSkate.log" ] && cp "$game/logs/ReSkate.log" "$work/logs/ReSkate.log"
if [ -d "$game/logs/crashes" ]; then
    find "$game/logs/crashes" -type f ! -name queue.lock 2>/dev/null | head -5 | while read -r f; do cp "$f" "$work/logs/"; done
fi
# Paths in the logs name your macOS account; replace it so the zip is safer to share.
user="$(id -un)"
find "$work" -type f \( -name '*.log' -o -name '*.txt' \) -exec sed -i '' "s|/Users/$user|/Users/<you>|g; s|\\\\Users\\\\$user|\\\\Users\\\\<you>|g" {} +

zip_path="$HOME/Desktop/ReSkate-for-Mac-diagnostics-$stamp_now.zip"
(cd "$(dirname "$work")" && zip -qr "$zip_path" "$(basename "$work")")
rm -rf "$(dirname "$work")"
echo
echo "Saved: $zip_path"
echo "It contains report.txt (system details and what is installed) and recent logs, with your macOS"
echo "account name replaced by <you>. Share it when asking for help."
open -R "$zip_path" 2>/dev/null || true
