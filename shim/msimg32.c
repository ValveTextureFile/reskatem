// msimg32.dll stand-in for skate. + ReSkate under GPTK's Wine 7.7 on macOS. ReSkate.dll imports msimg32,
// so this loads with it; on load it redirects a few of ReSkate.dll's own imports (its import slots only:
// the game's anti-tamper quits silently if system DLL code such as kernelbase is patched). The msimg32
// exports forward to gdi32, exactly as Wine's own msimg32 does.
//
// 1. ReadProcessMemory. ReSkate reads game memory with ReadProcessMemory(GetCurrentProcess(), ...). On
//    Windows that is a ~1 us syscall; in Wine every call is a wineserver round trip (~15 us under Rosetta),
//    which turns ReSkate's periodic world scans into 15-20 ms spikes that push the 60 Hz sim into slow
//    motion. Reads of our own process become a plain copy; other processes still go to NtReadVirtualMemory.
//    By AUstnnnnnn: https://github.com/ValveTextureFile/reskatem/issues/1
//
// 2. BCrypt pseudo-handles. ReSkate hashes with BCRYPT_SHA256_ALG_HANDLE (0x41) and friends. Wine 7.7 has
//    no pseudo-handle support: BCryptHash and the others read the handle as a pointer and fault at 0x41.
//    RESKATE_CRASH_REPORTING=0 kept the crash uploader from doing it, but since 2.1.3 the Music extension
//    (Spotify, YouTube Music) does it too. Pseudo-handles are swapped for real handles from
//    BCryptOpenAlgorithmProvider, opened once and kept.
//    https://github.com/ValveTextureFile/reskatem/issues/16
#include <windows.h>
#include <winternl.h>
#include <bcrypt.h>
#include <string.h>

// ---- ReadProcessMemory ----------------------------------------------------------------------------------
typedef NTSTATUS (NTAPI *NtReadVirtualMemory_t)(HANDLE, PVOID, PVOID, SIZE_T, SIZE_T *);
static NtReadVirtualMemory_t nt_read;

// Whole range committed and plainly readable. VirtualQuery reads the page tables without touching
// memory: IsBadReadPtr touches it, and in Wine a guard page (thread stacks) then kills the game.
static BOOL readable(LPCVOID address, SIZE_T size)
{
    const BYTE *p = address, *end = p + size;
    while (p < end) {
        MEMORY_BASIC_INFORMATION info;
        if (!VirtualQuery(p, &info, sizeof(info)) || info.State != MEM_COMMIT ||
            (info.Protect & (PAGE_GUARD | PAGE_NOACCESS)) ||
            !(info.Protect & (PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ |
                              PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)))
            return FALSE;
        p = (const BYTE *)info.BaseAddress + info.RegionSize;
    }
    return TRUE;
}

BOOL WINAPI fast_read(HANDLE process, LPCVOID address, LPVOID buffer, SIZE_T size, SIZE_T *read)
{
    if (process == GetCurrentProcess() && size && readable(address, size)) {
        memcpy(buffer, address, size);
        if (read) *read = size;
        return TRUE;
    }
    NTSTATUS status = nt_read(process, (PVOID)address, buffer, size, read);
    if (status) {
        SetLastError(RtlNtStatusToDosError(status));
        return FALSE;
    }
    return TRUE;
}

// ---- BCrypt pseudo-handles ------------------------------------------------------------------------------
// Pseudo-handle n is (n << 4) | 1 (bcrypt.h). Only the ones Wine 7.7 can open are listed; others pass through.
static const struct { const WCHAR *id; DWORD flags; } pseudo_algs[] = {
    [0x0] = { BCRYPT_MD2_ALGORITHM, 0 },
    [0x1] = { BCRYPT_MD4_ALGORITHM, 0 },
    [0x2] = { BCRYPT_MD5_ALGORITHM, 0 },
    [0x3] = { BCRYPT_SHA1_ALGORITHM, 0 },
    [0x4] = { BCRYPT_SHA256_ALGORITHM, 0 },
    [0x5] = { BCRYPT_SHA384_ALGORITHM, 0 },
    [0x6] = { BCRYPT_SHA512_ALGORITHM, 0 },
    [0x8] = { BCRYPT_RNG_ALGORITHM, 0 },
    [0x9] = { BCRYPT_MD5_ALGORITHM, BCRYPT_ALG_HANDLE_HMAC_FLAG },
    [0xa] = { BCRYPT_SHA1_ALGORITHM, BCRYPT_ALG_HANDLE_HMAC_FLAG },
    [0xb] = { BCRYPT_SHA256_ALGORITHM, BCRYPT_ALG_HANDLE_HMAC_FLAG },
    [0xc] = { BCRYPT_SHA384_ALGORITHM, BCRYPT_ALG_HANDLE_HMAC_FLAG },
    [0xd] = { BCRYPT_SHA512_ALGORITHM, BCRYPT_ALG_HANDLE_HMAC_FLAG },
};
#define PSEUDO_COUNT (sizeof(pseudo_algs) / sizeof(pseudo_algs[0]))
static BCRYPT_ALG_HANDLE real_algs[PSEUDO_COUNT];

