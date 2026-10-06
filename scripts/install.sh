#!/bin/bash
# ReSkate for Mac installer: everything needed to play skate. with ReSkate on an Apple Silicon Mac.
#
#   install.sh                      full install (downloads the game, about 14 GB)
#   install.sh --game-dir DIR       use a skate. folder you already have (the one with Skate.exe)
#   install.sh --check              only check whether this Mac can run it, change nothing
#   install.sh --yes                answer yes to every question (still asks you to scan the Steam QR code)
#
# Every step says what it is doing, and everything shown is also saved to
# ~/Library/Logs/ReSkate for Mac/install-<date>.log. Running it again repairs or updates an install:
# finished steps are checked and skipped.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"

check_only=0
custom_game_dir=""
while [ $# -gt 0 ]; do
    case "$1" in
        --game-dir) custom_game_dir="${2:-}"; [ -n "$custom_game_dir" ] || fail "--game-dir needs a folder."; shift 2 ;;
        --check) check_only=1; shift ;;
        --yes|-y) RESKATEM_YES=1; shift ;;
        --debug) RESKATEM_DEBUG=1; shift ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) fail "Unknown option: $1" "Run with --help to see the options." ;;
    esac
done
export RESKATEM_YES="${RESKATEM_YES:-0}" RESKATEM_DEBUG="${RESKATEM_DEBUG:-0}"

start_log install
STEP_TOTAL=8
[ "$check_only" = 1 ] && STEP_TOTAL=1

cat <<EOF

${BOLD}$PRODUCT${RESET}
Plays skate. on your Mac through ReSkate (offline play, mods), using Apple's Game Porting
Toolkit and Wine. Free; no CrossOver needed.

This installer will:
  1. check that this Mac can run it
  2. set up the Windows compatibility layer (Wine + Apple's D3DMetal, about 1 GB)
  3. create a Windows environment for the game
  4. install Microsoft's Visual C++ runtime into it
  5. download skate. from Steam with your own account (about 14 GB, free)
  6. install ReSkate
  7. add "skate. (ReSkate)" to your Applications folder
  8. check the result

ReSkate is a fan project, not made or endorsed by EA or Full Circle. skate. is EA's.
EOF
echo
info "Installer started $(date '+%Y-%m-%d %H:%M:%S'), macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n machdep.cpu.brand_string)"

# ---- 1. This Mac ------------------------------------------------------------------------------------------
step "Checking this Mac"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = 1 ]; then
    ok "Apple Silicon ($(sysctl -n machdep.cpu.brand_string))"
else
    fail "This is an Intel Mac. skate. needs an Apple Silicon Mac (M1 or newer)." \
        "There is no way around this: D3DMetal, which runs skate.'s DirectX 12 graphics, only exists for Apple Silicon."
fi
macos_version="$(sw_vers -productVersion)"
if [ "${macos_version%%.*}" -ge 14 ]; then
    ok "macOS $macos_version"
else
    fail "macOS $macos_version is too old." "Update to macOS 14 Sonoma or newer in System Settings > General > Software Update."
fi
memory_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
if [ "$memory_gb" -ge 16 ]; then ok "${memory_gb} GB memory"
else warn "${memory_gb} GB memory: 16 GB is recommended. The game may stutter; close other apps while playing."; fi

target_dir="${custom_game_dir:-$(game_dir)}"
needed_gb=3
if [ -n "$custom_game_dir" ]; then
    [ -d "$custom_game_dir" ] || fail "The folder $custom_game_dir does not exist." "Pass the folder that contains Skate.exe."
    [ -f "$custom_game_dir/Skate.exe" ] || fail "$custom_game_dir has no Skate.exe." "Pass the skate. folder itself (the one with Skate.exe and the Data folder)."
elif [ ! -f "$target_dir/Skate.exe" ]; then
    needed_gb=18
fi
available_gb="$(free_gb "$HOME")"
if [ "$available_gb" -ge "$needed_gb" ]; then
    ok "${available_gb} GB free disk space (about ${needed_gb} GB needed)"
else
    fail "Only ${available_gb} GB of disk space is free; about ${needed_gb} GB is needed." \
        "Free up space (System Settings > General > Storage), or, if you already have skate., run with --game-dir."
