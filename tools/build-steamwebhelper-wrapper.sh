#!/bin/bash
# Builds scripts/steam/steamwebhelper.exe from tools/steamwebhelper-wrapper.c. Needs Apple's clang (Xcode
# Command Line Tools) plus LLVM's lld-link and llvm-dlltool (brew install llvm lld). End users never run this;
# the built file is in the repository, and this lets anyone rebuild it and compare.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LLVM="${LLVM_BIN:-$(brew --prefix llvm 2>/dev/null)/bin}"
LLD_LINK="$(command -v lld-link || echo "$LLVM/lld-link")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf 'LIBRARY kernel32.dll\nEXPORTS\nGetCommandLineW\nGetModuleFileNameW\nGetEnvironmentVariableW\nCreateProcessW\nWaitForSingleObject\nGetExitCodeProcess\nExitProcess\n' > "$work/kernel32.def"
"$LLVM/llvm-dlltool" -m i386:x86-64 -d "$work/kernel32.def" -l "$work/libkernel32.a"
clang -target x86_64-pc-windows-gnu -O2 -ffreestanding -fno-stack-protector -fno-builtin -Wall \
    -c "$HERE/steamwebhelper-wrapper.c" -o "$work/wrapper.o"
"$LLD_LINK" /subsystem:windows /entry:start /nodefaultlib /machine:x64 /Brepro \
    /out:"$HERE/../scripts/steam/steamwebhelper.exe" "$work/wrapper.o" "$work/libkernel32.a"
echo "Built scripts/steam/steamwebhelper.exe ($(shasum -a 256 "$HERE/../scripts/steam/steamwebhelper.exe" | cut -d' ' -f1))"
