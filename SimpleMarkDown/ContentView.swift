//
//  ContentView.swift
//  SimpleMarkDown
//

import SwiftUI
import AppKit
internal import UniformTypeIdentifiers

// MARK: - Main View

struct ContentView: View {
    @State private var text: String = "# Hello!\n\n**bold**, *italic*, ***bold italic***, ~~strikethrough~~, `code`\n\n## Tasks\n\n- [x] Done\n- [ ] Todo\n\n## Table\n\n| Name     | Role    | Score |\n| :------- | :-----: | ----: |\n| Alice    | Admin   | 99    |\n| Bob      | User    | 42    |\n\n## Image\n\n![Swift logo](https://swift.org/assets/images/swift.svg)\n\n## Link\n\n[Apple](https://apple.com)\n\n---\n\n> Blockquote\n\n```\nfunc hello() {\n    print(\"world\")\n}\n```"
    @State private var currentFileURL: URL? = nil

    // @AppStorage = persiste automatiquement dans UserDefaults (survit aux redémarrages)
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("fontSize")   private var fontSize: Double   = 16

    private var windowTitle: String {
        currentFileURL?.lastPathComponent ?? "Untitled"
    }

    var body: some View {
        MarkdownEditorView(text: $text)
            .frame(minWidth: 500, minHeight: 400)
            .navigationTitle(windowTitle)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Open")  { openFile() }
                    Button("Save")  { saveFile() }
                }
            }
            .background(
                Group {
                    Button("") { openFile() }.keyboardShortcut("o", modifiers: .command).opacity(0)
                    Button("") { saveFile() }.keyboardShortcut("s", modifiers: .command).opacity(0)
                }
            )
            // Applique l'apparence dès le lancement
            .onAppear { applyAppearance(appearance) }
            // Réagit aux changements dans les Settings
            .onChange(of: appearance) { _, new in applyAppearance(new) }
    }

    // NSApp.appearance = nil → suit le système
    // NSApp.appearance = .aqua → force le mode clair
    // NSApp.appearance = .darkAqua → force le mode sombre
    private func applyAppearance(_ value: String) {
        switch value {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      NSApp.appearance = nil
        }
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            text = content
            currentFileURL = url
        }
    }

    func saveFile() {
        if let url = currentFileURL {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "Untitled.md"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
            currentFileURL = url
        }
    }
}