typedef NTSTATUS (WINAPI *BCryptOpenAlgorithmProvider_t)(BCRYPT_ALG_HANDLE *, LPCWSTR, LPCWSTR, ULONG);
typedef NTSTATUS (WINAPI *BCryptCloseAlgorithmProvider_t)(BCRYPT_ALG_HANDLE, ULONG);
typedef NTSTATUS (WINAPI *BCryptHash_t)(BCRYPT_ALG_HANDLE, PUCHAR, ULONG, PUCHAR, ULONG, PUCHAR, ULONG);
typedef NTSTATUS (WINAPI *BCryptCreateHash_t)(BCRYPT_ALG_HANDLE, BCRYPT_HASH_HANDLE *, PUCHAR, ULONG, PUCHAR,
                                             ULONG, ULONG);
typedef NTSTATUS (WINAPI *BCryptGetProperty_t)(BCRYPT_HANDLE, LPCWSTR, PUCHAR, ULONG, ULONG *, ULONG);
typedef NTSTATUS (WINAPI *BCryptGenRandom_t)(BCRYPT_ALG_HANDLE, PUCHAR, ULONG, ULONG);
typedef NTSTATUS (WINAPI *BCryptDeriveKeyPBKDF2_t)(BCRYPT_ALG_HANDLE, PUCHAR, ULONG, PUCHAR, ULONG, ULONGLONG,
                                                  PUCHAR, ULONG, ULONG);
static BCryptOpenAlgorithmProvider_t open_alg;
static BCryptCloseAlgorithmProvider_t close_alg;
static BCryptHash_t real_hash;
static BCryptCreateHash_t real_create_hash;
static BCryptGetProperty_t real_get_property;
static BCryptGenRandom_t real_gen_random;
static BCryptDeriveKeyPBKDF2_t real_pbkdf2;

static BCRYPT_HANDLE real_handle(BCRYPT_HANDLE handle)
{
    ULONG_PTR value = (ULONG_PTR)handle, n = value >> 4;
    if ((value & 0xf) != 1 || n >= PSEUDO_COUNT || !pseudo_algs[n].id || !open_alg) return handle;
    BCRYPT_ALG_HANDLE alg = real_algs[n];
    if (alg) return alg;
    if (open_alg(&alg, pseudo_algs[n].id, NULL, pseudo_algs[n].flags)) return handle;
    BCRYPT_ALG_HANDLE won = InterlockedCompareExchangePointer(&real_algs[n], alg, NULL);
    if (won) { close_alg(alg, 0); return won; }  // another thread opened it first
    return alg;
}

NTSTATUS WINAPI fix_hash(BCRYPT_ALG_HANDLE alg, PUCHAR secret, ULONG secret_len, PUCHAR input, ULONG input_len,
                         PUCHAR output, ULONG output_len)
{
    return real_hash(real_handle(alg), secret, secret_len, input, input_len, output, output_len);
}

NTSTATUS WINAPI fix_create_hash(BCRYPT_ALG_HANDLE alg, BCRYPT_HASH_HANDLE *hash, PUCHAR object, ULONG object_len,
                                PUCHAR secret, ULONG secret_len, ULONG flags)
{
    return real_create_hash(real_handle(alg), hash, object, object_len, secret, secret_len, flags);
}

NTSTATUS WINAPI fix_get_property(BCRYPT_HANDLE handle, LPCWSTR prop, PUCHAR buffer, ULONG count, ULONG *result,
                                 ULONG flags)
{
    return real_get_property(real_handle(handle), prop, buffer, count, result, flags);
}

