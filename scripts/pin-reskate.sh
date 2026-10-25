#!/bin/bash
# Replaces the installed ReSkate with one release and keeps it: the launcher is started with --no-update,
# and running the installer again keeps this version. For when the latest ReSkate is broken on Mac.
#
#   pin-reskate.sh            install ReSkate 2.0.3 (the last launcher whose window draws under D3DMetal)
#   pin-reskate.sh 2.0.3      install that version
#   pin-reskate.sh --latest   go back to the latest release and automatic updates

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"

version="2.0.3"
case "${1:-}" in
    "") ;;
    --latest) version="" ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) version="${1#v}" ;;
esac
if [ -n "$version" ] && ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "\"$1\" is not a ReSkate version." "Use a version like 2.0.3, or --latest."
fi

start_log pin-reskate
game="$(game_dir)"
[ -f "$game/Skate.exe" ] || fail "skate. is not installed in $game." "Run the installer first."
if pgrep -f 'ReSkateLauncher\.exe|Skate\.exe' >/dev/null 2>&1; then
    fail "skate. (ReSkate) is still running." "Quit it, then run this again."
fi

if [ -n "$version" ]; then
    url="https://github.com/Dingo-Shenanigans/ReSkate/releases/download/v$version"
    echo "${BOLD}Installing ReSkate $version and turning its automatic updates off${RESET}"
else
    url="https://github.com/Dingo-Shenanigans/ReSkate/releases/latest/download"
    echo "${BOLD}Installing the latest ReSkate and turning its automatic updates back on${RESET}"
fi

downloads="$BASE_DIR/downloads"
mkdir -p "$downloads" "$STATE_DIR"
rm -f "$downloads/launcher.json" # download() resumes partial files; this one must always be fresh
download "$url/launcher.json" "$downloads/launcher.json"
new_version="$(json_get "$downloads/launcher.json" launcher.version)"
skate_sha256="$(json_get "$downloads/launcher.json" game.skate_sha256)"
[ -n "$new_version" ] && [ -n "$skate_sha256" ] || fail "ReSkate ${version:-latest}'s launcher.json could not be read." \
    "Check that the version exists on https://github.com/Dingo-Shenanigans/ReSkate/releases"

# Record the choice first, so the installer follows it if the game needs a different build below.
if [ -n "$version" ]; then echo "$version" > "$RESKATE_PIN_FILE"; else rm -f "$RESKATE_PIN_FILE"; fi

if [ "$(sha256_of "$game/Skate.exe")" != "$skate_sha256" ]; then
    fail "ReSkate $new_version needs skate. build $(json_get "$downloads/launcher.json" game.build_id), and the installed game is a different build." \
        "Run the installer again: it now installs ReSkate $new_version and downloads only the game files that changed."
fi

for file in ReSkateLauncher.exe ReSkate.dll; do
    key=launcher; [ "$file" = ReSkate.dll ] && key=runtime
    download "$url/$file" "$downloads/$file" "$(json_get "$downloads/launcher.json" "$key.sha256")"
    mv -f "$downloads/$file" "$game/$file"
    ok "$file $new_version installed"
done
cp "$downloads/launcher.json" "$STATE_DIR/launcher.json"

# The app runs the scripts in bin/; give it the launch.sh that passes --no-update.
if [ -d "$BASE_DIR/bin" ] && [ "$HERE" != "$BASE_DIR/bin" ]; then
    cp "$HERE/common.sh" "$HERE/launch.sh" "$HERE/diagnose.sh" "$HERE/uninstall.sh" "$HERE/pin-reskate.sh" "$BASE_DIR/bin/"
    chmod +x "$BASE_DIR/bin/"*.sh
fi

echo
if [ -n "$version" ]; then
    ok "ReSkate $new_version is installed and will stay until you run: pin-reskate.sh --latest"
else
    ok "ReSkate $new_version is installed; updates are back on."
fi
