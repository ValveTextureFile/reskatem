#!/bin/bash
# EXPERIMENTAL: sets up online play (Windows Steam signed in beside the game). See STEAM-TESTING.md.
#
#   online-setup.sh          set up (or repair) the online setup
#   online-setup.sh --yes    answer yes to every question
#
# Needs a working offline install first. It builds a separate setup in
# ~/Library/Application Support/ReSkate for Mac/online and leaves the offline one as it is. Logged to
# ~/Library/Logs/ReSkate for Mac/online-setup-<date>.log. Running it again skips finished steps.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"

for arg in "$@"; do
    case "$arg" in
        --yes|-y) RESKATEM_YES=1 ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) fail "Unknown option: $arg" "Run with --help to see the options." ;;
    esac
done
export RESKATEM_YES="${RESKATEM_YES:-0}"

start_log online-setup
STEP_TOTAL=5

cat <<EOF

${BOLD}$PRODUCT: online setup (experimental)${RESET}
Online play needs Windows Steam running and signed in beside the game. This sets up a second, separate
copy of the game's Windows environment on a newer Wine that Steam works on. Your offline setup stays as
it is, and the game files are shared (nothing is downloaded again).

This will:
  1. check that the offline install is there and that there is room (about 4 GB)
  2. download MetalSharp's Wine 11 runtime with Apple's D3DMetal (about 435 MB, 2.5 GB unpacked)
  3. copy the game's Windows environment
  4. install Windows Steam into the copy and let it update itself
  5. fix Steam's window for Wine (see STEAM-TESTING.md)

${YELLOW}Online play has not been tested much. Never go online with mods your account should not be seen with.${RESET}
EOF
echo
confirm "Continue?" || { echo "Nothing was changed."; exit 0; }

# ---- 1. Checks ---------------------------------------------------------------------------------------------
step "Checking the offline install"
[ -f "$STATE_DIR/prefix-ready" ] && [ -d "$PREFIX_DIR/drive_c/windows" ] ||
    fail "The offline install is not finished." "Run the normal installer first (see README.md), then this."
[ -f "$(game_dir)/ReSkateLauncher.exe" ] || fail "ReSkate is not installed in $(game_dir)." "Run the normal installer again first."
ok "Offline install found"
mkdir -p "$ONLINE_DIR" "$ONLINE_STATE_DIR"
if [ ! -f "$ONLINE_STATE_DIR/runtime" ] && [ "$(free_gb "$ONLINE_DIR")" -lt 4 ]; then
    fail "Not enough free disk space: $(free_gb "$ONLINE_DIR") GB free, about 4 GB needed." "Free some space and run this again."
fi

# ---- 2. Wine 11 + D3DMetal -----------------------------------------------------------------------------------
step "Wine 11 runtime with D3DMetal ($ONLINE_RUNTIME_VERSION)"
if [ -f "$ONLINE_STATE_DIR/runtime" ] && [ -x "$ONLINE_WINE_DIR/bin/wine" ]; then
    ok "Already installed"
