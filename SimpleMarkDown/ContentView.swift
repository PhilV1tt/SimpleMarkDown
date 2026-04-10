//
//  ContentView.swift
//  SimpleMarkDown
//

import SwiftUI
import AppKit
internal import UniformTypeIdentifiers

// MARK: - Insert Action

enum InsertAction: Equatable {
    case bold, italic, strikethrough, inlineCode, link
    case boldUnderscore, italicUnderscore
    case highlight, comment
    case inlineMath, mathBlock
    case wikilink, tag, footnote
    case callout(String)
    case heading(Int)
    case table, codeBlock, image
    case copyRichText
}

// MARK: - Notification Names

extension Notification.Name {
    static let printDocument = Notification.Name("SMD_PrintDocument")
}

// MARK: - Main View

struct ContentView: View {
    @State private var text: String = "# Hello!\n\n**bold**, *italic*, ***bold italic***, ~~strikethrough~~, `code`\n\n## Tasks\n\n- [x] Done\n- [ ] Todo\n\n## Table\n\n| Name     | Role    | Score |\n| :------- | :-----: | ----: |\n| Alice    | Admin   | 99    |\n| Bob      | User    | 42    |\n\n## Image\n\n![Swift logo](https://swift.org/assets/images/swift.svg)\n\n## Link\n\n[Apple](https://apple.com)\n\n---\n\n> Blockquote\n\n```\nfunc hello() {\n    print(\"world\")\n}\n```"
    @State private var currentFileURL: URL? = nil
    @State private var isModified = false
    @State private var wordCount = 0
    @State private var charCount = 0
    @State private var lineCount = 0
    @State private var showFindReplace = false
    @State private var showOutline = false
    @State private var showQuickInsert = false
    @State private var isFocusMode = false
    @State private var isTypewriterMode = false
    @State private var insertAction: InsertAction? = nil

    @AppStorage("appearance")       private var appearance: String       = "system"
    @AppStorage("fontSize")         private var fontSize: Double         = 16
    @AppStorage("fontFamily")       private var fontFamily: String       = "system"
    @AppStorage("lineWidth")        private var lineWidth: Double        = 0
    @AppStorage("showLineNumbers")  private var showLineNumbers: Bool    = false
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 0
    @AppStorage("spellCheck")       private var spellCheckEnabled: Bool  = false
    @AppStorage("syntaxTheme")      private var syntaxTheme: String      = "default"

    @State private var autoSaveTimer: Timer? = nil

    private var windowTitle: String {
        (currentFileURL?.lastPathComponent ?? "Untitled") + (isModified ? " •" : "")
    }

    var body: some View {
        HStack(spacing: 0) {
            if showOutline && !isFocusMode {
                OutlineSidebarView(text: text)
                    .frame(width: 200)
                Divider()
            }

            VStack(spacing: 0) {
                if showFindReplace && !isFocusMode {
                    FindReplaceView(text: $text, isVisible: $showFindReplace)
                }
                if showQuickInsert && !isFocusMode {
                    QuickInsertBar { insertAction = $0 }
                }
                MarkdownEditorView(
                    text: $text,
                    isModified: $isModified,
                    insertAction: $insertAction,
                    isTypewriterMode: isTypewriterMode,
                    showLineNumbers: showLineNumbers,
                    spellCheckEnabled: spellCheckEnabled,
                    lineWidth: lineWidth,
                    appearance: appearance
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !isFocusMode {
                    StatusBarView(wordCount: wordCount, charCount: charCount, lineCount: lineCount)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .navigationTitle(windowTitle)
        .toolbar {
            if !isFocusMode {
                ToolbarItemGroup(placement: .navigation) {
                    Button("New")  { newFile() }
                    Button("Open") { openFile() }
                    Button("Save") { saveFile() }
                }
                ToolbarItemGroup(placement: .automatic) {
                    Button { showOutline.toggle() } label: {
                        Image(systemName: "list.bullet.indent")
                    }.help("Toggle Outline (⌘⇧L)")

                    Button { showQuickInsert.toggle() } label: {
                        Image(systemName: "plus.square")
                    }.help("Quick Insert Toolbar")

                    Button { isTypewriterMode.toggle() } label: {
                        Image(systemName: isTypewriterMode ? "arrow.up.and.down.text.horizontal" : "text.cursor")
                    }.help("Typewriter Mode")
                }
            }
        }
        .background(Group {
            // Keyboard shortcuts
            Button("") { openFile() }.keyboardShortcut("o", modifiers: .command).opacity(0)
            Button("") { saveFile() }.keyboardShortcut("s", modifiers: .command).opacity(0)
            Button("") { saveFileAs() }.keyboardShortcut("s", modifiers: [.command, .shift]).opacity(0)
            Button("") { showFindReplace.toggle() }.keyboardShortcut("f", modifiers: .command).opacity(0)
            Button("") { printDocument() }.keyboardShortcut("p", modifiers: .command).opacity(0)
            Button("") { exportHTML() }.keyboardShortcut("e", modifiers: .command).opacity(0)
            Button("") { isFocusMode.toggle() }.keyboardShortcut("f", modifiers: [.command, .control]).opacity(0)
            Button("") { showOutline.toggle() }.keyboardShortcut("l", modifiers: [.command, .shift]).opacity(0)
            Button("") { insertAction = .bold }.keyboardShortcut("b", modifiers: .command).opacity(0)
            Button("") { insertAction = .italic }.keyboardShortcut("i", modifiers: .command).opacity(0)
            Button("") { insertAction = .link }.keyboardShortcut("k", modifiers: .command).opacity(0)
            Button("") { insertAction = .strikethrough }.keyboardShortcut("x", modifiers: [.command, .shift]).opacity(0)
            Button("") { insertAction = .inlineCode }.keyboardShortcut("c", modifiers: [.command, .shift]).opacity(0)
            Button("") { insertAction = .copyRichText }.keyboardShortcut("c", modifiers: [.command, .option]).opacity(0)
            Button("") { insertAction = .heading(1) }.keyboardShortcut("1", modifiers: .command).opacity(0)
            Button("") { insertAction = .heading(2) }.keyboardShortcut("2", modifiers: .command).opacity(0)
            Button("") { insertAction = .heading(3) }.keyboardShortcut("3", modifiers: .command).opacity(0)
        })
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: nil, perform: handleDrop)
        .onAppear {
            applyAppearance(appearance)
            updateCounts()
        }
        .onChange(of: appearance)       { _, new in applyAppearance(new) }
        .onChange(of: text)             { _, _   in updateCounts(); scheduleAutoSave() }
        .onChange(of: autoSaveInterval) { _, _   in resetAutoSaveTimer() }
    }

    // MARK: - File Operations

    private func newFile() {
        if isModified {
            let alert = NSAlert()
            alert.messageText = "Save changes?"
            alert.informativeText = "Do you want to save changes to \"\(currentFileURL?.lastPathComponent ?? "Untitled")\"?"
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn { saveFile() }
            else if response == .alertThirdButtonReturn { return }
        }
        text = ""
        currentFileURL = nil
        isModified = false
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            text = try String(contentsOf: url, encoding: .utf8)
            currentFileURL = url
            isModified = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            showError("Could not open file", error: error)
        }
    }

    func saveFile() {
        if let url = currentFileURL {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                isModified = false
            } catch {
                showError("Could not save file", error: error)
            }
        } else {
            saveFileAs()
        }
    }

    func saveFileAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Untitled.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            currentFileURL = url
            isModified = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        } catch {
            showError("Could not save file", error: error)
        }
    }

    private func showError(_ message: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }

    // MARK: - Auto-save (#13)

    private func scheduleAutoSave() {
        guard autoSaveInterval > 0, currentFileURL != nil, isModified else { return }
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveInterval, repeats: false) { _ in
            if isModified { saveFile() }
        }
    }

    private func resetAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }

    // MARK: - Word Count (#10)

    private func updateCounts() {
        wordCount = text.isEmpty ? 0 : text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        charCount = text.count
        lineCount = text.isEmpty ? 1 : text.components(separatedBy: "\n").count
    }

    // MARK: - Print (#18)

    private func printDocument() {
        NotificationCenter.default.post(name: .printDocument, object: nil)
    }

    // MARK: - Export to HTML (#12)

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.html]
        panel.nameFieldStringValue = (currentFileURL?.deletingPathExtension().lastPathComponent ?? "export") + ".html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ExportManager.toHTML(markdown: text).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            showError("Could not export HTML", error: error)
        }
    }

    // MARK: - Appearance

    private func applyAppearance(_ value: String) {
        switch value {
        case "light", "paper": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":           NSApp.appearance = NSAppearance(named: .darkAqua)
        default:               NSApp.appearance = nil  // follows system
        }
    }

    // MARK: - Drag & Drop (#15, #24)

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                } else {
                    url = nil
                }
                guard let fileURL = url else { return }
                DispatchQueue.main.async {
                    do {
                        text = try String(contentsOf: fileURL, encoding: .utf8)
                        currentFileURL = fileURL
                        isModified = false
                        NSDocumentController.shared.noteNewRecentDocumentURL(fileURL)
                    } catch {
                        showError("Could not open dropped file", error: error)
                    }
                }
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                let name: String
                if let url = item as? URL { name = url.lastPathComponent }
                else { name = "image" }
                DispatchQueue.main.async {
                    insertAction = .image
                    text += "\n![Image](\(name))\n"
                    isModified = true
                }
            }
            return true
        }
        return false
    }
}

