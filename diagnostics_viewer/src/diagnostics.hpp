#pragma once

#include "miniz.h"
#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// What one diagnostics zip (scripts/diagnose.sh) holds: report.txt, launcher.json and logs/*.
struct LogFile {
    std::string name;
    std::string text;
    std::vector<size_t> lines; // where each line starts in text
    int errors = 0;            // lines log_line_kind calls errors
};

struct Diagnostics {
    bool loaded = false;
    std::string zip_path;
    std::string error;    // why the last import failed, empty if it worked
    std::string report;   // report.txt
    std::string launcher; // launcher.json, empty if the installer never finished
    std::vector<LogFile> logs;
    std::vector<const struct KnownProblem*> problems; // known problems found in the report or logs
};

// Signatures seen in real reports, with what to tell the user. Add a row when a new one is diagnosed.
struct KnownProblem {
    const char* text; // found anywhere in report.txt or a log
    const char* title;
    const char* advice;
};
inline const KnownProblem known_problems[] = {
    {"cannot create the Direct3D 12 pipeline", "The launcher can't draw its window (ReSkate 2.0.4+ under D3DMetal)",
     "Its new HDR shader doesn't build under Game Porting Toolkit. Run \"Downgrade ReSkate to 2.0.3.command\"; the fix is Dingo-Shenanigans/ReSkate#177."},
    {"Unhandled page fault on read access to 0000000000000041", "ReSkate's crash uploader faulted (BCryptHash under GPTK's Wine)",
     "Usually follows another error, so look for that first. RESKATE_CRASH_REPORTING=0 stops it (reskatem issue #1)."},
    {"Failed to dlopen D3DMetal", "macOS is older than 15.4", "D3DMetal 3.0 needs macOS 15.4 or newer: update macOS."},
    {"Please update your AMD Radeon driver", "skate. failed its AMD driver check",
     "WINEDLLOVERRIDES is missing atiadlxx=d; run the installer again to refresh the launch scripts."},
    {"Rosetta 2: NOT installed", "Rosetta 2 is missing", "Run the installer again; it installs Rosetta."},
    {"\nMISSING ", "Part of the install is missing", "Run the installer again; finished steps are skipped and missing parts repaired."},
    {"\nMISMATCH ", "ReSkate's files aren't the version the installer recorded",
     "Usually the launcher updated itself; check the Launcher tab. Run the installer again if it misbehaves."},
};

inline Diagnostics g_diag;

