/// Core markdown parsing utilities for SimpleMarkDown.
/// This module is separate from the Xcode target so it can be unit-tested
/// via Swift Package Manager without requiring AppKit or a test host.

import Foundation

// MARK: - Markdown Converter

/// Converts a Markdown string to HTML. This is the same logic used by
/// the in-app ExportManager, extracted here so it can be covered by tests.
public struct MarkdownConverter {

    public init() {}

    // MARK: - Public API

    public func toHTML(_ text: String) -> String {
        var out: [String] = [
            "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"UTF-8\"></head><body>"
        ]

        let lines     = text.components(separatedBy: "\n")
        var i         = 0
        var inCode    = false
        var codeLang  = ""
        var codeLines: [String] = []
        var tableRows: [String] = []
        var inTable   = false
        var listBuf:  [String] = []
        var listType  = ""

        func flushList() {
            guard !listBuf.isEmpty else { return }
            out.append("<\(listType)>")
            listBuf.forEach { out.append("<li>\($0)</li>") }
            out.append("</\(listType)>")
            listBuf = []; listType = ""
        }

        func flushTable() {
            guard tableRows.count >= 2 else { tableRows.forEach { out.append("<p>\($0)</p>") }; tableRows = []; return }
            out.append("<table><thead><tr>")
            tableRows[0].split(separator: "|", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .forEach { out.append("<th>\(inline($0))</th>") }
            out.append("</tr></thead><tbody>")
            for row in tableRows.dropFirst(2) {
                out.append("<tr>")
                row.split(separator: "|", omittingEmptySubsequences: true)
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .forEach { out.append("<td>\(inline($0))</td>") }
                out.append("</tr>")
            }
            out.append("</tbody></table>")
            tableRows = []
        }

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                flushList(); flushTable()
                if !inCode {
                    inCode = true
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLines = []
                } else {
                    inCode = false
                    let la = codeLang.isEmpty ? "" : " class=\"language-\(esc(codeLang))\""
                    out.append("<pre><code\(la)>\(codeLines.map { esc($0) }.joined(separator: "\n"))</code></pre>")
                    codeLines = []; codeLang = ""
                }
                i += 1; continue
            }
            if inCode { codeLines.append(line); i += 1; continue }

            // Table
            if line.hasPrefix("|") {
                flushList()
                inTable = true
                tableRows.append(line)
                i += 1; continue
            } else if inTable {
                flushTable(); inTable = false
            }

            // HR
            if line == "---" || line == "***" || line == "___" {
                flushList(); out.append("<hr>"); i += 1; continue
            }

            // Heading
            if line.hasPrefix("#") {
                flushList()
                var n = 0
                for ch in line { if ch == "#" { n += 1 } else { break } }
                if n <= 6 && line.count > n && line[line.index(line.startIndex, offsetBy: n)] == " " {
                    out.append("<h\(n)>\(inline(String(line.dropFirst(n + 1))))</h\(n)>")
                    i += 1; continue
                }
            }

            // Blockquote
            if line.hasPrefix("> ") {
                flushList()
                out.append("<blockquote><p>\(inline(String(line.dropFirst(2))))</p></blockquote>")
                i += 1; continue
            }

            // Task list
            if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                flushList()
                out.append("<p><input type=\"checkbox\" checked disabled> \(inline(String(line.dropFirst(6))))</p>")
                i += 1; continue
            }
            if line.hasPrefix("- [ ] ") {
                flushList()
                out.append("<p><input type=\"checkbox\" disabled> \(inline(String(line.dropFirst(6))))</p>")
                i += 1; continue
            }

            // Unordered list
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if listType != "ul" { flushList(); listType = "ul" }
                listBuf.append(inline(String(line.dropFirst(2))))
                i += 1; continue
            }

            // Ordered list
            if let m = line.range(of: "^\\d+\\. ", options: .regularExpression) {
                if listType != "ol" { flushList(); listType = "ol" }
                listBuf.append(inline(String(line[m.upperBound...])))
                i += 1; continue
            }

            flushList()
            if line.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
            out.append("<p>\(inline(line))</p>")
            i += 1
        }
        flushList(); flushTable()
        out.append("</body></html>")
        return out.joined(separator: "\n")
    }

    // MARK: - Inline formatting

    func inline(_ s: String) -> String {
        var t = esc(s)
        t = t.replacingOccurrences(of: "\\*\\*\\*(.+?)\\*\\*\\*", with: "<strong><em>$1</em></strong>", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*",       with: "<strong>$1</strong>",        options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*(.+?)\\*",             with: "<em>$1</em>",               options: .regularExpression)
        t = t.replacingOccurrences(of: "~~(.+?)~~",               with: "<del>$1</del>",             options: .regularExpression)
        t = t.replacingOccurrences(of: "`([^`]+)`",               with: "<code>$1</code>",           options: .regularExpression)
        t = t.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\(([^)]+)\\)", with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[([^\\]]+)\\]\\(([^)]+)\\)",  with: "<a href=\"$2\">$1</a>",      options: .regularExpression)
        return t
    }

    // MARK: - Table alignment parsing

    /// Parses a Markdown table separator row and returns column alignments.
    /// Handles multi-byte characters (emoji) correctly because Swift String.split
    /// operates on Unicode scalars, not UTF-16 code units.
    public func parseTableAlignments(_ separator: String) -> [String] {
        separator.split(separator: "|", omittingEmptySubsequences: false).compactMap { part in
            let t = part.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }
            if t.hasPrefix(":") && t.hasSuffix(":") { return "center" }
            if t.hasSuffix(":")                     { return "right" }
            return "left"
        }
    }

    /// Returns the UTF-16 offset of each pipe character in a table row line.
    /// Emoji that require surrogate pairs (utf16.count == 2) are handled correctly.
    public func pipePositions(in line: String) -> [Int] {
        var positions: [Int] = []
        var offset = 0
        for ch in line {
            if ch == "|" { positions.append(offset) }
            offset += ch.utf16.count
        }
        return positions
    }

    // MARK: - Escape sequences

    /// Returns true if the markdown character at the given position is backslash-escaped.
    public func isEscaped(in text: String, at nsRange: NSRange) -> Bool {
        let nsStr = text as NSString
        guard nsRange.location > 0 else { return false }
        return nsStr.character(at: nsRange.location - 1) == 92 // ASCII code for backslash
    }

    // MARK: - Helpers

    func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
