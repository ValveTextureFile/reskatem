#!/usr/bin/env python3
"""Builds scripts/steam/xpi-ms-win-core-realtime-l1-1-1.dll, a code-free x64 DLL whose exports only forward
to kernel32. Steam's browser (Chromium/CEF 126) needs QueryUnbiasedInterruptTimePrecise, which the Wine 7.7 in
Game Porting Toolkit lacks; it is forwarded to QueryUnbiasedInterruptTime (same argument, same units).
scripts/steam.sh points libcef.dll at this DLL. Rebuild with:  python3 tools/make-forwarder-dll.py"""
import os
import struct

NAME = "xpi-ms-win-core-realtime-l1-1-1.dll"
FORWARDS = {
    "QueryUnbiasedInterruptTimePrecise": "kernel32.QueryUnbiasedInterruptTime",
    "QueryInterruptTimePrecise": "kernel32.QueryUnbiasedInterruptTime",
    "QueryInterruptTime": "kernel32.QueryUnbiasedInterruptTime",
    "QueryUnbiasedInterruptTime": "kernel32.QueryUnbiasedInterruptTime",
    "QueryThreadCycleTime": "kernel32.QueryThreadCycleTime",
    "QueryProcessCycleTime": "kernel32.QueryProcessCycleTime",
}
ALIGN = 0x1000  # section and file alignment
RVA = 0x1000    # the only section, .edata


def build():
    names = sorted(FORWARDS, key=str.encode)  # export names must be sorted
    n = len(names)
    eat, npt, ordt = 40, 40 + 4 * n, 40 + 8 * n
    strings_at = ordt + 2 * n
    strings = bytearray()

    def add(text):
        offset = strings_at + len(strings)
        strings.extend(text.encode() + b"\0")
        return RVA + offset

    dll_name = add(NAME)
    name_rvas = [add(name) for name in names]
    target_rvas = [add(FORWARDS[name]) for name in names]
    edata = bytearray(strings_at)
    struct.pack_into("<IIHHIIIIIII", edata, 0, 0, 0, 0, 0, dll_name, 1, n, n, RVA + eat, RVA + npt, RVA + ordt)
    for i in range(n):
        struct.pack_into("<I", edata, eat + 4 * i, target_rvas[i])  # inside .edata = forwarder
        struct.pack_into("<I", edata, npt + 4 * i, name_rvas[i])
        struct.pack_into("<H", edata, ordt + 2 * i, i)
    edata += strings
    size = len(edata)
    edata += b"\0" * (-len(edata) % ALIGN)

    dos = bytearray(64)
    dos[0:2] = b"MZ"
    struct.pack_into("<I", dos, 0x3C, 64)
    coff = struct.pack("<4sHHIIIHH", b"PE\0\0", 0x8664, 1, 0, 0, 0, 240, 0x2022)  # x64, DLL
    opt = bytearray(240)
    struct.pack_into("<HBBIIIIIQIIHHHHHHIIIIHHQQQQII", opt, 0,
                     0x20B, 14, 0, 0, len(edata), 0, 0, RVA, 0x180000000, ALIGN, ALIGN,
                     6, 0, 0, 0, 6, 0, 0, RVA + len(edata), ALIGN, 0, 3, 0x160,
                     0x100000, 0x1000, 0x100000, 0x1000, 0, 16)
    struct.pack_into("<II", opt, 112, RVA, size)  # export directory
    section = struct.pack("<8sIIIIIIHHI", b".edata\0\0", size, RVA, len(edata), ALIGN, 0, 0, 0, 0, 0x40000040)
    headers = bytes(dos) + coff + bytes(opt) + section
    return headers + b"\0" * (ALIGN - len(headers)) + bytes(edata)


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "steam", NAME)
    with open(out, "wb") as f:
        f.write(build())
    print("Wrote", os.path.normpath(out))
