#!/bin/bash
# ReSkate for Mac: shared settings and helpers for install.sh, launch.sh, uninstall.sh and diagnose.sh.
# Written for the bash 3.2 that ships with macOS (no associative arrays, no ${var,,}).
# shellcheck disable=SC2034  # the settings below are used by the scripts that source this file

# ---- What gets installed, pinned to exact files ---------------------------------------------------
# Wine + Apple's D3DMetal (DirectX 12 -> Metal), from Gcenx's binary build of Apple's Game Porting
# Toolkit. Apple's licence allows non-commercial redistribution of D3DMetal; this project is free.
ENGINE_VERSION="3.0-3"
ENGINE_URL="https://github.com/Gcenx/game-porting-toolkit/releases/download/Game-Porting-Toolkit-3.0-3/game-porting-toolkit-3.0-3.tar.xz"
ENGINE_SHA256="d377683937340f914823dbb2e1252b329cbf834ff58907d0293db8cebf0e392e"

# Downloads the game from Steam with your own account (the same tool and version ReSkate uses).
DEPOTDOWNLOADER_VERSION="3.4.0"
DEPOTDOWNLOADER_URL="https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-macos-arm64.zip"
DEPOTDOWNLOADER_SHA256="60e80c7c496f3f9a079cd3c62036b35d088c27bc0149baf38f009eb57a52f6a5"

# ReSkate itself: always the latest release. Its launcher.json pins the launcher's and runtime's
# SHA-256 and the exact skate. build it supports, so those are checked against it.
RESKATE_RELEASE_URL="https://github.com/Dingo-Shenanigans/ReSkate/releases/latest/download"
VCREDIST_URL="https://aka.ms/vs/17/release/vc_redist.x64.exe"

STEAM_APP_ID="3354750"     # skate. on Steam
STEAM_DEPOT_ID="3354751"   # its Windows game files
STEAM_STORE_URL="https://store.steampowered.com/app/3354750"

# ---- Where things go --------------------------------------------------------------------------------
PRODUCT="ReSkate for Mac"
BASE_DIR="$HOME/Library/Application Support/ReSkate for Mac"
ENGINE_DIR="$BASE_DIR/engine"
WINE_BIN="$ENGINE_DIR/Game Porting Toolkit.app/Contents/Resources/wine/bin"
PREFIX_DIR="${RESKATEM_PREFIX:-$BASE_DIR/prefix}"  # the Windows environment (WINEPREFIX)
TOOLS_DIR="$BASE_DIR/tools"
STATE_DIR="$BASE_DIR/state"                   # markers for finished steps and settings
DEFAULT_GAME_DIR="$BASE_DIR/game"
LOG_DIR="$HOME/Library/Logs/ReSkate for Mac"
APP_PATH="$HOME/Applications/skate. (ReSkate).app"
GAME_DIR_FILE="$STATE_DIR/game-dir"           # remembers where the game is

