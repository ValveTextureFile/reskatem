#pragma once

// Draws GitHub-flavoured markdown with plain ImGui widgets and the default font.
// md4c parses; this file only turns its callbacks into ImGui calls.

#include "imgui.h"
#include "md4c.h"
#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace md {

struct Renderer {
    bool line_open = false; // something is on the current line, so the next text goes SameLine
    bool any_block = false; // a block was drawn already, so the next one gets a gap
    int strong = 0, em = 0, del = 0, heading = 0;
    bool code_span = false, in_code_block = false, in_table = false, in_thead = false, in_html = false;
    std::string href;  // link target while inside a link
    std::string code;  // collected code block text
    struct List { bool ordered; unsigned next; };
    std::vector<List> lists;
    std::vector<float> indents;   // what each list item / quote indented by, to undo it
    std::vector<ImVec2> quotes;   // where each quote started, to draw its bar
    int ids = 0;                  // unique ids for widgets inside the text

    void end_line() { line_open = false; }

    void gap() {
        end_line();
        if (any_block)
            ImGui::Dummy(ImVec2(0, ImGui::GetStyle().ItemSpacing.y));
        any_block = true;
    }

    ImU32 text_color() const {
        if (!href.empty())
            return ImGui::GetColorU32(ImGuiCol_TextLink);
        if (em)
            return ImGui::GetColorU32(ImGuiCol_Text, 0.8f);
        return ImGui::GetColorU32(ImGuiCol_Text);
    }

    // One piece that fits on the current line.
    void segment(const char* s, const char* e) {
        if (line_open)
            ImGui::SameLine(0, 0);
        ImDrawList* dl = ImGui::GetWindowDrawList();
        ImVec2 pos = ImGui::GetCursorScreenPos();
        ImVec2 size = ImGui::CalcTextSize(s, e);
        if (code_span)
            dl->AddRectFilled(ImVec2(pos.x - 1, pos.y), ImVec2(pos.x + size.x + 1, pos.y + size.y),
                              ImGui::GetColorU32(ImGuiCol_FrameBg), 2.0f);

        ImU32 col = text_color();
        ImGui::PushStyleColor(ImGuiCol_Text, col);
        ImGui::TextUnformatted(s, e);
        ImGui::PopStyleColor();
        line_open = true;

        // The default font has no bold, so bold is the same text drawn again one pixel over.
        if (strong || heading)
            dl->AddText(ImGui::GetFont(), ImGui::GetFontSize(), ImVec2(pos.x + 1, pos.y), col, s, e);
        if (del)
            dl->AddLine(ImVec2(pos.x, pos.y + size.y * 0.55f), ImVec2(pos.x + size.x, pos.y + size.y * 0.55f), col);

        if (!href.empty() && ImGui::IsItemHovered()) {
            dl->AddLine(ImVec2(pos.x, pos.y + size.y), ImVec2(pos.x + size.x, pos.y + size.y), col);
            ImGui::SetMouseCursor(ImGuiMouseCursor_Hand);
            ImGui::SetTooltip("%s", href.c_str());
            if (ImGui::IsItemClicked())
                open_url(href);
        }
    }

    // Text that may need wrapping across lines.
    void text(const char* s, const char* e) {
        while (s < e) {
            // An open line continues right after the last item, so measure from there to the right edge.
            float right = ImGui::GetCursorScreenPos().x + ImGui::GetContentRegionAvail().x;
            float avail = line_open ? right - ImGui::GetItemRectMax().x : ImGui::GetContentRegionAvail().x;
            const char* te = ImGui::GetFont()->CalcWordWrapPosition(ImGui::GetFontSize(), s, e, avail);
            const char* word_end = s;
            while (word_end < e && *word_end != ' ')
                word_end++;
            // ImGui splits a word that doesn't fit; only do that on an empty line, otherwise move the word down whole.
            if (te == s || (line_open && te < word_end)) {
                if (line_open) {
                    end_line();
                    while (s < e && *s == ' ')
                        s++;
                    continue;
                }
                do te++; while (te < e && (*te & 0xC0) == 0x80); // one character wider than the line: draw it anyway
            }
            segment(s, te);
            if (te < e) { // wrapped
                end_line();
                while (te < e && *te == ' ')
                    te++;
            }
            s = te;
        }
    }

    static void open_url(const std::string& url) {
        // Text comes from strangers on GitHub: only web links, and ImGui opens them without a shell.
        if (url.rfind("https://", 0) == 0 || url.rfind("http://", 0) == 0)
            ImGui::GetPlatformIO().Platform_OpenInShellFn(ImGui::GetCurrentContext(), url.c_str());
    }

