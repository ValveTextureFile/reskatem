#!/bin/bash
# One-line install, run in Terminal:
#
#   https://raw.githubusercontent.com/ValveTextureFile/reskatem/refs/heads/master/get.sh | bash
#
# Downloads this project into ~/ReSkate for Mac (installer) and starts the installer. Files fetched this
# way are not quarantined by Gatekeeper, so there is no "cannot be opened" warning to click through.
set -euo pipefail
repo="${RESKATEM_REPO:-ValveTextureFile/reskatem}"
branch="${RESKATEM_BRANCH:-main}"
dest="$HOME/ReSkate for Mac (installer)"

echo "Downloading the ReSkate for Mac installer from github.com/$repo ..."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar "https://github.com/$repo/archive/refs/heads/$branch.zip" -o "$tmp/installer.zip"
unzip -q "$tmp/installer.zip" -d "$tmp"
rm -rf "$dest"
mv "$tmp"/*-"$branch" "$dest"
chmod +x "$dest"/*.command "$dest"/scripts/*.sh
echo "Saved to: $dest"
echo
# Questions are read from the terminal, not from this pipe.
exec bash "$dest/scripts/install.sh" "$@" </dev/tty