// MARK: - Settings View
// Accessible via ⌘, ou "SimpleMarkDown > Settings…"

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: String = "system"
    @AppStorage("fontSize")   private var fontSize: Double   = 16
    @AppStorage("fontFamily") private var fontFamily: String = "system"

    var body: some View {
        Form {
            // ── Appearance ───────────────────────────────────────────────
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
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
            }

            // ── Reset ────────────────────────────────────────────────────
            Section {
                Button("Reset to defaults") {
                    appearance = "system"
                    fontSize   = 16
                    fontFamily = "system"
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding()
    }
}

// MARK: - NSViewRepresentable

struct MarkdownEditorView: NSViewRepresentable {
    @Binding var text: String

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

        tv.string = text
        MarkdownFormatter.apply(to: tv)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        // Reforimate si le texte a changé de l'extérieur (ouverture fichier)
        // OU si les settings ont changé (fontSize, fontFamily)
        let needsReformat = tv.string != text
            || context.coordinator.lastFontSize   != MarkdownFormatter.fontSize
            || context.coordinator.lastFontFamily != MarkdownFormatter.fontFamily

        if needsReformat {
            if tv.string != text { tv.string = text }
            context.coordinator.lastFontSize   = MarkdownFormatter.fontSize
            context.coordinator.lastFontFamily = MarkdownFormatter.fontFamily
            MarkdownFormatter.apply(to: tv)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditorView
        private var isFormatting = false
        var lastFontSize: Double   = 16
        var lastFontFamily: String = "system"

        init(_ p: MarkdownEditorView) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            applyIfNeeded(tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            applyIfNeeded(tv)
        }

        private func applyIfNeeded(_ tv: NSTextView) {
            guard !isFormatting else { return }
            isFormatting = true
            MarkdownFormatter.apply(to: tv)
            isFormatting = false
        }
    }
}

// MARK: - Markdown Formatter

struct MarkdownFormatter {

    // Lit les préférences depuis UserDefaults à chaque appel
    static var fontSize: Double {
        UserDefaults.standard.double(forKey: "fontSize").nonZero ?? 16
    }
    static var fontFamily: String {
        UserDefaults.standard.string(forKey: "fontFamily") ?? "system"
    }

    static var body: NSFont {
        let size = fontSize
        switch fontFamily {
        case "mono":  return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case "serif": return NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size)
        default:      return NSFont.systemFont(ofSize: size)
        }
    }
    static var mono:   NSFont { NSFont.monospacedSystemFont(ofSize: fontSize - 2, weight: .regular) }
    static var hidden: NSFont { NSFont.systemFont(ofSize: 0.1) }

    static let syntax      = NSColor.tertiaryLabelColor
    static let transparent = NSColor.clear
    static let hide: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 0.1),
        .foregroundColor: NSColor.clear,
    ]

    static func apply(to tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let savedRanges = tv.selectedRanges
        let cursor = tv.selectedRange().location

        let str       = storage.string
        let nsStr     = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)

        storage.beginEditing()

        storage.setAttributes([
            .font: body,
            .foregroundColor: NSColor.labelColor,
        ], range: fullRange)

        applyBlock(storage: storage, str: str, cursor: cursor)
        applyInline(storage: storage, str: str, cursor: cursor)

        storage.endEditing()
        tv.selectedRanges = savedRanges
    }

    // MARK: Block elements

    private static func applyBlock(storage: NSTextStorage, str: String, cursor: Int) {
        var loc = 0
        var inCodeBlock = false
        var codeBlockStart = 0
        var inTable = false
        var tableLineIndex = 0
        var tableAlignments: [NSTextAlignment] = []

        for line in str.components(separatedBy: "\n") {
            let len       = (line as NSString).length
            let lineRange = NSRange(location: loc, length: len)
            let onLine    = cursor >= loc && cursor <= loc + len

            // ── Fenced code block ```
            if line.hasPrefix("```") {
                inTable = false; tableLineIndex = 0; tableAlignments = []
                if !inCodeBlock {
                    inCodeBlock    = true
                    codeBlockStart = loc
                } else {
                    let blockRange = NSRange(location: codeBlockStart,
                                            length: loc + len - codeBlockStart)
                    storage.addAttributes([
                        .font: mono,
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .backgroundColor: NSColor.windowBackgroundColor,
                    ], range: blockRange)
                    inCodeBlock = false
                }
                storage.addAttributes(onLine
                    ? [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                       .foregroundColor: syntax] as [NSAttributedString.Key: Any]
                    : hide,
                    range: lineRange)
                loc += len + 1; continue
            }
            if inCodeBlock { loc += len + 1; continue }

            // ── Table lines (start with |)
            if line.hasPrefix("|") {
                if !inTable { inTable = true; tableLineIndex = 0 }
                applyTableLine(storage, line, loc, lineIndex: tableLineIndex,
                               alignments: &tableAlignments, onLine: onLine)
                tableLineIndex += 1
                loc += len + 1; continue
            } else if inTable {
                inTable = false; tableLineIndex = 0; tableAlignments = []
            }

            // ── Horizontal rule ---
            if line == "---" || line == "***" || line == "___" {
                if onLine {
                    storage.addAttributes([.foregroundColor: syntax], range: lineRange)
                } else {
                    storage.addAttributes(hide, range: lineRange)
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
            if      line.hasPrefix("# ")      { applyHeading(storage, loc, len, prefixLen: 2, size: fontSize * 1.9,  onLine: onLine) }
            else if line.hasPrefix("## ")     { applyHeading(storage, loc, len, prefixLen: 3, size: fontSize * 1.5,  onLine: onLine) }
            else if line.hasPrefix("### ")    { applyHeading(storage, loc, len, prefixLen: 4, size: fontSize * 1.25, onLine: onLine) }
            else if line.hasPrefix("#### ")   { applyHeading(storage, loc, len, prefixLen: 5, size: fontSize * 1.1,  onLine: onLine) }
            else if line.hasPrefix("##### ")  { applyHeading(storage, loc, len, prefixLen: 6, size: fontSize * 1.0,  onLine: onLine) }
            else if line.hasPrefix("###### ") { applyHeading(storage, loc, len, prefixLen: 7, size: fontSize * 0.9,  onLine: onLine) }

            // ── Blockquote
            else if line.hasPrefix("> ") {
                storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor],
                                       range: lineRange)
                let pr = NSRange(location: loc, length: min(2, len))
                storage.addAttributes(onLine ? [.foregroundColor: syntax] as [NSAttributedString.Key: Any] : hide, range: pr)
            }

            // ── Task list (must be before generic unordered list)
            else if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                let isChecked  = line.hasPrefix("- [x] ")
                let dashRange  = NSRange(location: loc, length: 2)     // "- "
                let checkRange = NSRange(location: loc + 2, length: 3) // "[ ]" or "[x]"
                if onLine {
                    storage.addAttributes([.foregroundColor: syntax], range: dashRange)
                    storage.addAttributes([.foregroundColor: syntax], range: checkRange)
                } else {
                    storage.addAttributes(hide, range: dashRange)
                    storage.addAttributes([
                        .foregroundColor: isChecked ? NSColor.systemGreen : NSColor.tertiaryLabelColor,
                    ], range: checkRange)
                }
            }

            // ── Unordered list
            else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let pr = NSRange(location: loc, length: min(2, len))
                storage.addAttributes(onLine ? [.foregroundColor: syntax] as [NSAttributedString.Key: Any] : hide, range: pr)
            }

            // ── Ordered list
            else if line.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                if let m = line.range(of: #"^\d+\. "#, options: .regularExpression) {
                    let prefixLen = line.distance(from: line.startIndex, to: m.upperBound)
                    let pr = NSRange(location: loc, length: prefixLen)
                    storage.addAttributes(onLine
                        ? [.foregroundColor: syntax] as [NSAttributedString.Key: Any]
                        : [.foregroundColor: NSColor.secondaryLabelColor],
                        range: pr)
                }
            }

            loc += len + 1
        }
    }

    private static func applyHeading(_ storage: NSTextStorage, _ loc: Int, _ len: Int,
                                     prefixLen: Int, size: CGFloat, onLine: Bool) {
        guard len > prefixLen else { return }
        let contentRange = NSRange(location: loc + prefixLen, length: len - prefixLen)
        let prefixRange  = NSRange(location: loc, length: prefixLen)

        storage.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: .bold)],
                               range: contentRange)
        if onLine {
            storage.addAttributes([
                .font: NSFont.systemFont(ofSize: size * 0.5, weight: .light),
                .foregroundColor: syntax,
                .baselineOffset: (size - size * 0.5) / 2,
            ], range: prefixRange)
        } else {
            storage.addAttributes(hide, range: prefixRange)
        }
    }

    private static func applyTableLine(_ storage: NSTextStorage, _ line: String, _ loc: Int,
                                        lineIndex: Int, alignments: inout [NSTextAlignment], onLine: Bool) {
        let len = (line as NSString).length

        // Separator row (index 1): parse alignments, hide or show as syntax
        if lineIndex == 1 {
            alignments = parseTableAlignments(line)
            if onLine {
                storage.addAttributes([.foregroundColor: syntax], range: NSRange(location: loc, length: len))
            } else {
                storage.addAttributes(hide, range: NSRange(location: loc, length: len))
            }
            return
        }

        let isHeader = lineIndex == 0

        // Find pipe positions (UTF-16 offsets)
        var pipePositions: [Int] = []
        var utf16Offset = 0
        for ch in line {
            if ch == "|" { pipePositions.append(utf16Offset) }
            utf16Offset += ch.utf16.count
        }

        // Style all pipes as syntax color
        for pipePos in pipePositions {
            storage.addAttributes([.foregroundColor: syntax],
                                  range: NSRange(location: loc + pipePos, length: 1))
        }

        // Style cell contents between consecutive pipes
        var colIndex = 0
        for i in 0..<(pipePositions.count - 1) {
            let cellStart = pipePositions[i] + 1
            let cellEnd   = pipePositions[i + 1]
            guard cellEnd > cellStart else { colIndex += 1; continue }

            let cellRange = NSRange(location: loc + cellStart, length: cellEnd - cellStart)
            var cellAttrs: [NSAttributedString.Key: Any] = [:]

            if isHeader {
                cellAttrs[.font] = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            }
            if colIndex < alignments.count {
                let ps = NSMutableParagraphStyle()
                ps.alignment = alignments[colIndex]
                cellAttrs[.paragraphStyle] = ps
            }
            if !cellAttrs.isEmpty {
                storage.addAttributes(cellAttrs, range: cellRange)
            }
            colIndex += 1
        }
    }

    private static func parseTableAlignments(_ separatorLine: String) -> [NSTextAlignment] {
        return separatorLine.split(separator: "|", omittingEmptySubsequences: false).compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }
            if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") { return NSTextAlignment.center }
            if trimmed.hasSuffix(":") { return NSTextAlignment.right }
            return NSTextAlignment.left
        }
    }

    // MARK: Inline elements

    private static func applyInline(storage: NSTextStorage, str: String, cursor: Int) {
        // Bold+italic must come before bold and italic (order matters)
        applySpan(storage, str, cursor,
                  pattern: #"\*\*\*(.+?)\*\*\*"#,
                  attrs: [.font: boldItalicFont()])

        // Use lookaround to avoid matching inside ***
        applySpan(storage, str, cursor,
                  pattern: #"(?<!\*)\*\*(?!\*)(.+?)(?<!\*)\*\*(?!\*)"#,
                  attrs: [.font: NSFont.systemFont(ofSize: fontSize, weight: .bold)])

        applySpan(storage, str, cursor,
                  pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#,
                  attrs: [.font: NSFont(descriptor: body.fontDescriptor.withSymbolicTraits(.italic),
                                        size: fontSize) ?? body])

        applySpan(storage, str, cursor,
                  pattern: #"~~(.+?)~~"#,
                  attrs: [.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                          .strikethroughColor: NSColor.labelColor])

        applySpan(storage, str, cursor,
                  pattern: #"(?<![`])`(?!`)([^`\n]+)`(?![`])"#,
                  attrs: [.font: mono,
                          .backgroundColor: NSColor.windowBackgroundColor,
                          .foregroundColor: NSColor.systemOrange])

        applyImage(storage, str, cursor)
        applyLink(storage, str, cursor)
    }

    private static func boldItalicFont() -> NSFont {
        let descriptor = body.fontDescriptor.withSymbolicTraits([.bold, .italic])
        return NSFont(descriptor: descriptor, size: fontSize) ?? body
    }

    private static func applySpan(_ storage: NSTextStorage, _ str: String, _ cursor: Int,
                                   pattern: String, attrs: [NSAttributedString.Key: Any]) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsStr     = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)

        for m in regex.matches(in: str, range: fullRange) {
            let matchRange   = m.range(at: 0)
            let contentRange = m.range(at: 1)
            guard contentRange.location != NSNotFound else { continue }

            let onSpan = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)
            storage.addAttributes(attrs, range: contentRange)

            let prefixLen   = contentRange.location - matchRange.location
            let suffixLen   = NSMaxRange(matchRange) - NSMaxRange(contentRange)
            let prefixRange = NSRange(location: matchRange.location, length: prefixLen)
            let suffixRange = NSRange(location: NSMaxRange(contentRange), length: suffixLen)
            let symAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: syntax,
                .font: NSFont.systemFont(ofSize: 12),
            ]

            if onSpan {
                if prefixLen > 0 { storage.addAttributes(symAttrs, range: prefixRange) }
                if suffixLen > 0 { storage.addAttributes(symAttrs, range: suffixRange) }
            } else {
                if prefixLen > 0 { storage.addAttributes(hide, range: prefixRange) }
                if suffixLen > 0 { storage.addAttributes(hide, range: suffixRange) }
            }
        }
    }

    private static func applyImage(_ storage: NSTextStorage, _ str: String, _ cursor: Int) {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) else { return }
        let nsStr     = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)

        for m in regex.matches(in: str, range: fullRange) {
            let matchRange = m.range(at: 0)
            let altRange   = m.range(at: 1)
            let urlRange   = m.range(at: 2)
            guard altRange.location != NSNotFound, urlRange.location != NSNotFound else { continue }

            let onImage = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)

            if onImage {
                storage.addAttributes([.foregroundColor: syntax], range: matchRange)
            } else {
                // Hide `![` prefix and `](url)` suffix; style alt text as gray italic
                let prefixRange = NSRange(location: matchRange.location,
                                          length: altRange.location - matchRange.location)
                let suffixRange = NSRange(location: NSMaxRange(altRange),
                                          length: NSMaxRange(matchRange) - NSMaxRange(altRange))
                storage.addAttributes(hide, range: prefixRange)
                storage.addAttributes(hide, range: suffixRange)
                let italicDescriptor = body.fontDescriptor.withSymbolicTraits(.italic)
                let italicFont = NSFont(descriptor: italicDescriptor, size: fontSize) ?? body
                storage.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: italicFont,
                ], range: altRange)
            }
        }
    }

    private static func applyLink(_ storage: NSTextStorage, _ str: String, _ cursor: Int) {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#) else { return }
        let nsStr     = str as NSString
        let fullRange = NSRange(location: 0, length: nsStr.length)

        for m in regex.matches(in: str, range: fullRange) {
            let matchRange = m.range(at: 0)
            let textRange  = m.range(at: 1)
            let urlRange   = m.range(at: 2)
            guard textRange.location != NSNotFound, urlRange.location != NSNotFound else { continue }

            // Skip images: preceded by !
            if matchRange.location > 0 && nsStr.character(at: matchRange.location - 1) == 33 { continue }

            let onLink = cursor >= matchRange.location && cursor <= NSMaxRange(matchRange)

            storage.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: textRange)

            let brackets: [NSRange] = [
                NSRange(location: matchRange.location, length: 1),
                NSRange(location: NSMaxRange(textRange), length: 1),
                NSRange(location: NSMaxRange(textRange) + 1, length: 1),
                NSRange(location: NSMaxRange(urlRange), length: 1),
            ]
            let symAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: syntax,
                .font: NSFont.systemFont(ofSize: 12),
            ]

            if onLink {
                brackets.forEach { storage.addAttributes(symAttrs, range: $0) }
                storage.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 13),
                ], range: urlRange)
            } else {
                brackets.forEach { storage.addAttributes(hide, range: $0) }
                storage.addAttributes(hide, range: urlRange)
            }
        }
    }
}

// MARK: - Double helper

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}