    void indent(float w) {
        ImGui::Indent(w);
        indents.push_back(w);
    }
    void unindent() {
        ImGui::Unindent(indents.back());
        indents.pop_back();
    }

    void enter_block(MD_BLOCKTYPE type, void* detail) {
        switch (type) {
        case MD_BLOCK_P:
            if (lists.empty())
                gap();
            break;
        case MD_BLOCK_H:
            gap();
            heading = ((MD_BLOCK_H_DETAIL*)detail)->level;
            break;
        case MD_BLOCK_QUOTE:
            gap();
            quotes.push_back(ImGui::GetCursorScreenPos());
            indent(ImGui::GetStyle().IndentSpacing);
            ImGui::PushStyleColor(ImGuiCol_Text, ImGui::GetColorU32(ImGuiCol_TextDisabled));
            break;
        case MD_BLOCK_UL:
            if (lists.empty())
                gap();
            lists.push_back({false, 0});
            break;
        case MD_BLOCK_OL:
            if (lists.empty())
                gap();
            lists.push_back({true, ((MD_BLOCK_OL_DETAIL*)detail)->start});
            break;
        case MD_BLOCK_LI: {
            end_line();
            auto* li = (MD_BLOCK_LI_DETAIL*)detail;
            float x0 = ImGui::GetCursorPosX();
            if (li->is_task) {
                bool done = li->task_mark != ' ';
                ImGui::PushID(ids++);
                ImGui::BeginDisabled();
                ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(0, 0)); // keep the box as tall as a text line
                ImGui::Checkbox("##task", &done);
                ImGui::PopStyleVar();
                ImGui::EndDisabled();
                ImGui::PopID();
                ImGui::SameLine();
            } else if (lists.back().ordered) {
                ImGui::TextDisabled("%u.", lists.back().next++);
                ImGui::SameLine();
            } else {
                ImGui::Bullet(); // stays on the same line by itself
            }
            // The cursor now sits after the marker; indenting by that much keeps it there and lines wrapped text up under it.
            indent(ImGui::GetCursorPosX() - x0);
            break;
        }
        case MD_BLOCK_HR:
            gap();
            ImGui::Separator();
            break;
        case MD_BLOCK_CODE:
            gap();
            in_code_block = true;
            code.clear();
            break;
        case MD_BLOCK_HTML:
            in_html = true;
            break;
        case MD_BLOCK_TABLE: {
            gap();
            unsigned cols = ((MD_BLOCK_TABLE_DETAIL*)detail)->col_count;
            ImGui::PushID(ids++);
            in_table = cols > 0 && ImGui::BeginTable("##table", (int)cols, ImGuiTableFlags_Borders | ImGuiTableFlags_RowBg | ImGuiTableFlags_SizingStretchProp);
            break;
        }
        case MD_BLOCK_THEAD:
            in_thead = true;
            break;
        case MD_BLOCK_TR:
            if (in_table)
                ImGui::TableNextRow(in_thead ? ImGuiTableRowFlags_Headers : 0);
            break;
        case MD_BLOCK_TH:
        case MD_BLOCK_TD:
            end_line();
            if (in_table)
                ImGui::TableNextColumn();
            if (type == MD_BLOCK_TH)
                strong++;
            break;
        default:
            break;
        }
    }

    void leave_block(MD_BLOCKTYPE type, void*) {
        switch (type) {
        case MD_BLOCK_P:
            end_line();
            break;
        case MD_BLOCK_H: {
            end_line();
            if (heading <= 2)
                ImGui::Separator();
            heading = 0;
            break;
        }
        case MD_BLOCK_QUOTE: {
            end_line();
            ImGui::PopStyleColor();
            unindent();
            ImVec2 top = quotes.back();
            quotes.pop_back();
            float bottom = ImGui::GetCursorScreenPos().y - ImGui::GetStyle().ItemSpacing.y;
            ImGui::GetWindowDrawList()->AddLine(ImVec2(top.x + 3, top.y), ImVec2(top.x + 3, bottom),
                                                ImGui::GetColorU32(ImGuiCol_Separator), 2.0f);
            break;
        }
        case MD_BLOCK_UL:
        case MD_BLOCK_OL:
            lists.pop_back();
            end_line();
            break;
        case MD_BLOCK_LI:
            end_line();
            unindent();
            break;
        case MD_BLOCK_CODE: {
            in_code_block = false;
            while (!code.empty() && code.back() == '\n')
                code.pop_back();
            ImGui::PushID(ids++);
            ImGui::BeginChild("##code", ImVec2(0, 0), ImGuiChildFlags_FrameStyle | ImGuiChildFlags_AutoResizeY,
                              ImGuiWindowFlags_HorizontalScrollbar);
            ImGui::TextUnformatted(code.data(), code.data() + code.size());
            ImGui::EndChild();
            ImGui::PopID();
            end_line();
            break;
        }
        case MD_BLOCK_HTML:
            in_html = false;
            break;
        case MD_BLOCK_TABLE:
            if (in_table)
                ImGui::EndTable();
            in_table = false;
            ImGui::PopID();
            end_line();
            break;
        case MD_BLOCK_THEAD:
            in_thead = false;
            break;
        case MD_BLOCK_TH:
            strong--;
            end_line();
            break;
        case MD_BLOCK_TD:
            end_line();
            break;
        default:
            break;
        }
    }

    void span(MD_SPANTYPE type, void* detail, bool enter) {
        int d = enter ? 1 : -1;
        switch (type) {
        case MD_SPAN_STRONG: strong += d; break;
        case MD_SPAN_EM: em += d; break;
        case MD_SPAN_DEL: del += d; break;
        case MD_SPAN_CODE: code_span = enter; break;
        case MD_SPAN_A:
        case MD_SPAN_IMG: {
            if (!enter) {
                href.clear();
                break;
            }
            const MD_ATTRIBUTE& a = type == MD_SPAN_A ? ((MD_SPAN_A_DETAIL*)detail)->href : ((MD_SPAN_IMG_DETAIL*)detail)->src;
            href.assign(a.text, a.size);
            if (type == MD_SPAN_IMG) {
                const char* label = "[image] ";
                text(label, label + strlen(label));
            }
            break;
        }
        default:
            break;
        }
    }

    // The built-in font is ASCII only; swap common typography for look-alikes instead of drawing '?'.
    static std::string ascii(const char* s, const char* e) {
        static const char* map[][2] = {{"\u2013", "-"}, {"\u2014", "--"}, {"\u2026", "..."}, {"\u2018", "'"}, {"\u2019", "'"},
                                       {"\u201C", "\""}, {"\u201D", "\""}, {"\u00B5", "u"}, {"\u00D7", "x"}, {"\u2192", "->"},
                                       {"\u00A0", " "}, {"\u2022", "*"}};
        std::string out(s, e);
        for (auto& m : map)
            for (size_t p; (p = out.find(m[0])) != std::string::npos;)
                out.replace(p, strlen(m[0]), m[1]);
        return out;
    }

    void on_text(MD_TEXTTYPE type, const char* s, const char* e) {
        std::string clean;
        if (std::any_of(s, e, [](char c) { return (unsigned char)c >= 0x80; })) {
            clean = ascii(s, e);
            s = clean.data();
            e = s + clean.size();
        }
        if (in_code_block) {
            code.append(s, e);
            return;
        }
        switch (type) {
        case MD_TEXT_HTML: // raw HTML (comments, <details>…) is not drawn
            return;
        case MD_TEXT_BR:
            end_line();
            return;
        case MD_TEXT_SOFTBR: {
            static const char space[] = " ";
            text(space, space + 1);
            return;
        }
        case MD_TEXT_NULLCHAR:
            return;
        case MD_TEXT_ENTITY: {
            static const char* map[][2] = {{"&amp;", "&"}, {"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&nbsp;", " "}, {"&#39;", "'"}};
            std::string ent(s, e);
            for (auto& m : map)
                if (ent == m[0]) {
                    text(m[1], m[1] + strlen(m[1]));
                    return;
                }
            break; // unknown: draw it as written
        }
        default:
            break;
        }
        if (!in_html)
            text(s, e);
    }
};

