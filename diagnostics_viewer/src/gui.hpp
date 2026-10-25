#pragma once

#include "imgui.h"
#include "diagnostics.hpp"
#include "issues.hpp"
#include "markdown.hpp"

const ImVec4 col_ok(0.45f, 0.85f, 0.45f, 1.0f);
const ImVec4 col_bad(1.0f, 0.4f, 0.4f, 1.0f);
const ImVec4 col_warn(1.0f, 0.75f, 0.3f, 1.0f);

// Shows text read-only in a scrollable box that fills the space left.
inline void text_view(const char* id, const std::string& text) {
    ImGui::BeginChild(id, ImVec2(0, 0), ImGuiChildFlags_Borders, ImGuiWindowFlags_HorizontalScrollbar);
    ImGui::TextUnformatted(text.data(), text.data() + text.size());
    ImGui::EndChild();
}

inline bool starts_with(const std::string& s, const char* prefix) {
    return s.rfind(prefix, 0) == 0;
}

// report.txt: "== Section" headers, "OK/MISSING/MISMATCH  label" checks and "Key: value" lines.
inline void report_tab() {
    static bool raw = false;
    const std::string& r = g_diag.report;

    int ok = 0, missing = 0, mismatch = 0;
    for (size_t p = 0; p < r.size(); p = r.find('\n', p) + 1) {
        ok += r.compare(p, 3, "OK ") == 0;
        missing += r.compare(p, 8, "MISSING ") == 0;
        mismatch += r.compare(p, 9, "MISMATCH ") == 0;
        if (r.find('\n', p) == std::string::npos)
            break;
    }
    ImGui::TextColored(col_ok, "%d ok", ok);
    ImGui::SameLine();
    ImGui::TextColored(missing ? col_bad : ImGui::GetStyleColorVec4(ImGuiCol_TextDisabled), "%d missing", missing);
    ImGui::SameLine();
    ImGui::TextColored(mismatch ? col_warn : ImGui::GetStyleColorVec4(ImGuiCol_TextDisabled), "%d mismatched", mismatch);
    ImGui::SameLine(ImGui::GetContentRegionAvail().x - ImGui::CalcTextSize("raw").x - ImGui::GetFrameHeight());
    ImGui::Checkbox("raw", &raw);

    if (raw) {
        text_view("report raw", r);
        return;
    }

    ImGui::BeginChild("report", ImVec2(0, 0), ImGuiChildFlags_Borders);
    if (!g_diag.problems.empty() && ImGui::CollapsingHeader("Known problems", ImGuiTreeNodeFlags_DefaultOpen)) {
        for (const KnownProblem* p : g_diag.problems) {
            ImGui::TextColored(col_bad, "%s", p->title);
            ImGui::Indent();
            ImGui::TextWrapped("%s", p->advice);
            ImGui::Unindent();
        }
        ImGui::Spacing();
    }
    bool any_section = false, in_table = false;
    auto end_table = [&] {
        if (in_table)
            ImGui::EndTable();
        in_table = false;
    };
    size_t p = 0;
    while (p < r.size()) {
        size_t e = r.find('\n', p);
        if (e == std::string::npos)
            e = r.size();
        std::string line = r.substr(p, e - p);
        p = e + 1;
        if (line.empty())
            continue;

        if (starts_with(line, "== ")) {
            end_table();
            any_section = true;
            if (ImGui::CollapsingHeader(line.c_str() + 3, ImGuiTreeNodeFlags_DefaultOpen)) {
                in_table = ImGui::BeginTable(line.c_str(), 2, ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerV);
                ImGui::TableSetupColumn("key", ImGuiTableColumnFlags_WidthFixed, ImGui::CalcTextSize("Free disk space").x);
                ImGui::TableSetupColumn("value", ImGuiTableColumnFlags_WidthStretch);
            }
            continue;
        }
        if (!in_table) { // the title line before any section; otherwise a collapsed section's line
            if (!any_section)
                ImGui::TextDisabled("%s", line.c_str());
            continue;
        }

        ImGui::TableNextRow();
        ImGui::TableNextColumn();
        size_t colon = line.find(": ");
        std::string value;
        if (starts_with(line, "OK ") || starts_with(line, "MISSING ") || starts_with(line, "MISMATCH ")) {
            size_t sp = line.find(' ');
            ImVec4 c = line[0] == 'O' ? col_ok : line[3] == 'S' ? col_bad : col_warn;
            ImGui::TextColored(c, "%s", line.substr(0, sp).c_str());
            value = line.substr(line.find_first_not_of(' ', sp));
        } else if (line[0] != ' ' && colon != std::string::npos && colon < 30) {
            ImGui::TextDisabled("%s", line.substr(0, colon).c_str());
            value = line.substr(colon + 2);
        } else {
            value = line.substr(line.find_first_not_of(' '));
        }
        ImGui::TableNextColumn();
        ImGui::TextWrapped("%s", value.c_str());
    }
    end_table();
    ImGui::EndChild();
}

