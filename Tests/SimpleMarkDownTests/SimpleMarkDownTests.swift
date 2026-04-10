import Testing
import Foundation
@testable import SimpleMarkDown

// MARK: - HTML Export Tests

@Suite("MarkdownConverter – Headings")
struct HeadingTests {
    let md = MarkdownConverter()

    @Test func h1() {
        let html = md.toHTML("# Hello")
        #expect(html.contains("<h1>Hello</h1>"))
    }

    @Test func h2() {
        let html = md.toHTML("## Section")
        #expect(html.contains("<h2>Section</h2>"))
    }

    @Test func h3() {
        let html = md.toHTML("### Sub")
        #expect(html.contains("<h3>Sub</h3>"))
    }

    @Test func headingHashesWithoutSpaceAreNotHeadings() {
        let html = md.toHTML("#NoSpace")
        #expect(!html.contains("<h1>"))
        #expect(html.contains("#NoSpace"))
    }
}

@Suite("MarkdownConverter – Inline Formatting")
struct InlineTests {
    let md = MarkdownConverter()

    @Test func bold() {
        let html = md.inline("**bold**")
        #expect(html.contains("<strong>bold</strong>"))
    }

    @Test func italic() {
        let html = md.inline("*italic*")
        #expect(html.contains("<em>italic</em>"))
    }

    @Test func boldItalic() {
        let html = md.inline("***bi***")
        #expect(html.contains("<strong><em>bi</em></strong>"))
    }

    @Test func strikethrough() {
        let html = md.inline("~~del~~")
        #expect(html.contains("<del>del</del>"))
    }

    @Test func inlineCode() {
        let html = md.inline("`code`")
        #expect(html.contains("<code>code</code>"))
    }

    @Test func link() {
        let html = md.inline("[Apple](https://apple.com)")
        #expect(html.contains("<a href=\"https://apple.com\">Apple</a>"))
    }

    @Test func image() {
        let html = md.inline("![Alt](img.png)")
        #expect(html.contains("<img src=\"img.png\" alt=\"Alt\">"))
    }

    @Test func htmlEntitiesEscaped() {
        let html = md.inline("<script>alert('xss')</script>")
        #expect(!html.contains("<script>"))
        #expect(html.contains("&lt;script&gt;"))
    }
}

@Suite("MarkdownConverter – Code Blocks")
struct CodeBlockTests {
    let md = MarkdownConverter()

    @Test func fencedCodeBlockNotFormattedAsInline() {
        let markdown = "```\n**not bold**\n```"
        let html = md.toHTML(markdown)
        // Content inside a code block must not be converted to <strong>
        #expect(!html.contains("<strong>"))
        #expect(html.contains("**not bold**"))
    }

    @Test func fencedCodeBlockWithLanguage() {
        let markdown = "```swift\nlet x = 1\n```"
        let html = md.toHTML(markdown)
        #expect(html.contains("class=\"language-swift\""))
    }

    @Test func fencedCodeBlockHTMLEscaped() {
        let markdown = "```\n<div>\n```"
        let html = md.toHTML(markdown)
        #expect(html.contains("&lt;div&gt;"))
        #expect(!html.contains("<div>"))
    }
}

@Suite("MarkdownConverter – Tables")
struct TableTests {
    let md = MarkdownConverter()

    @Test func basicTable() {
        let markdown = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = md.toHTML(markdown)
        #expect(html.contains("<table>"))
        #expect(html.contains("<th>A</th>"))
        #expect(html.contains("<td>1</td>"))
    }

    @Test func tableAlignmentParsing() {
        let alignments = md.parseTableAlignments("|:---|:---:|---:|")
        #expect(alignments == ["left", "center", "right"])
    }

    @Test func tableAlignmentIgnoresNonSeparatorRows() {
        let alignments = md.parseTableAlignments("| Name | Role |")
        #expect(alignments.isEmpty)
    }