// Draws `src` at the cursor, wrapping to the current content width.
inline void render(const std::string& src) {
    Renderer r;
    MD_PARSER p{};
    p.flags = MD_FLAG_PERMISSIVEAUTOLINKS | MD_FLAG_TABLES | MD_FLAG_STRIKETHROUGH | MD_FLAG_TASKLISTS;
    p.enter_block = [](MD_BLOCKTYPE t, void* d, void* u) { ((Renderer*)u)->enter_block(t, d); return 0; };
    p.leave_block = [](MD_BLOCKTYPE t, void* d, void* u) { ((Renderer*)u)->leave_block(t, d); return 0; };
    p.enter_span = [](MD_SPANTYPE t, void* d, void* u) { ((Renderer*)u)->span(t, d, true); return 0; };
    p.leave_span = [](MD_SPANTYPE t, void* d, void* u) { ((Renderer*)u)->span(t, d, false); return 0; };
    p.text = [](MD_TEXTTYPE t, const MD_CHAR* s, MD_SIZE n, void* u) { ((Renderer*)u)->on_text(t, s, s + n); return 0; };
    ImGui::PushID(&src);
    md_parse(src.data(), (MD_SIZE)src.size(), &p, &r); // md4c always closes what it opens, so pushes stay balanced
    ImGui::PopID();
}

} // namespace md
