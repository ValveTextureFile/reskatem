/* 
 * steamwebhelper wrapper for Windows Steam under Wine on macOS (see STEAM-TESTING.md).
 *
 * Steam draws its window with steamwebhelper.exe (Chromium). Under Wine 11 on macOS that window stays black
 * unless Chromium runs its GPU code in-process with GPU acceleration off. Steam cannot be told to pass
 * --in-process-gpu, so scripts/steam.sh renames Steam's steamwebhelper.exe to steamwebhelper.real.exe and puts
 * this wrapper in its place. It starts the real one with Steam's arguments plus those flags (or the flags in
 * STEAMWEBHELPER_FLAGS, if set) and returns its exit code.
 *
 * Built without a C runtime or Windows SDK by tools/build-steamwebhelper-wrapper.sh. 
*/
typedef unsigned int DWORD;
typedef int BOOL;
typedef void *HANDLE;
typedef __CHAR16_TYPE__ WCHAR;   /* UTF-16, like Windows' WCHAR; u"" literals match it on any compiler target */

#ifdef _WIN32
#define IMPORT __declspec(dllimport)
#else
#define IMPORT   /* lets editors on macOS check this file without Windows flags */
#endif
typedef struct {
    DWORD cb;
    WCHAR *reserved, *desktop, *title;
    DWORD x, y, width, height, x_chars, y_chars, fill, flags;
    unsigned short show, reserved2;
    void *reserved3;
    HANDLE std_in, std_out, std_err;
} STARTUPINFOW;
typedef struct { HANDLE process, thread; DWORD process_id, thread_id; } PROCESS_INFORMATION;

IMPORT WCHAR *GetCommandLineW(void);
IMPORT DWORD GetModuleFileNameW(void *, WCHAR *, DWORD);
IMPORT DWORD GetEnvironmentVariableW(const WCHAR *, WCHAR *, DWORD);
IMPORT BOOL CreateProcessW(const WCHAR *, WCHAR *, void *, void *, BOOL, DWORD, void *,
                                          const WCHAR *, STARTUPINFOW *, PROCESS_INFORMATION *);
IMPORT DWORD WaitForSingleObject(HANDLE, DWORD);
IMPORT BOOL GetExitCodeProcess(HANDLE, DWORD *);
IMPORT void ExitProcess(DWORD);

static WCHAR exe[1024], command[32768], flags[1024];
static const WCHAR default_flags[] = u" --in-process-gpu --disable-gpu";

static WCHAR *append(WCHAR *to, const WCHAR *text) {
    while (*text) *to++ = *text++;
    *to = 0;
    return to;
}

void start(void) {
    /* The real browser is beside this file. */
    DWORD n = GetModuleFileNameW(0, exe, 1000);
    while (n && exe[n - 1] != '\\') n--;
    append(exe + n, u"steamwebhelper.real.exe");

    /* Steam's arguments: our command line without our own program name. */
    const WCHAR *args = GetCommandLineW();
    if (*args == '"') {
        args++;
        while (*args && *args != '"') args++;
        if (*args) args++;
    } else {
        while (*args && *args != ' ') args++;
    }

    WCHAR *end = append(append(append(append(command, u"\""), exe), u"\""), args);
    if (GetEnvironmentVariableW(u"STEAMWEBHELPER_FLAGS", flags + 1, 1000)) {
        flags[0] = ' ';
        append(end, flags);
    } else {
        append(end, default_flags);
    }

    STARTUPINFOW startup = { sizeof startup };
    PROCESS_INFORMATION process;
    DWORD code = 1;
    if (!CreateProcessW(exe, command, 0, 0, 0, 0, 0, 0, &startup, &process)) ExitProcess(1);
    WaitForSingleObject(process.process, 0xffffffff);
    GetExitCodeProcess(process.process, &code);
    ExitProcess(code);
}
