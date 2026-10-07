# Steam testing branch

This branch is working toward **online play** for ReSkate on Mac: running the Windows Steam client in the
same Windows environment as the game, so ReSkate signs you in with your own Steam account instead of
starting offline.

**It is experimental.** If you just want to play, use the `master` branch and the normal install in the
[README](README.md).

## What works so far

Tested on an M4 Mac with 16 GB, macOS 26.3:

| Step | Status |
|---|---|
| skate. runs on the online setup (Wine 11 + D3DMetal) and plays well | Works |
| Windows Steam installs, updates itself, and its window draws | Works |
| Signing in to Steam (QR code or password) | Works |
| ReSkate's launcher sees the signed-in Steam account | Works |
| ReSkate's server browser lists servers | Works (65 servers found) |
| **Joining a server** | **Not working yet**: times out while connecting |

ReSkate never starts EA's anti-cheat or contacts EA's servers: it starts `Skate.exe` itself, blocks the EA
app, and runs its own online services. So EA's anti-cheat is not a factor here.

## How it works

### Why a second setup

The normal (offline) setup runs on the Wine 7.7 in Apple's Game Porting Toolkit. Windows Steam cannot run
there:

- Its built-in browser (`steamwebhelper`, Chromium 126) crashes on start: it needs the Windows 10 function
  `QueryUnbiasedInterruptTimePrecise`, which Wine 7.7 lacks.
- Even with that patched around, Steam rejects its own window. Steam checks which program is on the other
  end of the local connection to its window, and Wine 7.7 on macOS cannot answer: `getsockname` fails on
  connections accepted with `AcceptEx`, and every connection is reported as owned by process 0. Faking the
  answer would mean switching off Steam's check that only its own browser may control it, so that was not
  done.