else
    archive="$ONLINE_DIR/runtime.tar.zst"
    download "$ONLINE_RUNTIME_URL" "$archive" "$ONLINE_RUNTIME_SHA256"
    info "Unpacking (about 2.5 GB)..."
    rm -rf "$ONLINE_RUNTIME_DIR" "$ONLINE_DIR/unpack"; mkdir -p "$ONLINE_DIR/unpack"
    run tar -xf "$archive" -C "$ONLINE_DIR/unpack"
    mv "$ONLINE_DIR/unpack/runtime" "$ONLINE_RUNTIME_DIR" && rm -rf "$ONLINE_DIR/unpack" "$archive"
    xattr -dr com.apple.quarantine "$ONLINE_RUNTIME_DIR" 2>/dev/null || true
    [ -x "$ONLINE_WINE_DIR/bin/wine" ] || fail "The runtime did not unpack as expected ($ONLINE_WINE_DIR/bin/wine is missing)." \
        "Run this again; if it happens twice, report it with the diagnostics zip."

    # D3DMetal plugs into Wine as builtin DLLs whose Unix halves all point at libd3dshared.dylib, laid out
    # as in Game Porting Toolkit. The runtime ships it separately, so put it in place.
    d3dmetal="$ONLINE_RUNTIME_DIR/d3dmetal-gptk4-beta2"
    [ -d "$d3dmetal/external/D3DMetal.framework" ] || fail "The runtime has no D3DMetal ($d3dmetal)." \
        "The runtime download may have changed; please report it."
    info "Adding D3DMetal to Wine..."
    mkdir -p "$ONLINE_WINE_DIR/lib/external"
    cp -R "$d3dmetal/external/D3DMetal.framework" "$d3dmetal/external/libd3dshared.dylib" "$ONLINE_WINE_DIR/lib/external/"
    cp "$d3dmetal"/wine/x86_64-windows/*.dll "$ONLINE_WINE_DIR/lib/wine/x86_64-windows/"
    for unix_lib in "$d3dmetal"/wine/x86_64-unix/*.so; do
        ln -sf ../../external/libd3dshared.dylib "$ONLINE_WINE_DIR/lib/wine/x86_64-unix/$(basename "$unix_lib")"
    done
    touch "$ONLINE_STATE_DIR/runtime"
    ok "Installed in $ONLINE_RUNTIME_DIR"
fi
info "Wine reports: $("$ONLINE_WINE_DIR/bin/wine" --version 2>&1 | head -1)"

# ---- 3. Windows environment ------------------------------------------------------------------------------------
step "Copy of the game's Windows environment"
if [ -f "$ONLINE_STATE_DIR/prefix" ] && [ -d "$ONLINE_PREFIX_DIR/drive_c/windows" ]; then
    ok "Already set up in $ONLINE_PREFIX_DIR"
else
    if [ -x "$WINE_BIN/wineserver" ]; then wine_env; "$WINE_BIN/wineserver" -k 2>/dev/null || true; fi
    rm -rf "$ONLINE_PREFIX_DIR"
    # On APFS, -c makes a clone that shares unchanged data with the original, so it takes almost no space.
    run cp -cR "$PREFIX_DIR" "$ONLINE_PREFIX_DIR" || run cp -R "$PREFIX_DIR" "$ONLINE_PREFIX_DIR"
    info "Updating the copy for Wine 11 (a minute or two)..."
    online_wine wineboot --update >/dev/null 2>&1 || true
    online_wineserver_wait
    touch "$ONLINE_STATE_DIR/prefix"
    ok "Copied to $ONLINE_PREFIX_DIR"
fi

# ---- 4. Windows Steam ------------------------------------------------------------------------------------------
step "Windows Steam"
if steam_installed && [ -f "$ONLINE_STATE_DIR/steam" ]; then
    ok "Already installed"
else
    setup="$ONLINE_DIR/SteamSetup.exe"
    download "$STEAM_SETUP_URL" "$setup"
    info "Installing..."
    online_wine "$setup" /S >/dev/null 2>&1 || true
    online_wineserver_wait
    rm -f "$setup"
    steam_installed || fail "Steam did not install." "Run this again with RESKATEM_DEBUG=1 and send the diagnostics zip."

    # Steam's installer is small; the first start downloads the rest (a few hundred MB) and restarts Steam.
    info "Starting Steam once so it can update itself (a few minutes; its window may stay black for now)..."
    online_wine_env
    "$ONLINE_WINE_DIR/bin/wine" "C:\\Program Files (x86)\\Steam\\steam.exe" >/dev/null 2>&1 &
    html_log="$STEAM_DIR/logs/steamui_html.txt"
    for _ in $(seq 1 200); do
        sleep 3
        [ -f "$STEAM_DIR/bin/cef/cef.win64/steamwebhelper.exe" ] && grep -q BrowserReady "$html_log" 2>/dev/null && break
    done
    "$ONLINE_WINE_DIR/bin/wineserver" -k 2>/dev/null || true
    [ -f "$STEAM_DIR/bin/cef/cef.win64/steamwebhelper.exe" ] || fail "Steam did not finish updating." \
        "Check your internet connection and run this again."
    touch "$ONLINE_STATE_DIR/steam"
    ok "Installed and updated"
fi

# ---- 5. Steam's window ---------------------------------------------------------------------------------------------
step "Fixing Steam's window for Wine"
changes="$(steam_wrapper_fix)" || fail "Could not set up Steam's browser wrapper." "Run this again."
[ -n "$changes" ] && info "$changes"
touch "$ONLINE_STATE_DIR/ready"
ok "Ready"

cat <<EOF

${GREEN}${BOLD}Online setup is ready.${RESET}
Next:
  1. Start Steam and sign in (the QR code works with the Steam app on your phone):
       "$BASE_DIR/bin/steam.sh"
  2. In another Terminal window, start the game with Steam:
       "$BASE_DIR/bin/launch.sh" --online
     The ReSkate launcher shows your Steam account when it sees Steam. Press PLAY.
EOF
