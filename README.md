# ReSkate for Mac

> **You are on the `steam-testing` branch.** It is experimental work toward online play through Windows
> Steam; see [STEAM-TESTING.md](STEAM-TESTING.md). To just play, use the `master` branch.

Play **skate.** on an Apple Silicon Mac, offline and with mods, through
[ReSkate](https://github.com/Dingo-Shenanigans/ReSkate). Free (except for the game itself): no CrossOver or other paid software.

One installer sets up everything: Apple's Game Porting Toolkit (Wine and D3DMetal, which runs the game's
DirectX 12 graphics), a Windows environment, Microsoft's Visual C++ runtime, the game itself (downloaded from
Steam with your own free account) and ReSkate. You end up with a **skate. (ReSkate)** app in Applications.

> ReSkate and ReSkate for Mac are fan projects, not made or endorsed by Electronic Arts or Full Circle.
> skate. is EA's. Nothing here includes or shares the game: it is downloaded with your own Steam account.

## What you need

| | |
|---|---|
| Mac | **Apple Silicon** (M1, M2, M3, M4 or newer). Intel Macs cannot run it. |
| macOS | **14 Sonoma** or newer |
| Memory | 16 GB recommended (less may stutter; untested) |
| Disk | about **18 GB** free |
| Steam | a free Steam account, and the **Steam app on your phone** to sign in by scanning a QR code |

## Install

**Option 1, easiest:** open **Terminal** (press ⌘-Space, type *Terminal*, press Enter), paste this line and
press Enter:

```sh
curl -fsSL https://raw.githubusercontent.com/ValveTextureFile/reskatem/master/get.sh | bash
```

**Option 2:** download this project as a zip (green **Code** button → **Download ZIP**), unzip it, then
**right-click** `Install ReSkate for Mac.command` → **Open** → **Open**. (A plain double-click is blocked the
first time because the file came from the internet; right-click → Open allows it once.)

Then follow the steps on screen. The installer:

1. checks your Mac (and installs Rosetta 2 if needed; macOS may ask for your password),
2. sets up the compatibility layer (about 1 GB),
3. creates the Windows environment and installs the Visual C++ runtime,
4. opens skate.'s Steam page: click **Play Game** (or **Add to Library**) so the free game is on your
   account, then come back and press Enter,
5. shows a **QR code**: in the Steam app on your phone, open the Steam Guard (shield) tab, tap
   **Scan a QR code**, and approve. The game then downloads (about 12 GB),
6. installs ReSkate and adds **skate. (ReSkate)** to Applications.

Everything it does is printed as it happens and saved to `~/Library/Logs/ReSkate for Mac/`. If anything goes
wrong it says what happened and what to do; running it again continues where it stopped.

Already have skate.'s files (for example copied from a PC)? Skip the download:

```sh
bash scripts/install.sh --game-dir "/path/to/folder/with/Skate.exe"
```

## Play

Open **skate. (ReSkate)** from Applications or Spotlight and press **PLAY**.

- The **first start** can show a black screen for a few minutes while the graphics shaders are built.
- It plays **offline**: no EA servers needed; your progress is saved on your Mac.
- **Insert** opens the ReSkate menu, **~** the console. On a Mac keyboard without Insert, change the menu key
  in the launcher's Settings.
- If it runs slowly, lower the graphics settings or resolution in the game.
- **Mods:** install them from the launcher's **MODS** page, as on Windows.

## Update

Run the installer again. It updates ReSkate, and if ReSkate moved to a newer game build, downloads only the
files that changed.

## Something went wrong?

1. Double-click **Collect Diagnostics.command**. It saves a zip on your Desktop with your system details,
   what is installed (and whether each file checks out) and the recent logs, with your macOS account name
   replaced by `<you>`. It contains no game files and no Steam login.
2. [Open an issue](https://github.com/ValveTextureFile/reskatem/issues/new?template=problem.yml) (a free GitHub
   account is needed). The form asks what happened and how far it got; drag the zip into it.

Common problems:

| Problem | Fix |
|---|---|
| "Install ReSkate for Mac.command cannot be opened" | Right-click it → **Open** → **Open**, or use the Terminal line above. |
| "This is an Intel Mac" | Not supported: D3DMetal only exists for Apple Silicon. |
| The download says *no subscription* or *access denied* | Add skate. to your Steam library (free, **Play Game** on its store page), then run the installer again. |
| The QR code doesn't appear or expires | Run the installer again; it shows a fresh one. |
| Black screen on first start | Wait a few minutes: shaders are being built. |
| It stops right after starting | A dialog points to the log; run Collect Diagnostics and share the zip. |
| Very slow | Lower graphics settings; close other apps; 16 GB of memory is recommended. |

For detailed Wine logs, start it from Terminal with
`~/Library/Application\ Support/ReSkate\ for\ Mac/bin/launch.sh --debug`, and `--hud` shows Apple's
frame-rate overlay.

## Uninstall

Double-click **Uninstall.command**. It removes the app, the compatibility layer and the Windows environment,
and asks before deleting the game files (about 14 GB) or the logs.

## Where things are

| What | Where |
|---|---|
| App | `~/Applications/skate. (ReSkate).app` |
| Everything else (compatibility layer, Windows environment, game) | `~/Library/Application Support/ReSkate for Mac/` |
| Logs (installer and each game session) | `~/Library/Logs/ReSkate for Mac/` |
| ReSkate's own log | `…/ReSkate for Mac/game/logs/ReSkate.log` |

## How it works, and the parts it uses

| Part | Source | Pinned to |
|---|---|---|
| Wine + Apple D3DMetal 3.0 | [Gcenx/game-porting-toolkit](https://github.com/Gcenx/game-porting-toolkit) build of Apple's Game Porting Toolkit | 3.0-3, SHA-256 |
| Game download | [DepotDownloader](https://github.com/SteamRE/DepotDownloader) (the tool ReSkate itself uses) | 3.4.0, SHA-256 |
| Visual C++ runtime | Microsoft (`aka.ms/vs/17/release/vc_redist.x64.exe`) | Microsoft's current release |
| ReSkate launcher and runtime | [ReSkate releases](https://github.com/Dingo-Shenanigans/ReSkate/releases) | latest, checked against its `launcher.json` |
| Game build | Steam app 3354750, depot 3354751 | the manifest ReSkate's `launcher.json` names |

Apple's licence for the Game Porting Toolkit allows D3DMetal to be redistributed **for non-commercial
purposes only**; this project is free and must stay that way. Apple's licence covers developing, testing and
evaluating games on Apple devices; read it (`D3DMetal.framework/Versions/A/Resources/LICENSE` and Apple's
Game Porting Toolkit licence) before relying on it for anything else.