inline void log_line(const LogFile& log, int i) {
    const char* s = log.text.data() + log.lines[i];
    const char* e = log.text.data() + (i + 1 < (int)log.lines.size() ? log.lines[i + 1] - 1 : log.text.size());
    ImGui::TextDisabled("%5d", i + 1);
    ImGui::SameLine();
    int kind = log_line_kind(s, e);
    if (kind)
        ImGui::PushStyleColor(ImGuiCol_Text, kind == 1 ? col_bad : kind == 2 ? col_warn : ImGui::GetStyleColorVec4(ImGuiCol_TextDisabled));
    ImGui::TextUnformatted(s, e);
    if (kind)
        ImGui::PopStyleColor();
}

inline void logs_tab() {
    static int selected = 0;
    static ImGuiTextFilter filter;
    static bool problems_only = false;
    if (selected >= (int)g_diag.logs.size())
        selected = 0;

    ImGui::BeginChild("log list", ImVec2(ImGui::GetFontSize() * 20, 0), ImGuiChildFlags_Borders | ImGuiChildFlags_ResizeX);
    for (int i = 0; i < (int)g_diag.logs.size(); i++) {
        const LogFile& l = g_diag.logs[i];
        if (ImGui::Selectable(l.name.c_str(), selected == i))
            selected = i;
        ImGui::TextDisabled("  %.1f KB, %d lines", l.text.size() / 1024.0, (int)l.lines.size());
        if (l.errors) {
            ImGui::SameLine();
            ImGui::TextColored(col_bad, "%d errors", l.errors);
        }
    }
    ImGui::EndChild();

    ImGui::SameLine();
    ImGui::BeginGroup();
    if (g_diag.logs.empty()) {
        ImGui::TextDisabled("No logs in this zip.");
        ImGui::EndGroup();
        return;
    }
    const LogFile& log = g_diag.logs[selected];
    filter.Draw("filter", ImGui::GetFontSize() * 19);
    ImGui::SameLine();
    ImGui::Checkbox("errors and warnings only", &problems_only);

    ImGui::BeginChild("log text", ImVec2(0, 0), ImGuiChildFlags_Borders, ImGuiWindowFlags_HorizontalScrollbar);
    if (!filter.IsActive() && !problems_only) {
        ImGuiListClipper clipper; // only draw the lines on screen, logs can be huge
        clipper.Begin((int)log.lines.size());
        while (clipper.Step())
            for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++)
                log_line(log, i);
    } else {
        for (int i = 0; i < (int)log.lines.size(); i++) {
            const char* s = log.text.data() + log.lines[i];
            const char* e = log.text.data() + (i + 1 < (int)log.lines.size() ? log.lines[i + 1] - 1 : log.text.size());
            int kind = problems_only ? log_line_kind(s, e) : 1;
            if ((kind == 1 || kind == 2) && filter.PassFilter(s, e))
                log_line(log, i);
        }
    }
    ImGui::EndChild();
    ImGui::EndGroup();
}

inline void launcher_tab() {
    if (g_diag.launcher.empty()) {
        ImGui::TextDisabled("No launcher.json: the installer had not finished.");
        return;
    }
    auto j = nlohmann::json::parse(g_diag.launcher, nullptr, false);
    if (j.is_discarded() || !j.is_object()) {
        text_view("launcher", g_diag.launcher);
        return;
    }
    if (ImGui::BeginTable("launcher", 2, ImGuiTableFlags_RowBg | ImGuiTableFlags_BordersInnerV | ImGuiTableFlags_ScrollY)) {
        ImGui::TableSetupColumn("key", ImGuiTableColumnFlags_WidthFixed);
        ImGui::TableSetupColumn("value", ImGuiTableColumnFlags_WidthStretch);
        // "/game/build_id" -> "game.build_id"
        auto flat = j.flatten(); // must outlive the loop: items() only references it
        for (auto& [key, v] : flat.items()) {
            std::string k = key.substr(1);
            std::replace(k.begin(), k.end(), '/', '.');
            ImGui::TableNextRow();
            ImGui::TableNextColumn();
            ImGui::TextDisabled("%s", k.c_str());
            ImGui::TableNextColumn();
            std::string val = v.is_string() ? v.get<std::string>() : v.dump();
            ImGui::TextWrapped("%s", val.c_str());
        }
        ImGui::EndTable();
    }
}

