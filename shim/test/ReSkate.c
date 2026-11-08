// A fake ReSkate.dll for test.exe: it imports msimg32, ReadProcessMemory and the bcrypt functions the way
// the real one does, so the stand-in redirects its imports.
#include <windows.h>
#include <bcrypt.h>

__declspec(dllexport) void *keep_msimg32_import = AlphaBlend;

__declspec(dllexport) BOOL WINAPI test_read(LPCVOID address, LPVOID buffer, SIZE_T size, SIZE_T *read)
{
    return ReadProcessMemory(GetCurrentProcess(), address, buffer, size, read);
}

__declspec(dllexport) NTSTATUS WINAPI test_sha256(PUCHAR input, ULONG input_len, PUCHAR output)
{
    return BCryptHash(BCRYPT_SHA256_ALG_HANDLE, NULL, 0, input, input_len, output, 32);
}

__declspec(dllexport) NTSTATUS WINAPI test_hmac_sha256(PUCHAR key, ULONG key_len, PUCHAR input, ULONG input_len,
                                                       PUCHAR output)
{
    return BCryptHash(BCRYPT_HMAC_SHA256_ALG_HANDLE, key, key_len, input, input_len, output, 32);
}

__declspec(dllexport) NTSTATUS WINAPI test_create_hash(PUCHAR input, ULONG input_len, PUCHAR output)
{
    BCRYPT_HASH_HANDLE hash;
    NTSTATUS status = BCryptCreateHash(BCRYPT_SHA256_ALG_HANDLE, &hash, NULL, 0, NULL, 0, 0);
    if (status) return status;
    if (!(status = BCryptHashData(hash, input, input_len, 0))) status = BCryptFinishHash(hash, output, 32, 0);
    BCryptDestroyHash(hash);
    return status;
}

__declspec(dllexport) NTSTATUS WINAPI test_hash_length(ULONG *length)
{
    ULONG size;
    return BCryptGetProperty(BCRYPT_SHA256_ALG_HANDLE, BCRYPT_HASH_LENGTH, (PUCHAR)length, sizeof(*length), &size, 0);
}

__declspec(dllexport) NTSTATUS WINAPI test_random(PUCHAR buffer, ULONG count)
{
    return BCryptGenRandom(BCRYPT_RNG_ALG_HANDLE, buffer, count, 0);
}

__declspec(dllexport) NTSTATUS WINAPI test_pbkdf2(PUCHAR output)
{
    return BCryptDeriveKeyPBKDF2(BCRYPT_HMAC_SHA256_ALG_HANDLE, (PUCHAR)"password", 8, (PUCHAR)"salt", 4, 1,
                                 output, 32, 0);
}