fi
if curl -fsI --connect-timeout 10 https://github.com >/dev/null 2>&1; then ok "Internet connection"
else fail "Cannot reach github.com." "Check your internet connection (and any VPN or firewall), then run the installer again."; fi
if arch -x86_64 /usr/bin/true 2>/dev/null; then
    ok "Rosetta 2 is installed"
    rosetta=1
else
    warn "Rosetta 2 is not installed (it runs Intel apps such as Windows games' Wine on Apple Silicon)."
    rosetta=0
fi

if [ "$check_only" = 1 ]; then
    echo
    ok "This Mac can run $PRODUCT. Run the installer without --check to install."
    exit 0
fi

echo
confirm "Install $PRODUCT now?" || { info "Nothing was changed."; exit 0; }

if [ "$rosetta" = 0 ]; then
    info "Installing Rosetta 2 (macOS may ask for your password)..."
    run /usr/sbin/softwareupdate --install-rosetta --agree-to-license ||
        fail "Rosetta 2 could not be installed." "Install it by running:  softwareupdate --install-rosetta --agree-to-license"
    arch -x86_64 /usr/bin/true || fail "Rosetta 2 still does not run." "Restart your Mac and run the installer again."
    ok "Rosetta 2 installed"
fi

mkdir -p "$ENGINE_DIR" "$PREFIX_DIR" "$TOOLS_DIR" "$STATE_DIR" 2>/dev/null ||
    fail "Cannot create $BASE_DIR." "Check that your home folder is writable (Finder > Get Info on it)."
downloads="$BASE_DIR/downloads"
mkdir -p "$downloads"

# ---- 2. Wine + D3DMetal ----------------------------------------------------------------------------------
step "Windows compatibility layer (Wine + Apple D3DMetal, Game Porting Toolkit $ENGINE_VERSION)"
engine_marker="$STATE_DIR/engine-$ENGINE_VERSION"
if [ -f "$engine_marker" ] && [ -x "$WINE_BIN/wine64" ]; then
    ok "Already installed"
else
    download "$ENGINE_URL" "$downloads/engine.tar.xz" "$ENGINE_SHA256"
    info "Unpacking (about 1 GB)..."
    rm -rf "$ENGINE_DIR"; mkdir -p "$ENGINE_DIR"
    run tar -xJf "$downloads/engine.tar.xz" -C "$ENGINE_DIR"
    # Files fetched by curl carry no quarantine flag, but clear it in case the folder was copied from a download.
    xattr -dr com.apple.quarantine "$ENGINE_DIR" 2>/dev/null || true
    [ -x "$WINE_BIN/wine64" ] || fail "The compatibility layer did not unpack as expected ($WINE_BIN/wine64 is missing)." \
        "Run the installer again; if it happens twice, report it with the diagnostics zip."
    rm -f "$downloads/engine.tar.xz"
    touch "$engine_marker"
    ok "Installed in $ENGINE_DIR"
fi
info "Wine reports: $("$WINE_BIN/wine64" --version 2>&1 | head -1)"

# ---- 3. Windows environment -----------------------------------------------------------------------------
step "Windows environment"
if [ -f "$STATE_DIR/prefix-ready" ] && [ -d "$PREFIX_DIR/drive_c/windows" ]; then
    ok "Already set up in $PREFIX_DIR"
else
    info "Creating it (the first time takes a minute or two)..."
    wine_env
    run "$WINE_BIN/wine64" wineboot --init || fail "Wine could not create the Windows environment." \
        "Run the installer again with --debug and send the diagnostics zip."
    wineserver_wait
    info "Setting it to Windows 10..."
    run "$WINE_BIN/wine64" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuild /t REG_SZ /d 19045 /f >/dev/null
    run "$WINE_BIN/wine64" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v CurrentBuildNumber /t REG_SZ /d 19045 /f >/dev/null
    run "$WINE_BIN/wine64" reg add 'HKLM\Software\Microsoft\Windows NT\CurrentVersion' /v ProductName /t REG_SZ /d "Windows 10 Pro" /f >/dev/null
    run "$WINE_BIN/wine64" winecfg -v win10
    wineserver_wait
    [ -d "$PREFIX_DIR/drive_c/windows" ] || fail "The Windows environment was not created." "Run the installer again with --debug."
    touch "$STATE_DIR/prefix-ready"
    ok "Created in $PREFIX_DIR"