Wine 11 has neither problem. But the game needs Apple's D3DMetal for DirectX 12, and D3DMetal needs a
change in Wine's Mac driver (a `macdrv_functions` table) that plain Wine 11 builds do not have.
[MetalSharp](https://github.com/metalsharp/MetalSharp)'s runtime is a Wine 11.17 with that change, and it
ships the D3DMetal from Game Porting Toolkit 4.

So [`scripts/online-setup.sh`](scripts/online-setup.sh) builds a **second, separate setup** in
`~/Library/Application Support/ReSkate for Mac/online`:

1. MetalSharp's runtime (downloaded from their release, checked against a pinned SHA-256), with its
   D3DMetal put into Wine the way Game Porting Toolkit lays it out.
2. A copy of the game's Windows environment (an APFS clone, so it takes almost no extra space).
3. Windows Steam in that copy.

The offline setup is not changed, and both use the same game folder.

The online setup's environment (`online_wine_env` in [`scripts/common.sh`](scripts/common.sh)):

- **GnuTLS on the library path.** Wine's HTTPS needs it, and the runtime keeps it in its `x86_64-unix`
  folder. Without it, ReSkate cannot download its game content cache (`SEC_E_SECPKG_NOT_FOUND`).
- **D3DMetal's DLLs as builtins:** `d3d10,d3d11,d3d12,dxgi,nvapi64,nvngx-on-metalfx=b`.
- **`atiadlxx=d`**, as in the offline setup. D3DMetal presents the GPU as an AMD Radeon, and Wine's
  stand-in AMD driver library reports an old driver version.

### Steam's window

On Wine 11, Steam's window stays black unless its browser runs with `--in-process-gpu --disable-gpu`, and
Steam has no option to pass `--in-process-gpu`. So Steam's `steamwebhelper.exe` is renamed to
`steamwebhelper.real.exe`, and a small wrapper takes its place. The wrapper starts the real one with Steam's
arguments plus those flags.

- **The wrapper:** [`tools/steamwebhelper-wrapper.c`](tools/steamwebhelper-wrapper.c), about 30 lines, no C
  runtime.
- **The built file:** [`scripts/steam/steamwebhelper.exe`](scripts/steam/steamwebhelper.exe).
  [`tools/build-steamwebhelper-wrapper.sh`](tools/build-steamwebhelper-wrapper.sh) rebuilds it to the same
  bytes, so you can check it instead of trusting a binary.
- **Other flags:** set `STEAMWEBHELPER_FLAGS` to try different ones without rebuilding.

The idea comes from MetalSharp's Steam wrapper; this is a separate implementation.

Steam updates put their own `steamwebhelper.exe` back. So [`scripts/steam.sh`](scripts/steam.sh) puts the
wrapper in place before starting Steam and keeps watching while Steam runs. It replaces the file again
within a few seconds of an update.

## Future plans

Roughly in order:

1. **Joining servers.** It times out at "negotiating rendezvous" / "connecting". Next steps:
   - Read Steam's networking logs from a failed join.
   - Ask whether players on Linux/Proton can join. If they can, it is a Wine-on-macOS networking gap.
2. **Run online-setup from the installer** as an optional last step.
3. **Make online a choice in the app**, instead of a Terminal flag.
4. **Consider one setup instead of two.** If the Wine 11 setup proves at least as good offline, the offline
   setup could move to it too.

## Testing it

You need a working install from the normal [README](README.md) first.

**Before you start:**
- **Mods:** don't take mods online that your account shouldn't be seen with. You can move the `Mods` folder
  out of your game folder while testing.
- **Disk:** you need about 4 GB free.

**1. Install this branch's scripts.** This runs the installer from this branch. It keeps your game files,
so nothing big is downloaded again.

```sh
curl -fsSL https://raw.githubusercontent.com/ValveTextureFile/reskatem/steam-testing/get.sh | RESKATEM_BRANCH=steam-testing bash
```

**2. Set up online** (once, about 10 minutes):

```sh
"$HOME/Library/Application Support/ReSkate for Mac/bin/online-setup.sh"
```

**3. Start Steam and sign in.** The QR code works with the Steam app on your phone. Leave this Terminal
window open while you use Steam; it keeps the wrapper in place and finishes a minute after Steam quits.

```sh
"$HOME/Library/Application Support/ReSkate for Mac/bin/steam.sh"
```

**4. Start the game with Steam**, in a second Terminal window (⌘-N):

```sh
"$HOME/Library/Application Support/ReSkate for Mac/bin/launch.sh" --online
```

The ReSkate launcher shows your Steam account name when it sees Steam. Press **PLAY**.

### What to report

Tell contributors how far you got with the
[online test form](https://github.com/ValveTextureFile/reskatem/issues/new?template=online-test.yml) (a free GitHub
account is needed). Results that worked are just as useful as ones that did not. The form asks:

- Did online-setup finish?
- Did Steam's window draw, and could you sign in?
- Did the ReSkate launcher show your account?
- Did the game start, and did servers show up? Could you join one?
- Your Mac (chip, memory) and macOS version.

Attach the diagnostics zip to it: double-click **Collect Diagnostics.command**, then drag the zip it puts on
your Desktop into the form.
- **What's in it:** on this branch it includes the online setup's status and the Steam and online-setup
  logs.
- **What's left out:** your macOS account name is replaced with `<you>`, and there are no game files or
  logins.

### Undoing it

Quit Steam, then delete `~/Library/Application Support/ReSkate for Mac/online`. The offline setup is
untouched. To go back to the normal scripts, run the
normal install line from the README again.

## Licences and sources

| Part | Where it comes from |
|---|---|
| Wine 11.17 runtime | [MetalSharp](https://github.com/metalsharp/MetalSharp) `bundles` release (`metalsharp-runtime.tar.zst`), downloaded at setup time and checked against `ONLINE_RUNTIME_SHA256`. MetalSharp is AGPL-3.0; none of its code is in this repository. |
| D3DMetal (Game Porting Toolkit 4) | Shipped inside that runtime. Apple's licence allows D3DMetal to be redistributed **for non-commercial purposes only**. |
| Windows Steam | Valve's installer, downloaded at setup time. |

MetalSharp updates its `bundles` release in place. When it does, the pinned hash stops matching and
online-setup refuses the download. The pin in `scripts/common.sh` then needs updating after the new runtime
has been tested.

## Contributing

Help is welcome, especially:

- **Results from different Macs.** Did it work for you, and could you join a server?
- **Joining servers** (plan 1).
- **The installer step** (plan 2). Follow the existing installer: pinned downloads, checked hashes, plain
  explanations, and it should be safe to run again and pick up where it stopped.

Ground rules:

- **bash 3.2:** scripts are written for the bash that ships with macOS. That means no associative arrays and
  no `${var,,}`, and `${arr[@]+"${arr[@]}"}` for arrays that may be empty under `set -u`.
- **macOS tools only:** use only what macOS includes (bash, perl, plutil, curl, tar). Building the wrapper
  needs LLVM, but users never build it.
- **No copied code:** do not copy code or binaries from projects under incompatible licences (for example
  AGPL projects) into this repository. Ideas are fine; write your own version.
- **No game, Steam or login data:** never include or redistribute game files, Steam files, or anyone's login.
  Everything must be downloaded by the user with their own account.
- **Test on a copy:** to try something risky, point `RESKATEM_ONLINE_DIR` at a separate folder so your
  working online setup stays untouched:

  ```sh
  RESKATEM_ONLINE_DIR="$HOME/reskatem-online-test" scripts/online-setup.sh
  ```
