#pragma once

#include "diagnostics.hpp"
#include "imgui.h"
#include "json.hpp"
#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <regex>
#include <string>
#include <vector>

#define ISSUES_REPO "ValveTextureFile/reskatem"

struct IssueComment {
    std::string user;
    std::string created_at;
    std::string body;
};

struct Issue {
    int number = 0;
    std::string title;
    std::string state; // "open" or "closed"
    std::string user;
    std::string created_at;
    std::string body;
    std::vector<std::string> labels;
    int comment_count = 0;
    bool comments_loaded = false;
    std::vector<IssueComment> comments;
};

struct Issues {
    bool fetched = false;
    std::string error;
    std::vector<Issue> list;
};

inline Issues g_issues;

inline std::string json_str(const nlohmann::json& j, const char* key) {
    auto it = j.find(key);
    return it != j.end() && it->is_string() ? it->get<std::string>() : "";
}

// GETs a GitHub API path with curl (ships with macOS); returns null and sets error on failure.
// shortcut: no auth, so 60 requests/hour per IP; add a token header if that runs out.
inline nlohmann::json github_get(const std::string& path, std::string& error) {
    std::string cmd = "curl -fsSL --max-time 15 -H 'Accept: application/vnd.github+json' 'https://api.github.com/" + path + "' 2>&1";
    bool ok = false;
    std::string out = run(cmd.c_str(), &ok);
    if (!ok) {
        error = "GitHub request failed: " + out;
        return nullptr;
    }
    auto j = nlohmann::json::parse(out, nullptr, false);
    if (j.is_discarded()) {
        error = "GitHub sent something that is not JSON.";
        return nullptr;
    }
    error.clear();
    return j;
}

// shortcut: blocks the UI for the request and only gets the newest 100 issues; page with &page= if there are more.
inline void fetch_issues() {
    g_issues.fetched = true;
    auto j = github_get("repos/" ISSUES_REPO "/issues?state=all&per_page=100", g_issues.error);
    if (!j.is_array())
        return;

    g_issues.list.clear();
    for (const auto& it : j) {
        if (it.contains("pull_request")) // the issues endpoint also returns PRs
            continue;
        Issue is;
        is.number = it.value("number", 0);
        is.title = json_str(it, "title");
        is.state = json_str(it, "state");
        is.body = json_str(it, "body");
        is.created_at = json_str(it, "created_at");
        is.comment_count = it.value("comments", 0);
        if (it.contains("user") && it["user"].is_object())
            is.user = json_str(it["user"], "login");
        if (it.contains("labels") && it["labels"].is_array())
            for (const auto& l : it["labels"])
                is.labels.push_back(json_str(l, "name"));
        g_issues.list.push_back(std::move(is));
    }
}

inline void fetch_comments(Issue& is) {
    is.comments_loaded = true;
    auto j = github_get("repos/" ISSUES_REPO "/issues/" + std::to_string(is.number) + "/comments?per_page=100", g_issues.error);
    if (!j.is_array())
        return;
    is.comments.clear();
    for (const auto& c : j) {
        IssueComment ic;
        ic.body = json_str(c, "body");
        ic.created_at = json_str(c, "created_at");
        if (c.contains("user") && c["user"].is_object())
            ic.user = json_str(c["user"], "login");
        is.comments.push_back(std::move(ic));
    }
}

inline void open_issue_in_browser(int number) {
    std::string url = "https://github.com/" ISSUES_REPO "/issues/" + std::to_string(number);
    ImGui::GetPlatformIO().Platform_OpenInShellFn(ImGui::GetCurrentContext(), url.c_str());
}

// Diagnostics zips attached to the issue or its comments, as GitHub attachment links.
inline std::vector<std::string> diagnostics_links(const Issue& is) {
    // Strict on purpose: the URL is passed to curl, so only GitHub attachments with plain file names get through.
    static const std::regex link(R"(https://github\.com/user-attachments/files/[0-9]+/[A-Za-z0-9._-]+\.zip)");
    std::vector<std::string> out;
    auto scan = [&](const std::string& text) {
        for (std::sregex_iterator it(text.begin(), text.end(), link), end; it != end; ++it)
            if (std::find(out.begin(), out.end(), it->str()) == out.end())
                out.push_back(it->str());
    };
    scan(is.body);
    for (const IssueComment& c : is.comments)
        scan(c.body);
    return out;
}

// Downloads an attachment from diagnostics_links() to a temp file and loads it like an imported zip.
// shortcut: blocks the UI while downloading; fine for the few-KB zips diagnose.sh makes.
inline void import_from_issue(const Issue& is, const std::string& url) {
    std::string name = url.substr(url.rfind('/') + 1);
    std::string path = (std::filesystem::temp_directory_path() / ("reskatem-issue-" + std::to_string(is.number) + "-" + name)).string();
    std::string cmd = "curl -fsSL --max-time 60 --max-filesize 200000000 -o '" + path + "' '" + url + "' 2>&1";
    bool ok = false;
    std::string out = run(cmd.c_str(), &ok);
    if (!ok) {
        g_diag.error = "Download failed: " + out;
        return;
    }
    load_diagnostics(path);
    std::remove(path.c_str());
    if (g_diag.loaded && g_diag.zip_path == path)
        g_diag.zip_path = "#" + std::to_string(is.number) + ": " + name;
}