fi

# ---- 4. Visual C++ runtime ---------------------------------------------------------------------------------
step "Microsoft Visual C++ 2015-2022 runtime"
if [ -f "$STATE_DIR/vcredist" ]; then
    ok "Already installed"
else
    download "$VCREDIST_URL" "$downloads/vc_redist.x64.exe"
    info "Installing (silently, about a minute)..."
    wine_env
    run "$WINE_BIN/wine64" "$downloads/vc_redist.x64.exe" /install /quiet /norestart || true
    wineserver_wait
    if [ -f "$PREFIX_DIR/drive_c/windows/system32/msvcp140.dll" ]; then
        touch "$STATE_DIR/vcredist"
        rm -f "$downloads/vc_redist.x64.exe"
        ok "Installed"
    else
        fail "The Visual C++ runtime did not install." "Run the installer again with --debug and send the diagnostics zip."
    fi
fi

# ---- 5. The game ------------------------------------------------------------------------------------------------
step "skate. game files"
info "Reading which skate. build the latest ReSkate supports..."
download "$RESKATE_RELEASE_URL/launcher.json" "$downloads/launcher.json"
manifest_id="$(json_get "$downloads/launcher.json" game.manifest_id)"
build_id="$(json_get "$downloads/launcher.json" game.build_id)"
skate_sha256="$(json_get "$downloads/launcher.json" game.skate_sha256)"
reskate_version="$(json_get "$downloads/launcher.json" launcher.version)"
[ -n "$manifest_id" ] && [ -n "$skate_sha256" ] || fail "ReSkate's launcher.json could not be read." "Run the installer again; ReSkate's release page may have been updating."
info "ReSkate $reskate_version supports skate. build $build_id (manifest $manifest_id)."

game="$target_dir"
mkdir -p "$game"
if [ -f "$game/Skate.exe" ] && [ "$(sha256_of "$game/Skate.exe")" = "$skate_sha256" ]; then
    ok "Already present and the right build: $game"
else
    if [ -f "$game/Skate.exe" ]; then
        warn "The game in $game is a different build than ReSkate $reskate_version needs; updating it."
    fi
    if [ -n "$custom_game_dir" ]; then
        confirm "Download the supported build into $game (only changed files are fetched)?" ||
            fail "The game is not the build ReSkate needs." "Let the installer update it, or use a folder with build $build_id."
    fi
    cat <<EOF

  The game is downloaded from Steam with ${BOLD}your own Steam account${RESET}. Before continuing:

    1. Make sure skate. is in your Steam library. It is free: open the store page that is
       about to appear and click ${BOLD}Play Game${RESET} (or ${BOLD}Add to Library${RESET}). You do not need to install it there.
    2. Have the ${BOLD}Steam app on your phone${RESET} ready: a QR code will appear here. In the app, open
       the Steam Guard (shield) tab and tap ${BOLD}Scan a QR code${RESET}, then approve the sign-in.

  Your password is never typed here. The download is about 12 GB and resumes if interrupted.

EOF
    open "$STEAM_STORE_URL" 2>/dev/null || true
    wait_for_enter "Press Enter when skate. is in your Steam library and your phone is ready... "

    dd="$TOOLS_DIR/DepotDownloader"
    if [ ! -x "$dd" ] || [ "$(cat "$STATE_DIR/depotdownloader-version" 2>/dev/null)" != "$DEPOTDOWNLOADER_VERSION" ]; then
        download "$DEPOTDOWNLOADER_URL" "$downloads/DepotDownloader.zip" "$DEPOTDOWNLOADER_SHA256"
        run unzip -oq "$downloads/DepotDownloader.zip" -d "$TOOLS_DIR"
        chmod +x "$dd"
        echo "$DEPOTDOWNLOADER_VERSION" > "$STATE_DIR/depotdownloader-version"
        rm -f "$downloads/DepotDownloader.zip"
    fi
    info "Starting the download (DepotDownloader $DEPOTDOWNLOADER_VERSION). Scan the QR code below:"
    (cd "$TOOLS_DIR" && run "$dd" -app "$STEAM_APP_ID" -depot "$STEAM_DEPOT_ID" -manifest "$manifest_id" -os windows \
        -dir "$game" -qr -validate -max-downloads 16) || fail "The game download did not finish." \
        "If it said \"no subscription\" or \"access denied\", add skate. to your Steam library ($STEAM_STORE_URL) and run the installer again. Otherwise check your connection and run it again; it resumes."
    [ -f "$game/Skate.exe" ] || fail "The download finished but Skate.exe is missing." "Run the installer again; it re-checks every file."
    [ "$(sha256_of "$game/Skate.exe")" = "$skate_sha256" ] || fail "The downloaded Skate.exe is not the build ReSkate expects." \
        "Run the installer again. If it keeps happening, ReSkate may have just updated; report it with the diagnostics zip."
    ok "Downloaded build $build_id to $game"