    /// Issue #1: UTF-16 pipe positions must be correct with surrogate-pair emoji.
    /// Emoji like 🎉 (U+1F389) use 2 UTF-16 code units; offsets must reflect this.
    @Test func pipePositionsWithSurrogatePairEmoji() {
        // 🎉 (U+1F389) has utf16.count == 2 (surrogate pair)
        let line = "| 🎉 | text |"
        let positions = md.pipePositions(in: line)
        let utf16 = Array(line.utf16)
        // Every reported position must be a pipe character (UTF-16 code unit 124)
        for pos in positions {
            #expect(utf16[pos] == 124) // '|'
        }
    }

    @Test func pipePositionsWithASCIIOnly() {
        let line = "| A | B | C |"
        let positions = md.pipePositions(in: line)
        #expect(positions.count == 4)
        let utf16 = Array(line.utf16)
        for pos in positions {
            #expect(utf16[pos] == 124) // '|'
        }
    }

    @Test func pipePositionsWithBMPEmoji() {
        // ✅ (U+2705) is in the BMP: utf16.count == 1
        let line = "| ✅ | done |"
        let positions = md.pipePositions(in: line)
        let utf16 = Array(line.utf16)
        for pos in positions {
            #expect(utf16[pos] == 124) // '|'
        }
    }
}

@Suite("MarkdownConverter – Lists")
struct ListTests {
    let md = MarkdownConverter()

    @Test func unorderedList() {
        let html = md.toHTML("- Alpha\n- Beta")
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>Alpha</li>"))
        #expect(html.contains("<li>Beta</li>"))
    }

    @Test func orderedList() {
        let html = md.toHTML("1. First\n2. Second")
        #expect(html.contains("<ol>"))
        #expect(html.contains("<li>First</li>"))
    }

    @Test func taskListChecked() {
        let html = md.toHTML("- [x] Done")
        #expect(html.contains("checked"))
        #expect(html.contains("Done"))
    }

    @Test func taskListUnchecked() {
        let html = md.toHTML("- [ ] Todo")
        #expect(!html.contains("checked"))
        #expect(html.contains("Todo"))
    }
}

@Suite("MarkdownConverter – Block Elements")
struct BlockTests {
    let md = MarkdownConverter()

    @Test func blockquote() {
        let html = md.toHTML("> A quote")
        #expect(html.contains("<blockquote>"))
        #expect(html.contains("A quote"))
    }

    @Test func horizontalRule() {
        let html = md.toHTML("---")
        #expect(html.contains("<hr>"))
    }

    @Test func paragraph() {
        let html = md.toHTML("Hello world")
        #expect(html.contains("<p>Hello world</p>"))
    }
}

@Suite("MarkdownConverter – Escape Sequences (#8)")
struct EscapeTests {
    let md = MarkdownConverter()

    @Test func escapeAmpersand() {
        let result = md.esc("a & b")
        #expect(result == "a &amp; b")
    }

    @Test func escapeLessThan() {
        let result = md.esc("a < b")
        #expect(result == "a &lt; b")
    }

    @Test func escapeGreaterThan() {
        let result = md.esc("a > b")
        #expect(result == "a &gt; b")
    }

    @Test func multipleHTMLEntities() {
        let result = md.esc("<div class=\"x\">")
        #expect(result.contains("&lt;"))
        #expect(result.contains("&gt;"))
        #expect(!result.contains("<"))
    }
}

@Suite("MarkdownConverter – Multi-byte / Unicode Edge Cases")
struct UnicodeTests {
    let md = MarkdownConverter()

    @Test func chineseCharactersInHeading() {
        let html = md.toHTML("# 你好")
        #expect(html.contains("<h1>你好</h1>"))
    }

    @Test func emojiInParagraph() {
        let html = md.toHTML("Hello 🎉 world")
        #expect(html.contains("Hello 🎉 world"))
    }

    @Test func emojiInTableCell() {
        let markdown = "| Emoji | Value |\n|---|---|\n| 🎉 | party |"
        let html = md.toHTML(markdown)
        #expect(html.contains("<td>🎉</td>"))
        #expect(html.contains("<td>party</td>"))
    }

    @Test func mixedUnicodeInList() {
        let html = md.toHTML("- 日本語\n- العربية\n- Ελληνικά")
        #expect(html.contains("<li>日本語</li>"))
        #expect(html.contains("<li>العربية</li>"))
        #expect(html.contains("<li>Ελληνικά</li>"))
    }
}