# ---- Output -------------------------------------------------------------------------------------------
if [ -t 1 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
STEP_NUMBER=0
STEP_TOTAL=0

stamp() { date '+%H:%M:%S'; }
step() {
    STEP_NUMBER=$((STEP_NUMBER + 1))
    printf '\n%s[%s/%s] %s%s\n' "$BOLD$BLUE" "$STEP_NUMBER" "$STEP_TOTAL" "$*" "$RESET"
}
info() { printf '%s  %s%s\n' "$DIM$(stamp)" "$RESET" "$*"; }
ok() { printf '%s  %s✓ %s%s\n' "$DIM$(stamp)" "$RESET$GREEN" "$*" "$RESET"; }
warn() { printf '%s  %s! %s%s\n' "$DIM$(stamp)" "$RESET$YELLOW" "$*" "$RESET"; }
# fail "what went wrong" "what to do about it"
fail() {
    printf '\n%s✗ %s%s\n' "$BOLD$RED" "$1" "$RESET" >&2
    [ -n "${2:-}" ] && printf '\n%sWhat to do:%s %s\n' "$BOLD" "$RESET" "$2" >&2
    if [ -n "${LOG_FILE:-}" ]; then
        printf '\nThe full log is at:\n  %s\n' "$LOG_FILE" >&2
        printf 'If you ask for help, run "Collect Diagnostics.command" and attach the zip it makes.\n' >&2
    fi
    exit 1
}
# Prints a command, then runs it; its output goes to the screen and the log.
run() {
    printf '%s  $ %s%s\n' "$DIM" "$*" "$RESET"
    "$@"
}
# Asks a yes/no question; RESKATEM_YES=1 answers yes.
confirm() {
    if [ "${RESKATEM_YES:-0}" = 1 ]; then return 0; fi
    local answer
    printf '%s%s [y/N] %s' "$BOLD" "$1" "$RESET"
    read -r answer </dev/tty || return 1
    case "$answer" in [yY]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}
wait_for_enter() {
    if [ "${RESKATEM_YES:-0}" = 1 ]; then return 0; fi
    printf '%s%s%s' "$BOLD" "${1:-Press Enter to continue...}" "$RESET"
    read -r _ </dev/tty || true
}

# Starts a log in LOG_DIR named after $1 and copies everything printed into it.
start_log() {
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/$1-$(date '+%Y%m%d-%H%M%S').log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    info "Log: $LOG_FILE"
}

# ---- Files ----------------------------------------------------------------------------------------------
sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# download URL FILE [SHA256]: retries, resumes, and refuses a file whose hash does not match.
download() {
    local url="$1" file="$2" expected="${3:-}" attempt
    info "Downloading $(basename "$file")"
    info "  from $url"
    for attempt in 1 2 3 4 5; do
        if curl -fL --http1.1 --retry 3 --retry-delay 2 --connect-timeout 20 -C - --progress-bar -o "$file" "$url"; then
            break
        fi
        [ "$attempt" = 5 ] && fail "Could not download $(basename "$file") after 5 tries." \
            "Check your internet connection and run the installer again; it picks up where it stopped."
        warn "Download interrupted (try $attempt of 5); retrying in 5 seconds..."
        sleep 5
    done
    if [ -n "$expected" ]; then
        local actual
        actual="$(sha256_of "$file")"
        if [ "$actual" != "$expected" ]; then
            rm -f "$file"
            fail "$(basename "$file") is not the expected file (SHA-256 $actual, expected $expected)." \
                "Run the installer again. If it keeps happening, the download source changed; please report it."
        fi
        ok "Verified $(basename "$file") (SHA-256 matches)"
    fi
}

# Reads a value from a JSON file with plutil (part of macOS, no extra tools): json_get FILE key.path
json_get() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

free_gb() { df -g "$1" | awk 'NR==2 {print $4}'; }

game_dir() {
    if [ -f "$GAME_DIR_FILE" ]; then cat "$GAME_DIR_FILE"; else echo "$DEFAULT_GAME_DIR"; fi
}

# ---- Wine ----------------------------------------------------------------------------------------------
# The environment the game runs in. ROSETTA_ADVERTISE_AVX lets x86 games that require AVX run under
# Rosetta (macOS 15+). WINEDEBUG=-all keeps Wine quiet unless RESKATEM_DEBUG=1.
# atiadlxx=d: D3DMetal presents the GPU as an AMD Radeon, and Wine's stand-in AMD driver library reports
# version 22.20.19.16, so skate. refuses to start ("Please update your AMD Radeon driver") and then calls
# an ADL function the stand-in lacks. Without the library the game skips its AMD driver checks.
wine_env() {
    export WINEPREFIX="$PREFIX_DIR"
    export WINEESYNC=1
    export ROSETTA_ADVERTISE_AVX=1
    export WINEDLLOVERRIDES="atiadlxx=d"
    if [ "${RESKATEM_DEBUG:-0}" = 1 ]; then export WINEDEBUG="+err,+warn,+loaddll"; else export WINEDEBUG="-all"; fi
}
wine() { wine_env; "$WINE_BIN/wine64" "$@"; }

# ---- Windows Steam -----------------------------------------------------------------------------------------
# Steam's browser (steamwebhelper, Chromium 126) delay-loads QueryUnbiasedInterruptTimePrecise from
# api-ms-win-core-realtime-l1-1-1.dll. This Wine (7.7) lacks it, so the browser crashes on start and Steam never
# shows its window. Wine resolves api-ms-* names internally, so libcef.dll is pointed at a same-length name
# (xpi-...) and a forwarder DLL by that name is put beside it (built by tools/make-forwarder-dll.py).
# Steam updates replace libcef.dll, so steam_cef_fix runs before Steam starts and while it runs.
STEAM_DIR="$PREFIX_DIR/drive_c/Program Files (x86)/Steam"
CEF_SHIM_NAME="xpi-ms-win-core-realtime-l1-1-1.dll"
CEF_SHIM="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/steam/$CEF_SHIM_NAME"

steam_installed() { [ -f "$STEAM_DIR/steam.exe" ] || [ -f "$STEAM_DIR/Steam.exe" ]; }

# Fixes every 64-bit Steam browser folder; prints one line per folder it changed.
steam_cef_fix() {
    local dir lib
    for dir in "$STEAM_DIR"/bin/cef/cef.*; do
        lib="$dir/libcef.dll"
        [ -f "$lib" ] || continue
        file -b "$lib" | grep -q 'x86-64' || continue   # the shim is 64-bit; older 32-bit folders are unused
        if LC_ALL=C grep -q -a -F 'api-ms-win-core-realtime-l1-1-1.dll' "$lib"; then
            # Write a patched copy and swap it in, so a running browser keeps its old file.
            perl -0777 -pe 's/api-ms-win-core-realtime-l1-1-1\.dll\0/xpi-ms-win-core-realtime-l1-1-1.dll\0/g' \
                "$lib" > "$lib.reskatem" && mv -f "$lib.reskatem" "$lib" || { rm -f "$lib.reskatem"; return 1; }
            echo "Patched $(basename "$dir")/libcef.dll"
        fi
        if ! cmp -s "$CEF_SHIM" "$dir/$CEF_SHIM_NAME"; then
            cp "$CEF_SHIM" "$dir/$CEF_SHIM_NAME" || return 1
            echo "Added $CEF_SHIM_NAME to $(basename "$dir")"
        fi
    done
}
wineserver_wait() { wine_env; "$WINE_BIN/wineserver" -w 2>/dev/null || true; }