// MARK: - Status Bar (#10)

struct StatusBarView: View {
    let wordCount: Int
    let charCount: Int
    let lineCount: Int

    var body: some View {
        HStack(spacing: 16) {
            Text("\(wordCount) word\(wordCount == 1 ? "" : "s")")
            Text("\(charCount) char\(charCount == 1 ? "" : "s")")
            Text("\(lineCount) line\(lineCount == 1 ? "" : "s")")
            if wordCount > 0 {
                Text("~\(max(1, wordCount / 200)) min read")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

// MARK: - Find & Replace (#11)

struct FindReplaceView: View {
    @Binding var text: String
    @Binding var isVisible: Bool
    @State private var findText = ""
    @State private var replaceText = ""
    @State private var caseSensitive = false
    @State private var useRegex = false
    @FocusState private var findFocused: Bool

    private var matchCount: Int {
        guard !findText.isEmpty else { return 0 }
        var opts: String.CompareOptions = []
        if !caseSensitive { opts.insert(.caseInsensitive) }
        if useRegex       { opts.insert(.regularExpression) }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: findText, options: opts, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<text.endIndex
            if searchRange.lowerBound >= text.endIndex { break }
        }
        return count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Find field
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                    TextField("Find", text: $findText)
                        .textFieldStyle(.plain)
                        .focused($findFocused)
                        .onSubmit { findNext() }
                    if !findText.isEmpty {
                        Button { findText = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                .frame(minWidth: 140)

                // Replace field
                HStack {
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary).font(.caption)
                    TextField("Replace", text: $replaceText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                .frame(minWidth: 120)

                Toggle("Aa", isOn: $caseSensitive).toggleStyle(.button).help("Case Sensitive")
                Toggle(".*", isOn: $useRegex).toggleStyle(.button).help("Regular Expression")

                Divider().frame(height: 20)

                Button("Prev")    { findPrev() }.disabled(findText.isEmpty)
                Button("Next")    { findNext() }.disabled(findText.isEmpty)
                Button("Replace") { replaceOne() }.disabled(findText.isEmpty)
                Button("All")     { replaceAll() }.disabled(findText.isEmpty)

                if matchCount > 0 {
                    Text("\(matchCount) found").foregroundStyle(.secondary).font(.caption)
                } else if !findText.isEmpty {
                    Text("No results").foregroundStyle(.red).font(.caption)
                }

                Spacer()

                Button { isVisible = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
        }
        .background(.bar)
        .onAppear { findFocused = true }
    }

    private func compareOptions() -> String.CompareOptions {
        var opts: String.CompareOptions = []
        if !caseSensitive { opts.insert(.caseInsensitive) }
        if useRegex       { opts.insert(.regularExpression) }
        return opts
    }

    private func findNext() {
        guard !findText.isEmpty else { return }
        // Basic find: just trigger replace field focus — real highlighting done via NSTextFinder
    }
    private func findPrev() { }

    private func replaceOne() {
        guard !findText.isEmpty else { return }
        let opts = compareOptions()
        guard let range = text.range(of: findText, options: opts) else { return }
        text.replaceSubrange(range, with: replaceText)
    }

    private func replaceAll() {
        guard !findText.isEmpty else { return }
        let opts = compareOptions()
        text = text.replacingOccurrences(of: findText, with: replaceText, options: opts)
    }
}

// MARK: - Quick Insert Toolbar (#26)

struct QuickInsertBar: View {
    let onInsert: (InsertAction) -> Void

    private let items: [(String, String, InsertAction)] = [
        ("H1", "1.circle", .heading(1)),
        ("H2", "2.circle", .heading(2)),
        ("H3", "3.circle", .heading(3)),
        ("Bold", "bold", .bold),
        ("Italic", "italic", .italic),
        ("~~", "strikethrough", .strikethrough),
        ("==Highlight==", "highlighter", .highlight),
        ("%%Comment%%", "eye.slash", .comment),
        ("`Code`", "chevron.left.forwardslash.chevron.right", .inlineCode),
        ("$Math$", "function", .inlineMath),
        ("$$Block$$", "sum", .mathBlock),
        ("[[Wiki]]", "link.badge.plus", .wikilink),
        ("#Tag", "tag", .tag),
        ("[^fn]", "textformat.superscript", .footnote),
        ("Callout", "exclamationmark.bubble", .callout("NOTE")),
        ("Link", "link", .link),
        ("Table", "tablecells", .table),
        ("Block", "curlybraces", .codeBlock),
        ("Image", "photo", .image),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(items, id: \.0) { label, icon, action in
                    Button { onInsert(action) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: icon).font(.caption2)
                            Text(label).font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 4)
        .background(.bar)
    }
}

// MARK: - Outline Sidebar (#19)

struct OutlineSidebarView: View {
    let text: String

    struct HeadingEntry: Identifiable {
        let id = UUID()
        let level: Int
        let title: String
    }

    private var headings: [HeadingEntry] {
        let prefixes: [(String, Int)] = [
            ("###### ", 6), ("##### ", 5), ("#### ", 4), ("### ", 3), ("## ", 2), ("# ", 1)
        ]
        return text.components(separatedBy: "\n").compactMap { line in
            for (prefix, level) in prefixes.reversed() {
                if line.hasPrefix(prefix) {
                    return HeadingEntry(level: level, title: String(line.dropFirst(prefix.count)))
                }
            }
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Outline")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            Divider()
            if headings.isEmpty {
                Text("No headings").foregroundStyle(.secondary).font(.caption).padding(12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(headings) { h in
                            Text(h.title)
                                .font(.system(size: max(11, CGFloat(14 - h.level))))
                                .foregroundStyle(h.level <= 2 ? Color.primary : Color.secondary)
                                .padding(.leading, 8 + CGFloat((h.level - 1) * 12))
                                .padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Export Manager (#12)

struct ExportManager {

    static func toHTML(markdown text: String) -> String {
        let style = """
        body{font-family:-apple-system,sans-serif;max-width:800px;margin:40px auto;padding:0 20px;line-height:1.6}
        code{background:#f4f4f4;padding:2px 6px;border-radius:3px;font-family:monospace}
        pre{background:#f4f4f4;padding:16px;border-radius:6px;overflow:auto}
        pre code{background:none;padding:0}
        table{border-collapse:collapse;width:100%}
        th,td{border:1px solid #ddd;padding:8px 12px}
        th{background:#f0f0f0}
        blockquote{border-left:4px solid #ddd;margin:0;padding-left:16px;color:#666}
        img{max-width:100%}
        del{text-decoration:line-through}
        input[type=checkbox]{margin-right:4px}
        hr{border:none;border-top:1px solid #ddd}
        """
        var out = ["<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"UTF-8\">",
                   "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
                   "<style>\(style)</style></head><body>"]

        var lines = text.components(separatedBy: "\n")
        var i = 0
        var inCodeBlock = false
        var codeLang = ""
        var codeLines: [String] = []
        var tableRows: [String] = []
        var inTable = false
        var listBuffer: [String] = []
        var listType = ""  // "ul" or "ol"

        func flushList() {
            guard !listBuffer.isEmpty else { return }
            out.append("<\(listType)>")
            listBuffer.forEach { out.append("<li>\($0)</li>") }
            out.append("</\(listType)>")
            listBuffer = []; listType = ""
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
                if !inCodeBlock {
                    inCodeBlock = true
                    codeLang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLines = []
                } else {
                    inCodeBlock = false
                    let langAttr = codeLang.isEmpty ? "" : " class=\"language-\(esc(codeLang))\""
                    out.append("<pre><code\(langAttr)>\(codeLines.map { esc($0) }.joined(separator: "\n"))</code></pre>")
                    codeLines = []; codeLang = ""
                }
                i += 1; continue
            }
            if inCodeBlock { codeLines.append(line); i += 1; continue }

            // Table
            if line.hasPrefix("|") {
                flushList()
                if !inTable { inTable = true }
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
                    let title = String(line.dropFirst(n + 1))
                    out.append("<h\(n)>\(inline(title))</h\(n)>")
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
                listBuffer.append(inline(String(line.dropFirst(2))))
                i += 1; continue
            }

            // Ordered list
            if let m = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                if listType != "ol" { flushList(); listType = "ol" }
                listBuffer.append(inline(String(line[m.upperBound...])))
                i += 1; continue
            }

            flushList()

            // Empty line
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1; continue
            }

            out.append("<p>\(inline(line))</p>")
            i += 1
        }
        flushList(); flushTable()

        out.append("</body></html>")
        return out.joined(separator: "\n")
    }

    private static func inline(_ s: String) -> String {
        var t = esc(s)
        t = t.replacingOccurrences(of: #"\\\*"#, with: "&#42;", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\*\*\*(.+?)\*\*\*"#, with: "<strong><em>$1</em></strong>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#,     with: "<strong>$1</strong>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\*(.+?)\*"#,         with: "<em>$1</em>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"~~(.+?)~~"#,         with: "<del>$1</del>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"`([^`]+)`"#,         with: "<code>$1</code>", options: .regularExpression)
        t = t.replacingOccurrences(of: #"!\[([^\]]*)\]\(([^)]+)\)"#, with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]+)\]\(([^)]+)\)"#,  with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return t
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Settings View (#25, #28, #29)

struct SettingsView: View {
    @AppStorage("appearance")       private var appearance: String       = "system"
    @AppStorage("fontSize")         private var fontSize: Double         = 16
    @AppStorage("fontFamily")       private var fontFamily: String       = "system"
    @AppStorage("lineWidth")        private var lineWidth: Double        = 0
    @AppStorage("showLineNumbers")  private var showLineNumbers: Bool    = false
    @AppStorage("autoSaveInterval") private var autoSaveInterval: Double = 0
    @AppStorage("spellCheck")       private var spellCheckEnabled: Bool  = false
    @AppStorage("syntaxTheme")      private var syntaxTheme: String      = "default"

    var body: some View {
        Form {
            // ── Appearance ──────────────────────────────────────────────
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("Paper").tag("paper")
                }
                .pickerStyle(.segmented)

                Picker("Syntax Colors", selection: $syntaxTheme) {
                    Text("Default").tag("default")
                    Text("Solarized").tag("solarized")
                    Text("Monochrome").tag("mono")
                    Text("Ocean").tag("ocean")
                }
                .pickerStyle(.segmented)
            }

            // ── Editor ───────────────────────────────────────────────────
            Section("Editor") {
                HStack {
                    Text("Font size")
                    Slider(value: $fontSize, in: 12...28, step: 1)
                    Text("\(Int(fontSize))pt")
                        .monospacedDigit()
                        .frame(width: 36)
                }

                Picker("Font", selection: $fontFamily) {
                    Text("System").tag("system")
                    Text("Monospaced").tag("mono")
                    Text("Serif").tag("serif")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Max line width")
                    Slider(value: $lineWidth, in: 0...1200, step: 40)
                    Text(lineWidth == 0 ? "None" : "\(Int(lineWidth))")
                        .monospacedDigit()
                        .frame(width: 40)
                }

                Toggle("Show line numbers", isOn: $showLineNumbers)
                Toggle("Spell check",       isOn: $spellCheckEnabled)
            }

            // ── Auto-save ────────────────────────────────────────────────
            Section("Auto-save") {
                Picker("Interval", selection: $autoSaveInterval) {
                    Text("Off").tag(0.0)
                    Text("30 s").tag(30.0)
                    Text("1 min").tag(60.0)
                    Text("5 min").tag(300.0)
                }
                .pickerStyle(.segmented)
            }

            // ── Reset ────────────────────────────────────────────────────
            Section {
                Button("Reset to defaults") {
                    appearance = "system"; fontSize = 16; fontFamily = "system"
                    lineWidth = 0; showLineNumbers = false; autoSaveInterval = 0
                    spellCheckEnabled = false; syntaxTheme = "default"
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .padding()
    }
}

// MARK: - NSViewRepresentable (#3, #16, #21, #22, #23, #24, #29)

// Warm cream color for paper mode — defined once, used in both the view and the formatter
extension NSColor {
    static let paperBackground = NSColor(red: 0.990, green: 0.968, blue: 0.900, alpha: 1)
    static let paperCodeBg     = NSColor(red: 0.940, green: 0.918, blue: 0.850, alpha: 1)
    static let paperText       = NSColor(red: 0.14,  green: 0.11,  blue: 0.08,  alpha: 1)
}

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isModified: Bool
    @Binding var insertAction: InsertAction?
    let isTypewriterMode: Bool
    let showLineNumbers: Bool
    let spellCheckEnabled: Bool
    let lineWidth: Double
    let appearance: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let tv = scrollView.documentView as? NSTextView else { return scrollView }

        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled  = false
        tv.isAutomaticDashSubstitutionEnabled   = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 60, height: 40)
        // Enable native find panel (#11)
        tv.usesFindPanel = true
        tv.isContinuousSpellCheckingEnabled = spellCheckEnabled
        // Accept image drops (#24)
        tv.registerForDraggedTypes([.fileURL, .tiff, .png])

        tv.string = text
        MarkdownFormatter.apply(to: tv)

        // Listen for print notification (#18)
        context.coordinator.printObserver = NotificationCenter.default.addObserver(
            forName: .printDocument, object: nil, queue: .main
        ) { [weak tv] _ in
            guard let tv else { return }
            let op = NSPrintOperation(view: tv)
            op.run()
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }

        // Apply background color for paper / dark modes
        let bg: NSColor = appearance == "paper" ? .paperBackground : .textBackgroundColor
        if tv.backgroundColor != bg {
            tv.backgroundColor        = bg
            scrollView.backgroundColor = bg
            scrollView.contentView.backgroundColor = bg
        }

        tv.isContinuousSpellCheckingEnabled = spellCheckEnabled

        // Line number ruler (#22)
        if showLineNumbers {
            if !(scrollView.verticalRulerView is LineNumberRulerView) {
                let ruler = LineNumberRulerView(scrollView: scrollView, textView: tv)
                scrollView.verticalRulerView = ruler
                scrollView.hasVerticalRuler = true
                scrollView.rulersVisible = true
            }
        } else if scrollView.hasVerticalRuler {
            scrollView.hasVerticalRuler = false
            scrollView.rulersVisible = false
        }

        // Apply max line width (#28) via textContainerInset
        if lineWidth > 0 {
            let windowWidth = scrollView.frame.width
            let inset = max(20, (windowWidth - lineWidth) / 2)
            if tv.textContainerInset.width != inset {
                tv.textContainerInset = NSSize(width: inset, height: 40)
            }
        } else if tv.textContainerInset.width != 60 {
            tv.textContainerInset = NSSize(width: 60, height: 40)
        }

        // Reformat if text or settings changed
        let needsReformat = tv.string != text
            || context.coordinator.lastFontSize   != MarkdownFormatter.fontSize
            || context.coordinator.lastFontFamily != MarkdownFormatter.fontFamily
            || context.coordinator.lastTheme      != MarkdownFormatter.syntaxTheme

        if needsReformat {
            if tv.string != text { tv.string = text }
            context.coordinator.lastFontSize   = MarkdownFormatter.fontSize
            context.coordinator.lastFontFamily = MarkdownFormatter.fontFamily
            context.coordinator.lastTheme      = MarkdownFormatter.syntaxTheme
            MarkdownFormatter.apply(to: tv)
        }

        // Handle insert actions (#16, #26)
        if let action = insertAction {
            context.coordinator.handleInsert(action, in: tv)
            DispatchQueue.main.async { insertAction = nil }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        private var isFormatting = false
        private var needsFormat  = false   // fix #3: never drop keystrokes
        var lastFontSize:   Double = 16
        var lastFontFamily: String = "system"
        var lastTheme:      String = "default"
        var printObserver: Any?

        init(_ p: MarkdownEditorView) { parent = p }

        deinit {
            if let obs = printObserver { NotificationCenter.default.removeObserver(obs) }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            parent.isModified = true
            // fromTextChange: true — dropped format passes get re-queued (#3)
            applyIfNeeded(tv, fromTextChange: true)
            if parent.isTypewriterMode { scrollToCenter(tv) }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            // fromTextChange: false — if we are already formatting (e.g. because
            // apply() itself triggered this delegate call), do NOT queue a re-run
            // or we create an infinite loop: apply → selection change → apply → …
            applyIfNeeded(tv, fromTextChange: false)
            if parent.isTypewriterMode { scrollToCenter(tv) }
            tv.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        // Fix #3: queue a follow-up pass when a text-change arrives mid-format.
        // Selection-change calls never queue a re-run (fromTextChange: false) to
        // avoid the apply() → textViewDidChangeSelection → apply() infinite loop.
        private func applyIfNeeded(_ tv: NSTextView, fromTextChange: Bool) {
            guard !isFormatting else {
                if fromTextChange { needsFormat = true }
                return
            }
            isFormatting = true
            MarkdownFormatter.apply(to: tv)
            isFormatting = false
            if needsFormat {
                needsFormat = false
                applyIfNeeded(tv, fromTextChange: true)
            }
        }

        // MARK: Smart list continuation (#23)

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSTextView.insertNewline(_:)) {
                return handleReturn(textView)
            }
            return false
        }

        private func handleReturn(_ tv: NSTextView) -> Bool {
            let nsStr = tv.string as NSString
            let cursor = tv.selectedRange().location
            let paraRange = nsStr.lineRange(for: NSRange(location: cursor, length: 0))
            let currentLine = nsStr.substring(with: NSRange(location: paraRange.location,
                                                              length: paraRange.length))
                                   .trimmingCharacters(in: .newlines)

            // Unordered list (task or bullet)
            let ulPrefixes = ["- [x] ", "- [X] ", "- [ ] ", "- ", "* ", "+ "]
            for prefix in ulPrefixes {
                if currentLine.hasPrefix(prefix) {
                    let content = String(currentLine.dropFirst(prefix.count))
                    if content.isEmpty {
                        // Exit list: replace current line with empty line
                        tv.replaceCharacters(in: NSRange(location: paraRange.location, length: paraRange.length - 1), with: "")
                        return true
                    }
                    let nextPrefix = (prefix == "- [x] " || prefix == "- [X] ") ? "- [ ] " : prefix
                    tv.insertText("\n" + nextPrefix, replacementRange: tv.selectedRange())
                    return true
                }
            }

            // Ordered list
            if let m = currentLine.range(of: #"^(\d+)[.)]\s"#, options: .regularExpression) {
                let numStr = String(currentLine[m].dropLast(2))
                if let num = Int(numStr) {
                    let content = String(currentLine.dropFirst(numStr.count + 2))
                    if content.isEmpty {
                        tv.replaceCharacters(in: NSRange(location: paraRange.location, length: paraRange.length - 1), with: "")
                        return true
                    }
                    tv.insertText("\n\(num + 1). ", replacementRange: tv.selectedRange())
                    return true
                }
            }
            return false
        }

        // MARK: Formatting shortcuts & quick insert (#16, #26)

        func handleInsert(_ action: InsertAction, in tv: NSTextView) {
            let sel = tv.selectedRange()
            let selected = (tv.string as NSString).substring(with: sel)

            switch action {
            case .bold:
                toggle(tv: tv, sel: sel, selected: selected, open: "**", close: "**", placeholder: "bold text")
            case .italic:
                toggle(tv: tv, sel: sel, selected: selected, open: "*", close: "*", placeholder: "italic text")
            case .strikethrough:
                toggle(tv: tv, sel: sel, selected: selected, open: "~~", close: "~~", placeholder: "text")
            case .inlineCode:
                toggle(tv: tv, sel: sel, selected: selected, open: "`", close: "`", placeholder: "code")
            case .link:
                let text = selected.isEmpty ? "link text" : selected
                tv.insertText("[\(text)](url)", replacementRange: sel)
            case .heading(let level):
                let prefix = String(repeating: "#", count: level) + " "
                let nsStr = tv.string as NSString
                let paraRange = nsStr.lineRange(for: sel)
                let line = nsStr.substring(with: NSRange(location: paraRange.location, length: paraRange.length)).trimmingCharacters(in: .newlines)
                // Toggle: remove prefix if already has it, else add it
                if line.hasPrefix(prefix) {
                    tv.replaceCharacters(in: NSRange(location: paraRange.location, length: prefix.count), with: "")
                } else {
                    // Strip any existing heading prefix
                    var stripped = line
                    while stripped.hasPrefix("#") { stripped = String(stripped.dropFirst()) }
                    stripped = stripped.trimmingCharacters(in: .init(charactersIn: " "))
                    tv.replaceCharacters(in: NSRange(location: paraRange.location, length: paraRange.length - 1), with: prefix + stripped)
                }
            case .table:
                tv.insertText("\n| Col 1 | Col 2 | Col 3 |\n| ----- | ----- | ----- |\n| Cell  | Cell  | Cell  |\n", replacementRange: sel)
            case .codeBlock:
                let inner = selected.isEmpty ? "code here" : selected
                tv.insertText("\n```\n\(inner)\n```\n", replacementRange: sel)
            case .image:
                tv.insertText("![alt text](image-url)", replacementRange: sel)
            case .boldUnderscore:
                toggle(tv: tv, sel: sel, selected: selected, open: "__", close: "__", placeholder: "bold text")
            case .italicUnderscore:
                toggle(tv: tv, sel: sel, selected: selected, open: "_", close: "_", placeholder: "italic text")
            case .highlight:
                toggle(tv: tv, sel: sel, selected: selected, open: "==", close: "==", placeholder: "highlighted text")
            case .comment:
                toggle(tv: tv, sel: sel, selected: selected, open: "%%", close: "%%", placeholder: "comment")
            case .inlineMath:
                toggle(tv: tv, sel: sel, selected: selected, open: "$", close: "$", placeholder: "formula")
            case .mathBlock:
                let inner = selected.isEmpty ? "E = mc^2" : selected
                tv.insertText("\n$$\n\(inner)\n$$\n", replacementRange: sel)
            case .wikilink:
                let page = selected.isEmpty ? "Page Name" : selected
                tv.insertText("[[\(page)]]", replacementRange: sel)
            case .tag:
                tv.insertText("#\(selected.isEmpty ? "tag" : selected)", replacementRange: sel)
            case .footnote:
                tv.insertText("[^1]", replacementRange: sel)
            case .callout(let type):
                tv.insertText("\n> [!\(type)]\n> Content here\n", replacementRange: sel)
            case .copyRichText:
                copyAsRichText(tv)
            }
        }

        // Toggle inline syntax (wrap/unwrap)
        private func toggle(tv: NSTextView, sel: NSRange, selected: String,
                            open: String, close: String, placeholder: String) {
            let nsStr = tv.string as NSString
            let openLen  = open.utf16.count
            let closeLen = close.utf16.count
            // Check if already wrapped
            if sel.location >= openLen && NSMaxRange(sel) + closeLen <= nsStr.length {
                let preRange  = NSRange(location: sel.location - openLen, length: openLen)
                let postRange = NSRange(location: NSMaxRange(sel), length: closeLen)
                if nsStr.substring(with: preRange) == open && nsStr.substring(with: postRange) == close {
                    // Unwrap: remove delimiters
                    tv.replaceCharacters(in: NSRange(location: NSMaxRange(sel), length: closeLen), with: "")
                    tv.replaceCharacters(in: NSRange(location: sel.location - openLen, length: openLen), with: "")
                    return
                }
            }
            let inner = selected.isEmpty ? placeholder : selected
            tv.insertText("\(open)\(inner)\(close)", replacementRange: sel)
        }

        // MARK: Copy as rich text (#30)

        private func copyAsRichText(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([storage])
        }

        // MARK: Typewriter scrolling (#21)

        private func scrollToCenter(_ tv: NSTextView) {
            guard let sv = tv.enclosingScrollView,
                  let lm = tv.layoutManager,
                  let tc = tv.textContainer else { return }
            let cursorRange = tv.selectedRange()
            guard cursorRange.location != NSNotFound else { return }
            let glyphRange = lm.glyphRange(forCharacterRange: cursorRange, actualCharacterRange: nil)
            let cursorRect = lm.boundingRect(forGlyphRange: glyphRange, in: tc)
            let cursorY = cursorRect.midY + tv.textContainerInset.height
            let targetY = cursorY - sv.documentVisibleRect.height / 2
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                sv.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: max(0, targetY)))
            }
        }
    }
}

// MARK: - Line Number Ruler View (#22)

class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv   = textView,
              let lm   = tv.layoutManager,
              let tc   = tv.textContainer else { return }

        // Background + separator
        NSColor.controlBackgroundColor.setFill(); rect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: rect.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let font  = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let visibleRect = tv.enclosingScrollView?.documentVisibleRect ?? tv.visibleRect
        let glyphRange  = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let charRange   = lm.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let nsStr    = tv.string as NSString
        let before   = nsStr.substring(to: charRange.location)
        var lineNum  = before.components(separatedBy: "\n").count
        var charIdx  = charRange.location

        while charIdx < NSMaxRange(charRange) {
            let paraRange = nsStr.lineRange(for: NSRange(location: charIdx, length: 0))
            let gRange    = lm.glyphRange(forCharacterRange: paraRange, actualCharacterRange: nil)
            let lineRect  = lm.boundingRect(forGlyphRange: gRange, in: tc)
            let y = lineRect.minY + tv.textContainerInset.height - visibleRect.minY

            let label     = NSAttributedString(string: "\(lineNum)", attributes: attrs)
            let labelSize = label.size()
            label.draw(at: NSPoint(x: rect.maxX - labelSize.width - 6, y: y))

            lineNum += 1
            charIdx  = NSMaxRange(paraRange)
            if charIdx >= nsStr.length { break }
        }
    }
}

// MARK: - Markdown Formatter (#1, #6, #8, #25)

struct MarkdownFormatter {

    // Read once per call cycle; callers pass a Context to avoid repeated UserDefaults hits (#6)
    static var fontSize: Double {
        UserDefaults.standard.double(forKey: "fontSize").nonZero ?? 16
    }
    static var fontFamily: String {
        UserDefaults.standard.string(forKey: "fontFamily") ?? "system"
    }
    static var syntaxTheme: String {
        UserDefaults.standard.string(forKey: "syntaxTheme") ?? "default"
    }

    // MARK: Cached context (fixes #6)

    struct Context {
        let fontSize:   Double
        let fontFamily: String
        let theme:      String
        let body:       NSFont
        let mono:       NSFont
        let syntax:     NSColor
        let codeBg:     NSColor
        let codeColor:  NSColor
        let hide: [NSAttributedString.Key: Any]

        init() {
            fontSize   = UserDefaults.standard.double(forKey: "fontSize").nonZero ?? 16
            fontFamily = UserDefaults.standard.string(forKey: "fontFamily") ?? "system"
            theme      = UserDefaults.standard.string(forKey: "syntaxTheme") ?? "default"

            switch fontFamily {
            case "mono":  body = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            case "serif": body = NSFont(name: "Georgia", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            default:      body = NSFont.systemFont(ofSize: fontSize)
            }
            mono = NSFont.monospacedSystemFont(ofSize: max(10, fontSize - 2), weight: .regular)

            switch theme {
            case "solarized": syntax = NSColor(red: 0.42, green: 0.60, blue: 0.62, alpha: 1)
            case "mono":      syntax = NSColor.secondaryLabelColor
            case "ocean":     syntax = NSColor(red: 0.40, green: 0.55, blue: 0.75, alpha: 1)
            default:          syntax = NSColor.tertiaryLabelColor
            }

            let isPaper = UserDefaults.standard.string(forKey: "appearance") == "paper"
            switch theme {
            case "solarized": codeBg = NSColor(red: 0.99, green: 0.96, blue: 0.89, alpha: 1)
            case "ocean":     codeBg = NSColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1)
            default:          codeBg = isPaper ? .paperCodeBg : NSColor.windowBackgroundColor
            }

            switch theme {
            case "solarized": codeColor = NSColor(red: 0.52, green: 0.60, blue: 0.00, alpha: 1)
            case "ocean":     codeColor = NSColor(red: 0.60, green: 0.85, blue: 0.90, alpha: 1)
            default:          codeColor = NSColor.systemOrange
            }

            hide = [.font: NSFont.systemFont(ofSize: 0.1), .foregroundColor: NSColor.clear]
        }
    }

    static func apply(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let ctx         = Context()           // read UserDefaults once (#6)
        let savedRanges = tv.selectedRanges
        let cursor      = tv.selectedRange().location

        let str       = storage.string
        let nsStr     = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)

        storage.beginEditing()
        let textColor: NSColor = (UserDefaults.standard.string(forKey: "appearance") == "paper") ? .paperText : .labelColor
        storage.setAttributes([.font: ctx.body, .foregroundColor: textColor], range: fullRange)
        applyBlock(storage: storage, str: str, cursor: cursor, ctx: ctx)
        applyInline(storage: storage, str: str, cursor: cursor, ctx: ctx)
        storage.endEditing()
        tv.selectedRanges = savedRanges
    }

    // MARK: Block elements

    private static func applyBlock(storage: NSTextStorage, str: String, cursor: Int, ctx: Context) {
        var loc            = 0
        var inCodeBlock    = false
        var codeBlockStart = 0
        var inMathBlock    = false
        var mathBlockStart = 0
        var inTable        = false
        var tableLineIdx   = 0
        var tableAligns: [NSTextAlignment] = []

        for line in str.components(separatedBy: "\n") {
            let len       = (line as NSString).length
            let lineRange = NSRange(location: loc, length: len)
            let onLine    = cursor >= loc && cursor <= loc + len

            // ── Display math block $$
            if line.trimmingCharacters(in: .whitespaces) == "$$" {
                inTable = false; tableLineIdx = 0; tableAligns = []
                if !inMathBlock {
                    inMathBlock = true; mathBlockStart = loc
                } else {
                    let blockRange = NSRange(location: mathBlockStart, length: loc + len - mathBlockStart)
                    storage.addAttributes([.font: ctx.mono,
                                           .foregroundColor: NSColor.systemPurple,
                                           .backgroundColor: ctx.codeBg], range: blockRange)
                    inMathBlock = false
                }
                storage.addAttributes(onLine
                    ? [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.systemPurple] as [NSAttributedString.Key: Any]
                    : ctx.hide, range: lineRange)
                loc += len + 1; continue
            }
            if inMathBlock { loc += len + 1; continue }

            // ── Fenced code block
            if line.hasPrefix("```") {
                inTable = false; tableLineIdx = 0; tableAligns = []
                if !inCodeBlock {
                    inCodeBlock = true; codeBlockStart = loc
                } else {
                    let blockRange = NSRange(location: codeBlockStart, length: loc + len - codeBlockStart)
                    storage.addAttributes([.font: ctx.mono,
                                           .foregroundColor: NSColor.secondaryLabelColor,
                                           .backgroundColor: ctx.codeBg], range: blockRange)
                    inCodeBlock = false
                }
                storage.addAttributes(onLine
                    ? [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: ctx.syntax] as [NSAttributedString.Key: Any]
                    : ctx.hide, range: lineRange)
                loc += len + 1; continue
            }
            if inCodeBlock { loc += len + 1; continue }

            // ── Table lines
            if line.hasPrefix("|") {
                if !inTable { inTable = true; tableLineIdx = 0 }
                applyTableLine(storage, line, loc, lineIndex: tableLineIdx,
                               alignments: &tableAligns, onLine: onLine, ctx: ctx)
                tableLineIdx += 1
                loc += len + 1; continue
            } else if inTable {
                inTable = false; tableLineIdx = 0; tableAligns = []
            }

            // ── Horizontal rule
            if line == "---" || line == "***" || line == "___" {
                if onLine {
                    storage.addAttributes([.foregroundColor: ctx.syntax], range: lineRange)
                } else {
                    storage.addAttributes(ctx.hide, range: lineRange)
                    storage.addAttributes([
                        .font: NSFont.systemFont(ofSize: 6),
                        .foregroundColor: NSColor.separatorColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: NSColor.separatorColor,
                    ], range: lineRange)
                }
                loc += len + 1; continue
            }

            // ── Headings
            if      line.hasPrefix("# ")      { applyHeading(storage, loc, len, prefixLen: 2, size: ctx.fontSize * 1.9,  onLine: onLine, ctx: ctx) }
            else if line.hasPrefix("## ")     { applyHeading(storage, loc, len, prefixLen: 3, size: ctx.fontSize * 1.5,  onLine: onLine, ctx: ctx) }
            else if line.hasPrefix("### ")    { applyHeading(storage, loc, len, prefixLen: 4, size: ctx.fontSize * 1.25, onLine: onLine, ctx: ctx) }
            else if line.hasPrefix("#### ")   { applyHeading(storage, loc, len, prefixLen: 5, size: ctx.fontSize * 1.1,  onLine: onLine, ctx: ctx) }
            else if line.hasPrefix("##### ")  { applyHeading(storage, loc, len, prefixLen: 6, size: ctx.fontSize * 1.0,  onLine: onLine, ctx: ctx) }
            else if line.hasPrefix("###### ") { applyHeading(storage, loc, len, prefixLen: 7, size: ctx.fontSize * 0.9,  onLine: onLine, ctx: ctx) }

            // ── Callout > [!TYPE] (Obsidian) — must come before generic blockquote
            else if line.hasPrefix("> [!") {
                let afterBang = line.dropFirst(4)
                let typeName  = String(afterBang.prefix(while: { $0 != "]" && $0 != " " && $0 != "\n" }))
                let color     = calloutColor(typeName)
                storage.addAttributes([.foregroundColor: color], range: lineRange)
                if !onLine {
                    storage.addAttributes(ctx.hide, range: NSRange(location: loc, length: min(2, len)))
                }
            }

            // ── Blockquote
            else if line.hasPrefix("> ") {
                storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: lineRange)
                let pr = NSRange(location: loc, length: min(2, len))
                storage.addAttributes(onLine ? [.foregroundColor: ctx.syntax] as [NSAttributedString.Key: Any] : ctx.hide, range: pr)
            }

            // ── Footnote definition [^id]:
            else if line.hasPrefix("[^"), line.contains("]:") {
                storage.addAttributes([.foregroundColor: NSColor.systemIndigo,
                                       .font: NSFont.systemFont(ofSize: ctx.fontSize * 0.9)], range: lineRange)
            }

            // ── Task list (before generic unordered)
            else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                let isChecked  = !line.hasPrefix("- [ ] ")
                let dashRange  = NSRange(location: loc, length: 2)
                let checkRange = NSRange(location: loc + 2, length: 3)
                if onLine {
                    storage.addAttributes([.foregroundColor: ctx.syntax], range: dashRange)
                    storage.addAttributes([.foregroundColor: ctx.syntax], range: checkRange)
                } else {
                    storage.addAttributes(ctx.hide, range: dashRange)
                    storage.addAttributes([.foregroundColor: isChecked ? NSColor.systemGreen : NSColor.tertiaryLabelColor], range: checkRange)
                }
            }

            // ── Unordered list (-, *, + prefixes)
            else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                let pr = NSRange(location: loc, length: min(2, len))
                storage.addAttributes(onLine ? [.foregroundColor: ctx.syntax] as [NSAttributedString.Key: Any] : ctx.hide, range: pr)
            }

            // ── Ordered list (1. or 1) formats)
            else if let m = line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) {
                let prefixLen = line.distance(from: line.startIndex, to: m.upperBound)
                let pr = NSRange(location: loc, length: prefixLen)
                storage.addAttributes(onLine
                    ? [.foregroundColor: ctx.syntax] as [NSAttributedString.Key: Any]
                    : [.foregroundColor: NSColor.secondaryLabelColor],
                    range: pr)
            }

            loc += len + 1
        }
    }

    private static func calloutColor(_ type: String) -> NSColor {
        switch type.lowercased() {
        case "note":                                     return NSColor.systemBlue
        case "abstract", "summary", "tldr":             return NSColor.systemCyan
        case "info":                                     return NSColor.systemBlue
        case "tip", "hint", "important":                return NSColor.systemGreen
        case "success", "check", "done":                return NSColor.systemGreen
        case "question", "help", "faq":                 return NSColor.systemYellow
        case "warning", "caution", "attention":         return NSColor.systemOrange
        case "failure", "fail", "missing":              return NSColor.systemRed
        case "danger", "error":                         return NSColor.systemRed
        case "bug":                                     return NSColor.systemRed
        case "example":                                 return NSColor.systemPurple
        case "quote", "cite":                           return NSColor.secondaryLabelColor
        default:                                        return NSColor.systemBlue
        }
    }

    private static func applyHeading(_ storage: NSTextStorage, _ loc: Int, _ len: Int,
                                     prefixLen: Int, size: CGFloat, onLine: Bool, ctx: Context) {
        guard len > prefixLen else { return }
        let contentRange = NSRange(location: loc + prefixLen, length: len - prefixLen)
        let prefixRange  = NSRange(location: loc, length: prefixLen)
        storage.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .bold)], range: contentRange)
        if onLine {
            storage.addAttributes([.font: NSFont.systemFont(ofSize: size * 0.5, weight: .light),
                                    .foregroundColor: ctx.syntax,
                                    .baselineOffset: (size - size * 0.5) / 2], range: prefixRange)
        } else {
            storage.addAttributes(ctx.hide, range: prefixRange)
        }
    }