fi
echo "$game" > "$GAME_DIR_FILE"

# ---- 6. ReSkate -------------------------------------------------------------------------------------------------
step "ReSkate $reskate_version"
for file in ReSkateLauncher.exe ReSkate.dll; do
    key=launcher; [ "$file" = ReSkate.dll ] && key=runtime
    expected="$(json_get "$downloads/launcher.json" "$key.sha256")"
    if [ -f "$game/$file" ] && [ "$(sha256_of "$game/$file")" = "$expected" ]; then
        ok "$file is up to date"
    else
        download "$RESKATE_RELEASE_URL/$file" "$downloads/$file" "$expected"
        mv -f "$downloads/$file" "$game/$file"
        ok "$file installed"
    fi
done
cp "$downloads/launcher.json" "$STATE_DIR/launcher.json"

# ---- 7. App ------------------------------------------------------------------------------------------------------
step "Adding \"skate. (ReSkate)\" to Applications"
mkdir -p "$BASE_DIR/bin"
cp "$HERE/common.sh" "$HERE/launch.sh" "$HERE/diagnose.sh" "$HERE/uninstall.sh" "$BASE_DIR/bin/"
chmod +x "$BASE_DIR/bin/"*.sh
mkdir -p "$HOME/Applications"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>skate-reskate</string>
    <key>CFBundleIdentifier</key><string>io.github.reskatem.skate</string>
    <key>CFBundleName</key><string>skate. (ReSkate)</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$reskate_version</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
cat > "$APP_PATH/Contents/MacOS/skate-reskate" <<'EOF'
#!/bin/bash
exec "$HOME/Library/Application Support/ReSkate for Mac/bin/launch.sh" "$@"
EOF
chmod +x "$APP_PATH/Contents/MacOS/skate-reskate"
# The engine's icon, until the project has its own.
icon="$ENGINE_DIR/Game Porting Toolkit.app/Contents/Resources/gptk.icns"
[ -f "$icon" ] && cp "$icon" "$APP_PATH/Contents/Resources/AppIcon.icns"
touch "$APP_PATH"
ok "$APP_PATH"

# ---- 8. Check ----------------------------------------------------------------------------------------------------
step "Final check"
problems=0
for f in "$WINE_BIN/wine64" "$PREFIX_DIR/drive_c/windows/system32/msvcp140.dll" "$game/Skate.exe" "$game/ReSkateLauncher.exe" "$game/ReSkate.dll" "$APP_PATH/Contents/MacOS/skate-reskate"; do
    if [ -e "$f" ]; then ok "$(basename "$f")"; else warn "Missing: $f"; problems=$((problems + 1)); fi
done
[ "$problems" = 0 ] || fail "$problems file(s) are missing." "Run the installer again; it repairs what is missing."
rm -rf "$downloads"

cat <<EOF

${BOLD}${GREEN}Done!${RESET} $PRODUCT is installed.

${BOLD}To play:${RESET} open ${BOLD}skate. (ReSkate)${RESET} from Applications (or Spotlight), then press ${BOLD}PLAY${RESET}.
  - The first start can show a black screen for a few minutes while graphics shaders are built.
  - It plays offline (no EA servers). Insert opens the ReSkate menu, ~ the console.
  - If it runs slowly, lower the graphics settings in the game.

${BOLD}If something goes wrong:${RESET} double-click ${BOLD}Collect Diagnostics.command${RESET} and share the zip it puts on your Desktop.
${BOLD}To update ReSkate:${RESET} run this installer again.
${BOLD}To remove everything:${RESET} double-click ${BOLD}Uninstall.command${RESET}.

EOF