NTSTATUS WINAPI fix_gen_random(BCRYPT_ALG_HANDLE alg, PUCHAR buffer, ULONG count, ULONG flags)
{
    return real_gen_random(real_handle(alg), buffer, count, flags);
}

NTSTATUS WINAPI fix_pbkdf2(BCRYPT_ALG_HANDLE alg, PUCHAR password, ULONG password_len, PUCHAR salt, ULONG salt_len,
                           ULONGLONG iterations, PUCHAR key, ULONG key_len, ULONG flags)
{
    return real_pbkdf2(real_handle(alg), password, password_len, salt, salt_len, iterations, key, key_len, flags);
}

// ---- Import redirection ---------------------------------------------------------------------------------
// Points every slot in ReSkate.dll's imports from DLL (any case) named FUNCTION at REPLACEMENT. ReSkate
// imports us, so its imports are already bound when this runs. Its import table lists kernel32 twice
// (kernel32.dll and KERNEL32.dll), so every matching descriptor is patched.
static void redirect(BYTE *base, const char *dll, const char *function, void *replacement)
{
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    for (IMAGE_IMPORT_DESCRIPTOR *d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); d->Name; d++) {
        if (lstrcmpiA((char *)(base + d->Name), dll) || !d->OriginalFirstThunk) continue;
        IMAGE_THUNK_DATA *names = (IMAGE_THUNK_DATA *)(base + d->OriginalFirstThunk);
        IMAGE_THUNK_DATA *slots = (IMAGE_THUNK_DATA *)(base + d->FirstThunk);
        for (; names->u1.AddressOfData; names++, slots++) {
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            IMAGE_IMPORT_BY_NAME *n = (IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData);
            if (strcmp((char *)n->Name, function)) continue;
            DWORD old;
            if (!VirtualProtect(&slots->u1.Function, sizeof(slots->u1.Function), PAGE_READWRITE, &old)) continue;
            slots->u1.Function = (ULONG_PTR)replacement;
            VirtualProtect(&slots->u1.Function, sizeof(slots->u1.Function), old, &old);
        }
    }
}

static void install(void)
{
    BYTE *base = (BYTE *)GetModuleHandleA("ReSkate.dll");
    if (!base) return;

    nt_read = (NtReadVirtualMemory_t)GetProcAddress(GetModuleHandleA("ntdll.dll"), "NtReadVirtualMemory");
    if (nt_read) redirect(base, "kernel32.dll", "ReadProcessMemory", fast_read);
    HMODULE bcrypt = GetModuleHandleA("bcrypt.dll");
    open_alg = (BCryptOpenAlgorithmProvider_t)GetProcAddress(bcrypt, "BCryptOpenAlgorithmProvider");
    close_alg = (BCryptCloseAlgorithmProvider_t)GetProcAddress(bcrypt, "BCryptCloseAlgorithmProvider");
    if (!open_alg || !close_alg) return;
    real_hash = (BCryptHash_t)GetProcAddress(bcrypt, "BCryptHash");
    real_create_hash = (BCryptCreateHash_t)GetProcAddress(bcrypt, "BCryptCreateHash");
    real_get_property = (BCryptGetProperty_t)GetProcAddress(bcrypt, "BCryptGetProperty");
    real_gen_random = (BCryptGenRandom_t)GetProcAddress(bcrypt, "BCryptGenRandom");
    real_pbkdf2 = (BCryptDeriveKeyPBKDF2_t)GetProcAddress(bcrypt, "BCryptDeriveKeyPBKDF2");
    if (real_hash) redirect(base, "bcrypt.dll", "BCryptHash", fix_hash);
    if (real_create_hash) redirect(base, "bcrypt.dll", "BCryptCreateHash", fix_create_hash);
    if (real_get_property) redirect(base, "bcrypt.dll", "BCryptGetProperty", fix_get_property);
    if (real_gen_random) redirect(base, "bcrypt.dll", "BCryptGenRandom", fix_gen_random);
    if (real_pbkdf2) redirect(base, "bcrypt.dll", "BCryptDeriveKeyPBKDF2", fix_pbkdf2);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        install();
    }
    return TRUE;
}

void WINAPI vSetDdrawflag(void) {}