    // UTF-16 offsets are accumulated correctly via ch.utf16.count, which returns 2 for
    // surrogate-pair emoji (e.g. 🎉) — ensuring NSRange operations land on the right positions. (#1)
    private static func applyTableLine(_ storage: NSTextStorage, _ line: String, _ loc: Int,
                                        lineIndex: Int, alignments: inout [NSTextAlignment],
                                        onLine: Bool, ctx: Context) {
        let len = (line as NSString).length

        if lineIndex == 1 {
            alignments = parseTableAlignments(line)
            storage.addAttributes(onLine ? [.foregroundColor: ctx.syntax] as [NSAttributedString.Key: Any] : ctx.hide,
                                  range: NSRange(location: loc, length: len))
            return
        }

        let isHeader = lineIndex == 0

        // Build UTF-16 pipe positions — correct for all Unicode including surrogate-pair emoji (#1)
        var pipePositions: [Int] = []
        var utf16Offset = 0
        for ch in line {
            if ch == "|" { pipePositions.append(utf16Offset) }
            utf16Offset += ch.utf16.count
        }

        for pipePos in pipePositions {
            storage.addAttributes([.foregroundColor: ctx.syntax],
                                  range: NSRange(location: loc + pipePos, length: 1))
        }

        var colIndex = 0
        for i in 0..<(pipePositions.count - 1) {
            let cellStart = pipePositions[i] + 1
            let cellEnd   = pipePositions[i + 1]
            guard cellEnd > cellStart else { colIndex += 1; continue }

            let cellRange = NSRange(location: loc + cellStart, length: cellEnd - cellStart)
            var cellAttrs: [NSAttributedString.Key: Any] = [:]
            if isHeader { cellAttrs[.font] = NSFont.systemFont(ofSize: ctx.fontSize, weight: .bold) }
            if colIndex < alignments.count {
                let ps = NSMutableParagraphStyle()
                ps.alignment = alignments[colIndex]
                cellAttrs[.paragraphStyle] = ps
            }
            if !cellAttrs.isEmpty { storage.addAttributes(cellAttrs, range: cellRange) }
            colIndex += 1
        }
    }

