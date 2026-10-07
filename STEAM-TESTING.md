# Steam testing branch

This branch is working toward **online play** for ReSkate on Mac: running the Windows Steam client in the
same Windows environment as the game, so ReSkate can sign you in with your own account instead of starting
offline.

**It is experimental.** Windows Steam now starts and its window works, but nobody has played online
through it yet. If you just want to play, use the `master` branch and the normal install in the
[README](README.md).

## What works so far

| Step | Status |
|---|---|
| Windows Steam installs and updates itself in the game's Windows environment | Works |
| Steam's window (its built-in browser) loads instead of crashing | **Works with the fix on this branch** |
| The fix is re-applied automatically after Steam updates | Works |
| Signing in to Steam | Not tested yet |
| ReSkate seeing a signed-in Steam and starting online | Not tested yet |
| EA's anti-cheat allowing the game online under Wine | **Unknown, and the biggest risk** |

### The problem this branch fixes

Steam draws its whole window with a built-in browser, `steamwebhelper` (Chromium 126). Under the Wine
in Apple's Game Porting Toolkit (Wine 7.7), it crashed about a second after starting, over and over, so
Steam never showed a window.

The cause was a missing Windows 10 function: Chromium loads `QueryUnbiasedInterruptTimePrecise` from
`api-ms-win-core-realtime-l1-1-1.dll` when it first needs it. Wine 7.7 does not have that function, and
Chromium deliberately crashes when a function it loads that way is missing. (Adding launch flags such as
`--in-process-gpu --disable-gpu` does not help: Steam already passes those.)

The fix, in `steam_cef_fix` in `scripts/common.sh`:

1. Wine handles every `api-ms-*` name itself, so a replacement DLL by that name would be ignored. Instead,
   the one place in Steam's `libcef.dll` that names that DLL is changed to `xpi-ms-win-core-realtime-l1-1-1.dll`
   (same length, so nothing else in the file moves).
2. A tiny DLL by that name goes beside it,
   [`scripts/steam/xpi-ms-win-core-realtime-l1-1-1.dll`](scripts/steam/xpi-ms-win-core-realtime-l1-1-1.dll). It
   contains no code: each function only forwards to one Wine already has. `QueryUnbiasedInterruptTimePrecise`
   goes to `QueryUnbiasedInterruptTime`, which takes the same argument and returns the same units.
   [`tools/make-forwarder-dll.py`](tools/make-forwarder-dll.py) builds it, so you can rebuild it and compare
   instead of trusting a binary.

Steam updates replace `libcef.dll`, so [`scripts/steam.sh`](scripts/steam.sh) applies the fix before starting
Steam and keeps checking while Steam runs, re-applying it within a few seconds of an update.

## Future plans

Roughly in order:

1. **Test online for real.** Sign in to Steam, start skate. through ReSkate with Steam running, and see
   whether EA's anti-cheat lets it through. If it does not, online is blocked no matter what happens with
   Steam, and this branch stops here.
2. **Install Steam from the installer**, as an optional step, so nobody has to do the manual steps below.
3. **Make online a choice in the app**, for example an "Online (Steam)" option, instead of a Terminal flag.
4. **Look at a newer Wine.** Newer Wine versions have the missing function, which would make the
   `libcef.dll` change unnecessary. Moving the game to a different engine is a big change and needs its own
   round of testing, so it comes after the steps above.

## Testing it

**Read this first.** This connects your Steam and EA accounts to the real online services from a Wine setup
that the game's anti-cheat may consider suspicious. There is some risk of your account being flagged. Only
test with an account you are willing to risk, and **never go online with mods installed**: move the `Mods`
folder out of your game folder before testing.

You need a working install from the normal [README](README.md) first.

**1. Install this branch's scripts.** This runs the installer from this branch; it keeps your game files, so
nothing big is downloaded again.

```sh
curl -fsSL https://raw.githubusercontent.com/ValveTextureFile/reskatem/steam-testing/get.sh | RESKATEM_BRANCH=steam-testing bash
```

**2. Install Windows Steam into the game's Windows environment** (once):

```sh
cd ~/Downloads
curl -fLO https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe
WINEPREFIX="$HOME/Library/Application Support/ReSkate for Mac/prefix" \
  "$HOME/Library/Application Support/ReSkate for Mac/engine/Game Porting Toolkit.app/Contents/Resources/wine/bin/wine64" SteamSetup.exe /S
```

**3. Start Steam with the fix.** Leave this Terminal window open while you use Steam; it keeps the fix
applied and finishes on its own a minute after Steam quits.

```sh
"$HOME/Library/Application Support/ReSkate for Mac/bin/steam.sh"
```

The first start downloads Steam's updates (a few hundred MB) and restarts Steam more than once; give it a
few minutes. If no window appears after that, quit Steam and run the line again. Then sign in; the QR code
option works with the Steam app on your phone.

**4. Start the game with Steam**, in a second Terminal window (⌘-N):

```sh
"$HOME/Library/Application Support/ReSkate for Mac/bin/launch.sh" --online
```

The ReSkate launcher shows whether it sees a signed-in Steam. Press **PLAY**.

### What to report

Whatever happens, tell us how far you got, for example in a GitHub issue:

- Did Steam's window appear? Could you sign in?
- Did the ReSkate launcher show you as signed in?
- Did the game start? Did it get online, or did anti-cheat or the game show an error? (A screenshot of
  any error helps a lot.)
- Your Mac (chip, memory) and macOS version.

Then double-click **Collect Diagnostics.command** and attach the zip it puts on your Desktop. On this branch
it includes the Steam logs. It replaces your macOS account name with `<you>` and contains no game files or
logins.

### Undoing it

To remove Windows Steam, quit it and delete
`~/Library/Application Support/ReSkate for Mac/prefix/drive_c/Program Files (x86)/Steam`. To go back to the
normal scripts, run the normal install line from the README again.

## Contributing

Help is welcome, especially:

- **Online and anti-cheat results**, good or bad, from different Macs.
- **The installer step for Steam** (plan 2). It should follow the existing installer: pinned downloads,
  checked hashes, plain explanations, and the ability to run again and pick up where it stopped.
- **Investigating a newer Wine** (plan 4) and what it changes for the game itself.

Ground rules:

- Scripts are written for the **bash 3.2 that ships with macOS**: no associative arrays, no `${var,,}`, and
  use `${arr[@]+"${arr[@]}"}` for arrays that may be empty under `set -u`.
- Use only what macOS includes (bash, perl, plutil, curl). Python is not guaranteed for everyone; the
  Python tool here is only for rebuilding the DLL.
- **Do not copy code or binaries from projects under incompatible licences** (for example AGPL projects)
  into this repository. Ideas are fine; write your own version.
- Never include or redistribute game files, Steam files, or anyone's login. Everything must be downloaded
  by the user with their own account.
- Test with `RESKATEM_PREFIX` pointing at a copy of the Windows environment when you try something risky,
  so your working setup stays untouched:

  ```sh
  cp -cR "$HOME/Library/Application Support/ReSkate for Mac/prefix" "$HOME/Library/Application Support/ReSkate for Mac/prefix-test"
  RESKATEM_PREFIX="$HOME/Library/Application Support/ReSkate for Mac/prefix-test" scripts/steam.sh
  ```
