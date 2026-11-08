#!/bin/bash
# Builds msimg32.dll (and with --test, test/test.exe and its fake ReSkate.dll) with mingw-w64, or zig if
# mingw-w64 is missing. The installer copies the built msimg32.dll next to Skate.exe; see msimg32.c.
#
#   brew install mingw-w64     (or: brew install zig)
#   shim/build.sh [--test]
set -euo pipefail
cd "$(dirname "$0")"
if command -v x86_64-w64-mingw32-gcc >/dev/null; then
    x86_64-w64-mingw32-gcc -O2 -s -shared -nostartfiles -Wl,--entry,DllMain -o msimg32.dll msimg32.c msimg32.def \
        -lkernel32 -lntdll -lmsvcrt
    cc=(x86_64-w64-mingw32-gcc)
elif command -v zig >/dev/null; then
    zig cc -target x86_64-windows-gnu -O2 -s -shared -o msimg32.dll msimg32.c msimg32.def -lntdll
    cc=(zig cc -target x86_64-windows-gnu)
else
    echo "Needs x86_64-w64-mingw32-gcc or zig." >&2; exit 1
fi
rm -f ./*.lib ./*.pdb
echo "built shim/msimg32.dll"
if [ "${1:-}" = --test ]; then
    "${cc[@]}" -O2 -shared -o test/ReSkate.dll test/ReSkate.c -lmsimg32 -lbcrypt
    "${cc[@]}" -O2 -o test/test.exe test/test.c
    cp msimg32.dll test/
    rm -f test/*.lib test/*.pdb
    echo "built shim/test; run it in Wine:  cd shim/test && WINEDLLOVERRIDES=msimg32=n,b wine test.exe"
fi