// Issues from GitHub: a filterable list on the left, the selected issue and its comments on the right.
inline void issues_tab() {
    static int filter = 0; // 0 all, 1 open, 2 closed (all: issues with diagnostics are often closed)
    static int selected = -1; // issue number

    if (!g_issues.fetched)
        fetch_issues();

    if (ImGui::Button("refresh"))
        fetch_issues();
    ImGui::SameLine();
    ImGui::RadioButton("all", &filter, 0);
    ImGui::SameLine();
    ImGui::RadioButton("open", &filter, 1);
    ImGui::SameLine();
    ImGui::RadioButton("closed", &filter, 2);
    ImGui::SameLine();
    ImGui::TextDisabled("%d issues in " ISSUES_REPO, (int)g_issues.list.size());
    if (!g_issues.error.empty())
        ImGui::TextColored(col_bad, "%s", g_issues.error.c_str());

    Issue* current = nullptr;
    ImGui::BeginChild("issue list", ImVec2(ImGui::GetFontSize() * 27, 0), ImGuiChildFlags_Borders | ImGuiChildFlags_ResizeX);
    for (Issue& is : g_issues.list) {
        if ((filter == 1 && is.state != "open") || (filter == 2 && is.state != "closed"))
            continue;
        std::string label = "#" + std::to_string(is.number) + " " + is.title;
        if (is.state != "open")
            ImGui::PushStyleColor(ImGuiCol_Text, ImGui::GetStyleColorVec4(ImGuiCol_TextDisabled));
        if (ImGui::Selectable(label.c_str(), selected == is.number))
            selected = is.number;
        if (is.state != "open")
            ImGui::PopStyleColor();
        if (selected == is.number)
            current = &is;
    }
    ImGui::EndChild();

    ImGui::SameLine();
    ImGui::BeginChild("issue", ImVec2(0, 0), ImGuiChildFlags_Borders);
    if (!current) {
        ImGui::TextDisabled("Select an issue.");
    } else {
        if (!current->comments_loaded && current->comment_count > 0)
            fetch_comments(*current);

        ImGui::PushTextWrapPos(0.0f);
        ImGui::Text("#%d %s", current->number, current->title.c_str());
        ImGui::PopTextWrapPos();
        ImGui::TextColored(current->state == "open" ? col_ok : ImGui::GetStyleColorVec4(ImGuiCol_TextDisabled), "%s", current->state.c_str());
        ImGui::SameLine();
        ImGui::TextDisabled("by %s on %s", current->user.c_str(), current->created_at.substr(0, 10).c_str());
        for (const std::string& l : current->labels) {
            ImGui::SameLine();
            ImGui::TextDisabled("[%s]", l.c_str());
        }
        ImGui::SameLine();
        if (ImGui::SmallButton("open in browser"))
            open_issue_in_browser(current->number);
        std::vector<std::string> zips = diagnostics_links(*current);
        if (zips.empty())
            ImGui::TextColored(ImColor(255,0,0),"no diagnostics zip attached");
        // Own row, full size: on the title row they got clipped off the right edge.
        for (size_t i = 0; i < zips.size(); i++) {
            if (i > 0)
                ImGui::SameLine();
            std::string label = zips.size() == 1 ? "import diagnostics" : "import diagnostics " + std::to_string(i + 1);
            if (ImGui::Button(label.c_str()))
                import_from_issue(*current, zips[i]);
            ImGui::SetItemTooltip("%s", zips[i].substr(zips[i].rfind('/') + 1).c_str());
        }
        ImGui::Separator();
        if (current->body.empty())
            ImGui::TextDisabled("(no description)");
        else
            md::render(current->body);

        for (const IssueComment& c : current->comments) {
            ImGui::Spacing();
            ImGui::SeparatorText((c.user + " on " + c.created_at.substr(0, 10)).c_str());
            md::render(c.body);
        }
    }
    ImGui::EndChild();
}

inline void gui() {
    // Fill the whole OS window: no title bar, no moving/resizing, no rounded edges.
    const ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(vp->WorkPos);
    ImGui::SetNextWindowSize(vp->WorkSize);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
    ImGui::Begin("Diagnostics", nullptr,
                 ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove |
                 ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoBringToFrontOnFocus);
    ImGui::PopStyleVar();

    // title
    ImGui::Text("reskatem diagnostics viewer v0.0.1 | ValveTextureFile");

    // import diagnostics
    if (ImGui::Button("import diagnostics zip")) {
        std::string path = pick_zip();
        if (!path.empty())
            load_diagnostics(path);
    }
    ImGui::SameLine();
    ImGui::TextDisabled("%s", g_diag.loaded ? g_diag.zip_path.c_str() : "no zip loaded (or drop one on the window)");
    if (!g_diag.error.empty())
        ImGui::TextColored(col_bad, "%s", g_diag.error.c_str());

    ImGui::SeparatorText("view");

    if (!g_diag.loaded)
        ImGui::TextDisabled("Import a ReSkate-for-Mac-diagnostics-*.zip to view it.");

    // Jump to the report whenever a different zip is loaded.
    static std::string shown_zip;
    ImGuiTabItemFlags report_flags = g_diag.loaded && g_diag.zip_path != shown_zip ? ImGuiTabItemFlags_SetSelected : 0;
    shown_zip = g_diag.zip_path;

    if (ImGui::BeginTabBar("tabs")) {
        if (g_diag.loaded && ImGui::BeginTabItem("Report", nullptr, report_flags)) {
            report_tab();
            ImGui::EndTabItem();
        }
        if (g_diag.loaded && ImGui::BeginTabItem("Logs")) {
            logs_tab();
            ImGui::EndTabItem();
        }
        if (g_diag.loaded && ImGui::BeginTabItem("Launcher")) {
            launcher_tab();
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem("Issues")) {
            issues_tab();
            ImGui::EndTabItem();
        }
        ImGui::EndTabBar();
    }

    ImGui::End();
}
