// Checks the msimg32.dll stand-in through a fake ReSkate.dll (ReSkate.c). Run in Wine with test.exe,
// ReSkate.dll and msimg32.dll in one folder and WINEDLLOVERRIDES="msimg32=n,b". Prints PASS/FAIL lines and
// exits non-zero on any failure. On Wine 7.7 without the stand-in the bcrypt checks crash at 0x41.
#include <windows.h>
#include <stdio.h>
#include <string.h>

typedef BOOL (WINAPI *Read)(HANDLE, LPCVOID, LPVOID, SIZE_T, SIZE_T *);
typedef BOOL (WINAPI *TestRead)(LPCVOID, LPVOID, SIZE_T, SIZE_T *);
typedef LONG (WINAPI *Hash)(PUCHAR, ULONG, PUCHAR);
typedef LONG (WINAPI *Hmac)(PUCHAR, ULONG, PUCHAR, ULONG, PUCHAR);
typedef LONG (WINAPI *Length)(ULONG *);
typedef LONG (WINAPI *Random)(PUCHAR, ULONG);
typedef LONG (WINAPI *Pbkdf2)(PUCHAR);

static int failures;
static void check(const char *what, int ok) { printf("%s %s\n", ok ? "PASS" : "FAIL", what); failures += !ok; }
static int hex_is(const UCHAR *bytes, const char *hex)
{
    char text[65];
    for (int i = 0; i < 32; i++) sprintf(text + 2 * i, "%02x", bytes[i]);
    return !strcmp(text, hex);
}

static double bench(TestRead r)
{
    static char src[256]; char dst[256]; SIZE_T n; LARGE_INTEGER f, a, b;
    QueryPerformanceFrequency(&f); QueryPerformanceCounter(&a);
    for (int i = 0; i < 20000; i++) r(src, dst, 64, &n);
    QueryPerformanceCounter(&b);
    return (double)(b.QuadPart - a.QuadPart) * 1e6 / f.QuadPart / 20000;
}

int main(void)
{
    HMODULE reskate = LoadLibraryA("ReSkate.dll");
    HMODULE shim = GetModuleHandleA("msimg32.dll");
    if (!reskate || !shim) { printf("FAIL could not load ReSkate.dll / msimg32.dll\n"); return 1; }
    check("msimg32.dll is the stand-in", GetProcAddress(shim, "FastReadForTest") != NULL);
    check("AlphaBlend forwards to gdi32", GetProcAddress(shim, "AlphaBlend") != NULL);

    // ReadProcessMemory, through ReSkate.dll's redirected import.
    TestRead read = (TestRead)GetProcAddress(reskate, "test_read");
    static int value = 1234; int out = 0; SIZE_T n = 0;
    check("read: valid", read(&value, &out, 4, &n) && out == 1234 && n == 4);
    check("read: invalid address fails", !read((void *)0x10, &out, 4, &n));
    char *guard = VirtualAlloc(NULL, 4096, MEM_COMMIT, PAGE_READWRITE | PAGE_GUARD);
    check("read: guard page fails without crashing", !read(guard, &out, 4, &n));
    char *two = VirtualAlloc(NULL, 8192, MEM_COMMIT, PAGE_READWRITE); DWORD old;
    VirtualProtect(two + 4096, 4096, PAGE_NOACCESS, &old);
    check("read: range into a no-access page fails", !read(two + 4094, &out, 4, &n));
    Read fast = (Read)GetProcAddress(shim, "FastReadForTest");
    check("read: ReSkate's import is redirected", fast && bench(read) < 5.0);
    printf("     read through ReSkate.dll: %.2f us\n", bench(read));

    // BCrypt pseudo-handles, through ReSkate.dll's redirected imports.
    UCHAR digest[32] = {0};
    const char *abc_sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    check("BCryptHash(SHA256 pseudo-handle)",
          !((Hash)GetProcAddress(reskate, "test_sha256"))((PUCHAR)"abc", 3, digest) && hex_is(digest, abc_sha256));
    memset(digest, 0, 32);
    check("BCryptHash(HMAC-SHA256 pseudo-handle)",
          !((Hmac)GetProcAddress(reskate, "test_hmac_sha256"))((PUCHAR)"key", 3,
              (PUCHAR)"The quick brown fox jumps over the lazy dog", 43, digest) &&
          hex_is(digest, "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"));
    memset(digest, 0, 32);
    check("BCryptCreateHash(SHA256 pseudo-handle)",
          !((Hash)GetProcAddress(reskate, "test_create_hash"))((PUCHAR)"abc", 3, digest) &&
          hex_is(digest, abc_sha256));
    ULONG length = 0;
    check("BCryptGetProperty(SHA256 pseudo-handle)",
          !((Length)GetProcAddress(reskate, "test_hash_length"))(&length) && length == 32);
    UCHAR random[32] = {0}, zero[32] = {0};
    check("BCryptGenRandom(RNG pseudo-handle)",
          !((Random)GetProcAddress(reskate, "test_random"))(random, 32) && memcmp(random, zero, 32));
    memset(digest, 0, 32);
    check("BCryptDeriveKeyPBKDF2(HMAC-SHA256 pseudo-handle)",
          !((Pbkdf2)GetProcAddress(reskate, "test_pbkdf2"))(digest) &&
          hex_is(digest, "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"));

    printf(failures ? "%d check(s) failed\n" : "all checks passed\n", failures);
    return failures != 0;
}
