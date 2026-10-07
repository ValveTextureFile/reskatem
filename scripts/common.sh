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

wineserver_wait() { wine_env; "$WINE_BIN/wineserver" -w 2>/dev/null || true; }

# ---- Online (Windows Steam), experimental -------------------------------------------------------------------
# Online play needs Windows Steam signed in, in the same Windows environment as the game. Steam does not work
# on Game Porting Toolkit's Wine 7.7 (its browser crashes, and Wine 7.7 cannot tell Steam which program owns a
# local connection, so Steam rejects its own window). online-setup.sh therefore builds a second, separate setup:
# MetalSharp's Wine 11 runtime (which can host D3DMetal), the D3DMetal from Game Porting Toolkit 4 that the
# runtime ships, and a copy of the game's Windows environment with Windows Steam in it. The offline setup above
# is not changed. See STEAM-TESTING.md.
ONLINE_DIR="${RESKATEM_ONLINE_DIR:-$BASE_DIR/online}"
ONLINE_RUNTIME_VERSION="MetalSharp bundles, Wine 11.17"
ONLINE_RUNTIME_URL="https://github.com/metalsharp/MetalSharp/releases/download/bundles/metalsharp-runtime.tar.zst"
ONLINE_RUNTIME_SHA256="7c0ef15a528e3cafa3bdf7d88eac0849eefd84fbc692e19eb7cdcc134b7920c7"
ONLINE_RUNTIME_DIR="$ONLINE_DIR/runtime"                     # unpacked runtime (wine/, d3dmetal-gptk4-beta2/)
ONLINE_WINE_DIR="$ONLINE_RUNTIME_DIR/wine"
ONLINE_PREFIX_DIR="$ONLINE_DIR/prefix"                       # copy of PREFIX_DIR, plus Windows Steam
ONLINE_STATE_DIR="$ONLINE_DIR/state"                         # markers for finished online-setup steps
STEAM_SETUP_URL="https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe"
STEAM_DIR="$ONLINE_PREFIX_DIR/drive_c/Program Files (x86)/Steam"
STEAM_WRAPPER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/steam/steamwebhelper.exe"

online_ready() { [ -f "$ONLINE_STATE_DIR/ready" ] && [ -x "$ONLINE_WINE_DIR/bin/wine" ] && steam_installed; }
steam_installed() { [ -f "$STEAM_DIR/steam.exe" ] || [ -f "$STEAM_DIR/Steam.exe" ]; }

# The environment for the online setup. GnuTLS (HTTPS inside Wine) lives in the runtime's unix folder, so it
# must be on the library path; the D3DMetal DLLs are Wine builtins there; atiadlxx=d as for wine_env.
online_wine_env() {
    export WINEPREFIX="$ONLINE_PREFIX_DIR"
    export WINEESYNC=1
    export ROSETTA_ADVERTISE_AVX=1
    export DYLD_FALLBACK_LIBRARY_PATH="$ONLINE_WINE_DIR/lib/wine/x86_64-unix:$ONLINE_WINE_DIR/lib/external:$ONLINE_WINE_DIR/lib"
    export WINEDLLOVERRIDES="d3d10,d3d11,d3d12,dxgi,nvapi64,nvngx-on-metalfx=b;atiadlxx=d"
    if [ "${RESKATEM_DEBUG:-0}" = 1 ]; then export WINEDEBUG="+err,+warn,+loaddll"; else export WINEDEBUG="-all"; fi
}
online_wine() { online_wine_env; "$ONLINE_WINE_DIR/bin/wine" "$@"; }
online_wineserver_wait() { online_wine_env; "$ONLINE_WINE_DIR/bin/wineserver" -w 2>/dev/null || true; }

# Steam's window stays black on Wine 11 unless its browser runs with --in-process-gpu --disable-gpu, which
# Steam cannot be told to pass. Each 64-bit browser folder gets the wrapper (tools/steamwebhelper-wrapper.c)
# as steamwebhelper.exe, and Steam's own file becomes steamwebhelper.real.exe. Steam updates put their own
# file back, so this runs before Steam starts and while it runs (steam.sh). Prints one line per change.
steam_wrapper_fix() {
    local dir exe
    for dir in "$STEAM_DIR"/bin/cef/cef.*; do
        exe="$dir/steamwebhelper.exe"
        [ -f "$exe" ] || continue
        cmp -s "$STEAM_WRAPPER" "$exe" && continue
        file -b "$exe" | grep -q 'x86-64' || continue   # the wrapper is 64-bit; 32-bit folders are unused
        mv -f "$exe" "$dir/steamwebhelper.real.exe" && cp "$STEAM_WRAPPER" "$exe" || return 1
        echo "Wrapped $(basename "$dir")/steamwebhelper.exe"
    done
}