inline bool ends_with(const std::string& s, const std::string& suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

inline bool contains_nocase(const char* s, const char* e, const char* needle) {
    size_t n = std::strlen(needle);
    for (; s + n <= e; s++) {
        size_t i = 0;
        while (i < n && std::tolower((unsigned char)s[i]) == needle[i])
            i++;
        if (i == n)
            return true;
    }
    return false;
}

// 0 normal, 1 error, 2 warning, 3 noise (wine fixme lines)
inline int log_line_kind(const char* s, const char* e) {
    if (contains_nocase(s, e, "fixme:"))
        return 3;
    // A level the log states itself wins over words in the message ("[WARNING] crash reporter...").
    for (const char* w : {"[error]", "[critical]", "[fatal]", "err:"})
        if (contains_nocase(s, e, w))
            return 1;
    for (const char* w : {"[warning]", "[warn]", "warn:"})
        if (contains_nocase(s, e, w))
            return 2;
    for (const char* w : {"error", "fail", "crash", "exception", "unhandled"})
        if (contains_nocase(s, e, w))
            return 1;
    return contains_nocase(s, e, "warn") ? 2 : 0;
}

// Reads the zip into memory only (nothing is written to disk) and replaces g_diag on success.
inline void load_diagnostics(const std::string& path) {
    // Zips come from other people: refuse anything that would unpack to more than this.
    const mz_uint64 max_file_size = 64ull << 20;

    mz_zip_archive zip{};
    if (!mz_zip_reader_init_file(&zip, path.c_str(), 0)) {
        g_diag.error = "Could not open " + path + " as a zip: " + mz_zip_get_error_string(mz_zip_get_last_error(&zip));
        return;
    }

    Diagnostics d;
    d.zip_path = path;
    for (mz_uint i = 0; i < mz_zip_reader_get_num_files(&zip); i++) {
        mz_zip_archive_file_stat st;
        if (!mz_zip_reader_file_stat(&zip, i, &st) || st.m_is_directory)
            continue;
        std::string name = st.m_filename;
        // The zip has one top folder (ReSkate-for-Mac-diagnostics-<date>/), so match on the end of the path.
        std::string* dest = nullptr;
        bool is_log = name.find("/logs/") != std::string::npos || name.rfind("logs/", 0) == 0;
        if (name == "report.txt" || ends_with(name, "/report.txt"))
            dest = &d.report;
        else if (name == "launcher.json" || ends_with(name, "/launcher.json"))
            dest = &d.launcher;
        else if (!is_log)
            continue;

        std::string text;
        if (st.m_uncomp_size > max_file_size) {
            text = "(skipped: larger than 64 MB)";
        } else {
            size_t size = 0;
            void* data = mz_zip_reader_extract_to_heap(&zip, i, &size, 0);
            if (data) {
                text.assign(static_cast<const char*>(data), size);
                mz_free(data);
            } else {
                text = std::string("(could not unpack: ") + mz_zip_get_error_string(mz_zip_get_last_error(&zip)) + ")";
            }
        }

        if (dest)
            *dest = std::move(text);
        else
            d.logs.push_back({name.substr(name.rfind('/') + 1), std::move(text)});
    }
    mz_zip_reader_end(&zip);

    if (d.report.empty()) {
        g_diag.error = path + " has no report.txt, so it is not a ReSkate diagnostics zip.";
        return;
    }
    std::sort(d.logs.begin(), d.logs.end(), [](const LogFile& a, const LogFile& b) { return a.name < b.name; });
    for (LogFile& l : d.logs) {
        if (!l.text.empty() && l.text.back() == '\n')
            l.text.pop_back();
        for (size_t p = 0; p <= l.text.size(); p = l.text.find('\n', p) + 1) {
            l.lines.push_back(p);
            size_t e = l.text.find('\n', p);
            l.errors += log_line_kind(l.text.data() + p, l.text.data() + (e == std::string::npos ? l.text.size() : e)) == 1;
            if (e == std::string::npos)
                break;
        }
    }
    for (const KnownProblem& p : known_problems) {
        bool found = d.report.find(p.text) != std::string::npos;
        for (const LogFile& l : d.logs)
            found = found || l.text.find(p.text) != std::string::npos;
        if (found)
            d.problems.push_back(&p);
    }
    d.loaded = true;
    g_diag = std::move(d);
}

// Runs a shell command and returns what it printed; ok is false if it exited with an error.
inline std::string run(const char* cmd, bool* ok = nullptr) {
    std::string out;
    int status = -1;
    if (FILE* p = popen(cmd, "r")) {
        char buf[4096];
        size_t n;
        while ((n = fread(buf, 1, sizeof buf, p)) > 0)
            out.append(buf, n);
        status = pclose(p);
    }
    if (ok)
        *ok = status == 0;
    return out;
}

// Asks the OS for a .zip with its own dialog; returns "" if cancelled.
// shortcut: blocks the UI while the dialog is open and needs osascript (macOS) or zenity (Linux).
inline std::string pick_zip() {
#ifdef __APPLE__
    const char* cmd = "osascript -e 'POSIX path of (choose file of type {\"zip\"} with prompt \"Choose a diagnostics zip\")' 2>/dev/null";
#else
    const char* cmd = "zenity --file-selection --title='Choose a diagnostics zip' --file-filter='*.zip' 2>/dev/null";
#endif
    std::string out = run(cmd);
    while (!out.empty() && (out.back() == '\n' || out.back() == '\r'))
        out.pop_back();
    return out;
}