    private static func parseTableAlignments(_ separatorLine: String) -> [NSTextAlignment] {
        separatorLine.split(separator: "|", omittingEmptySubsequences: false).compactMap { part in
            let t = part.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }
            if t.hasPrefix(":") && t.hasSuffix(":") { return .center }
            if t.hasSuffix(":")                     { return .right  }
            return .left
        }
    }

    // MARK: Inline elements (#8 escape sequences)

    private static func applyInline(storage: NSTextStorage, str: String, cursor: Int, ctx: Context) {
        // Build set of UTF-16 positions that are backslash-escaped (#8)
        // A character at position i is escaped if str[i-1] == '\'
        var escapedPositions = Set<Int>()
        let nsStr = str as NSString
        do {
            let escRegex = try NSRegularExpression(pattern: "\\\\([*_~`\\[\\]()!\\\\#])")
            for m in escRegex.matches(in: str, range: NSRange(location: 0, length: nsStr.length)) {
                escapedPositions.insert(m.range(at: 0).location) // position of backslash
            }
            // Hide backslash when not on cursor line
            for pos in escapedPositions {
                let lineStart = nsStr.lineRange(for: NSRange(location: pos, length: 0)).location
                let lineEnd   = lineStart + (nsStr.lineRange(for: NSRange(location: pos, length: 0)).length)
                let onLine    = cursor >= lineStart && cursor <= lineEnd
                if !onLine {
                    storage.addAttributes(ctx.hide, range: NSRange(location: pos, length: 1))
                } else {
                    storage.addAttributes([.foregroundColor: ctx.syntax,
                                           .font: NSFont.systemFont(ofSize: ctx.fontSize * 0.8)],
                                          range: NSRange(location: pos, length: 1))
                }
            }
        } catch {}

        // Bold+italic (must precede bold and italic individually)
        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: #"\*\*\*(.+?)\*\*\*"#,
                  attrs: [.font: boldItalicFont(ctx: ctx)], ctx: ctx)

        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: #"(?<!\*)\*\*(?!\*)(.+?)(?<!\*)\*\*(?!\*)"#,
                  attrs: [.font: NSFont.systemFont(ofSize: ctx.fontSize, weight: .bold)], ctx: ctx)

        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
                  attrs: [.font: NSFont(descriptor: ctx.body.fontDescriptor.withSymbolicTraits(.italic),
                                        size: ctx.fontSize) ?? ctx.body], ctx: ctx)

        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: #"~~(.+?)~~"#,
                  attrs: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                          .strikethroughColor: NSColor.labelColor], ctx: ctx)

        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: #"(?<![`])`(?!`)([^`\n]+)`(?![`])"#,
                  attrs: [.font: ctx.mono,
                          .backgroundColor: ctx.codeBg,
                          .foregroundColor: ctx.codeColor], ctx: ctx)

        // Bold with underscores __text__ (Obsidian)
        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: "(?<![_])__(?![_])(.+?)(?<![_])__(?![_])",
                  attrs: [.font: NSFont.systemFont(ofSize: ctx.fontSize, weight: .bold)], ctx: ctx)

        // Italic with underscores _text_ (Obsidian)
        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: "(?<![_])_(?![_])([^_\\n]+)(?<![_])_(?![_])",
                  attrs: [.font: NSFont(descriptor: ctx.body.fontDescriptor.withSymbolicTraits(.italic),
                                        size: ctx.fontSize) ?? ctx.body], ctx: ctx)

        // Highlight ==text== (Obsidian)
        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: "==([^=\\n]+)==",
                  attrs: [.backgroundColor: NSColor.systemYellow.withAlphaComponent(0.35),
                          .foregroundColor: NSColor.labelColor], ctx: ctx)

        // Inline math $text$ (Obsidian)
        applySpan(storage, str, cursor, escapedPositions: escapedPositions,
                  pattern: "(?<!\\$)\\$(?!\\$)([^\\$\\n]+?)(?<!\\$)\\$(?!\\$)",
                  attrs: [.font: ctx.mono, .foregroundColor: NSColor.systemPurple], ctx: ctx)

        // Comments %%text%% (Obsidian) — hidden unless cursor is inside
        applyComment(storage, str, cursor, ctx: ctx)

        // Wikilinks [[Page]] or [[Page|Display]] (Obsidian)
        applyWikilink(storage, str, cursor, ctx: ctx)

        // Footnote references [^id] (Obsidian / CommonMark)
        applyFootnoteRef(storage, str, cursor, ctx: ctx)

        // Tags #tagname (Obsidian)
        applyTag(storage, str, cursor, ctx: ctx)

        applyImage(storage, str, cursor, ctx: ctx)
        applyLink(storage, str, cursor, ctx: ctx)
    }

    private static func boldItalicFont(ctx: Context) -> NSFont {
        let descriptor = ctx.body.fontDescriptor.withSymbolicTraits([.bold, .italic])
        return NSFont(descriptor: descriptor, size: ctx.fontSize) ?? ctx.body
    }

    private static func applySpan(_ storage: NSTextStorage, _ str: String, _ cursor: Int,
                                   escapedPositions: Set<Int>,
                                   pattern: String,
                                   attrs: [NSAttributedString.Key: Any],
                                   ctx: Context) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsStr     = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)

        for m in regex.matches(in: str, range: fullRange) {
            let matchRange   = m.range(at: 0)
            let contentRange = m.range(at: 1)
            guard contentRange.location != NSNotFound else { continue }

            // Skip if match starts at an escaped position (#8)
            if escapedPositions.contains(matchRange.location + 1) { continue }

            let onSpan = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)
            storage.addAttributes(attrs, range: contentRange)

            let prefixLen   = contentRange.location - matchRange.location
            let suffixLen   = NSMaxRange(matchRange) - NSMaxRange(contentRange)
            let prefixRange = NSRange(location: matchRange.location, length: prefixLen)
            let suffixRange = NSRange(location: NSMaxRange(contentRange), length: suffixLen)
            let symAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: ctx.syntax,
                                                            .font: NSFont.systemFont(ofSize: 12)]

            if onSpan {
                if prefixLen > 0 { storage.addAttributes(symAttrs, range: prefixRange) }
                if suffixLen > 0 { storage.addAttributes(symAttrs, range: suffixRange) }
            } else {
                if prefixLen > 0 { storage.addAttributes(ctx.hide, range: prefixRange) }
                if suffixLen > 0 { storage.addAttributes(ctx.hide, range: suffixRange) }
            }
        }
    }

    private static func applyImage(_ storage: NSTextStorage, _ str: String, _ cursor: Int, ctx: Context) {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) else { return }
        let nsStr     = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)

        for m in regex.matches(in: str, range: fullRange) {
            let matchRange = m.range(at: 0)
            let altRange   = m.range(at: 1)
            guard altRange.location != NSNotFound else { continue }
            let onImage = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)

            if onImage {
                storage.addAttributes([.foregroundColor: ctx.syntax], range: matchRange)
            } else {
                let prefixRange = NSRange(location: matchRange.location, length: altRange.location - matchRange.location)
                let suffixRange = NSRange(location: NSMaxRange(altRange), length: NSMaxRange(matchRange) - NSMaxRange(altRange))
                storage.addAttributes(ctx.hide, range: prefixRange)
                storage.addAttributes(ctx.hide, range: suffixRange)
                let italicFont = NSFont(descriptor: ctx.body.fontDescriptor.withSymbolicTraits(.italic), size: ctx.fontSize) ?? ctx.body
                storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .font: italicFont], range: altRange)
            }
        }
    }

    private static func applyLink(_ storage: NSTextStorage, _ str: String, _ cursor: Int, ctx: Context) {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) else { return }
        let nsStr     = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)

        for m in regex.matches(in: str, range: fullRange) {
            let matchRange = m.range(at: 0)
            let textRange  = m.range(at: 1)
            let urlRange   = m.range(at: 2)
            guard textRange.location != NSNotFound, urlRange.location != NSNotFound else { continue }
            // Skip images (preceded by !)
            if matchRange.location > 0 && nsStr.character(at: matchRange.location - 1) == 33 { continue }

            let onLink = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)
            storage.addAttributes([.foregroundColor: NSColor.linkColor,
                                    .underlineStyle: NSUnderlineStyle.single.rawValue], range: textRange)

            let brackets = [
                NSRange(location: matchRange.location,        length: 1),
                NSRange(location: NSMaxRange(textRange),       length: 1),
                NSRange(location: NSMaxRange(textRange) + 1,   length: 1),
                NSRange(location: NSMaxRange(urlRange),        length: 1),
            ]
            let symAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: ctx.syntax, .font: NSFont.systemFont(ofSize: 12)]

            if onLink {
                brackets.forEach { storage.addAttributes(symAttrs, range: $0) }
                storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 13)], range: urlRange)
            } else {
                brackets.forEach { storage.addAttributes(ctx.hide, range: $0) }
                storage.addAttributes(ctx.hide, range: urlRange)
            }
        }
    }

    // MARK: New Obsidian inline helpers

    /// Comments %%text%% — invisible unless cursor is inside
    private static func applyComment(_ storage: NSTextStorage, _ str: String, _ cursor: Int, ctx: Context) {
        guard let regex = try? NSRegularExpression(pattern: "%%(.+?)%%", options: .dotMatchesLineSeparators) else { return }
        let nsStr = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)
        for m in regex.matches(in: str, range: fullRange) {
            let matchRange = m.range(at: 0)
            let onSpan = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)
            storage.addAttributes(onSpan ? [.foregroundColor: ctx.syntax] as [NSAttributedString.Key: Any] : ctx.hide,
                                  range: matchRange)
        }
    }

    /// Wikilinks [[Page]] or [[Page|Display text]]
    private static func applyWikilink(_ storage: NSTextStorage, _ str: String, _ cursor: Int, ctx: Context) {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\[\\]|\\n]+?)(?:\\|([^\\[\\]\\n]+?))?\\]\\]") else { return }
        let nsStr = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)
        for m in regex.matches(in: str, range: fullRange) {
            let matchRange   = m.range(at: 0)
            let pageRange    = m.range(at: 1)
            let displayRange = m.range(at: 2) // NSNotFound when no alias
            let onLink = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)

            let visibleRange = (displayRange.location != NSNotFound) ? displayRange : pageRange
            storage.addAttributes([.foregroundColor: NSColor.linkColor,
                                    .underlineStyle: NSUnderlineStyle.single.rawValue], range: visibleRange)

            let symAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: ctx.syntax,
                .font: NSFont.systemFont(ofSize: 12),
                .underlineStyle: 0,
            ]
            let prefixRange = NSRange(location: matchRange.location, length: 2)                 // [[
            let suffixRange = NSRange(location: NSMaxRange(matchRange) - 2, length: 2)          // ]]

            if onLink {
                storage.addAttributes(symAttrs, range: prefixRange)
                storage.addAttributes(symAttrs, range: suffixRange)
                if displayRange.location != NSNotFound {
                    // show page name as syntax + pipe separator
                    storage.addAttributes(symAttrs, range: pageRange)
                    storage.addAttributes(symAttrs, range: NSRange(location: NSMaxRange(pageRange), length: 1))
                }
            } else {
                storage.addAttributes(ctx.hide, range: prefixRange)
                storage.addAttributes(ctx.hide, range: suffixRange)
                if displayRange.location != NSNotFound {
                    storage.addAttributes(ctx.hide, range: pageRange)
                    storage.addAttributes(ctx.hide, range: NSRange(location: NSMaxRange(pageRange), length: 1))
                }
            }
        }
    }

    /// Footnote references [^id] — styled as superscript
    private static func applyFootnoteRef(_ storage: NSTextStorage, _ str: String, _ cursor: Int, ctx: Context) {
        guard let regex = try? NSRegularExpression(pattern: "\\[\\^([^\\]\\n]+)\\]") else { return }
        let nsStr = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)
        let small = ctx.fontSize * 0.75
        for m in regex.matches(in: str, range: fullRange) {
            let matchRange   = m.range(at: 0)
            let contentRange = m.range(at: 1)
            let onRef = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)

            storage.addAttributes([.foregroundColor: NSColor.systemIndigo,
                                    .font: NSFont.systemFont(ofSize: small),
                                    .baselineOffset: ctx.fontSize * 0.25], range: matchRange)
            if !onRef {
                // hide [^ and ] brackets, keep just the id
                storage.addAttributes(ctx.hide, range: NSRange(location: matchRange.location, length: 2))
                storage.addAttributes(ctx.hide, range: NSRange(location: NSMaxRange(contentRange), length: 1))
            }
        }
    }

    /// Tags #tagname — teal coloured, slightly smaller
    private static func applyTag(_ storage: NSTextStorage, _ str: String, _ cursor: Int, ctx: Context) {
        guard let regex = try? NSRegularExpression(pattern: "(?<![&\\w#])#([a-zA-Z][a-zA-Z0-9_/-]*)") else { return }
        let nsStr = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)
        for m in regex.matches(in: str, range: fullRange) {
            let matchRange = m.range(at: 0)
            storage.addAttributes([
                .foregroundColor: NSColor.systemTeal,
                .font: NSFont.monospacedSystemFont(ofSize: ctx.fontSize * 0.88, weight: .medium),
            ], range: matchRange)
        }
    }
}

// MARK: - Double helper

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
