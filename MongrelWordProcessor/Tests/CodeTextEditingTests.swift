import Foundation
import XCTest
@testable import MongrelWordProcessor

final class CodeTextEditingTests: XCTestCase {
    func testReturnBeforeEmojiPreservesUnicodeAndSelection() {
        for source in ["🙂", "let name = \"🙂\"", "{🙂}"] {
            let location = (source as NSString).range(of: "🙂").location
            let result = CodeTextEditing.insertNewline(in: source, selection: NSRange(location: location, length: 0), language: .swift, useTabs: false, tabWidth: 4)
            XCTAssertTrue(result.text.contains("🙂"))
            XCTAssertTrue(result.text.contains("\n"))
            XCTAssertTrue(NSMaxRange(result.selection) <= result.text.utf16.count)
        }
    }

    func testIndentedSelectionStaysWithinTheSelectedLines() {
        let result = CodeTextEditing.indent("one\ntwo\nthree", selection: NSRange(location: 0, length: 8), useTabs: false, tabWidth: 2)
        XCTAssertEqual(result.text, "  one\n  two\nthree")
        XCTAssertEqual(result.selection, NSRange(location: 2, length: 10))
        XCTAssertEqual((result.text as NSString).substring(with: result.selection), "one\n  two\n")
        let whole = CodeTextEditing.indent("one\ntwo", selection: NSRange(location: 0, length: 7), useTabs: false, tabWidth: 2)
        XCTAssertEqual(NSMaxRange(whole.selection), whole.text.utf16.count)
    }

    func testOutdentMapsPartialIndentAndMultilineSelectionExactly() {
        let source = "    one\n    two"
        let result = CodeTextEditing.outdent(source, selection: NSRange(location: 2, length: 8), tabWidth: 4)
        XCTAssertEqual(result.text, "one\ntwo")
        XCTAssertEqual(result.selection, NSRange(location: 0, length: 4))
        let caret = CodeTextEditing.outdent(source, selection: NSRange(location: 2, length: 0), tabWidth: 4)
        XCTAssertEqual(caret.selection, NSRange(location: 0, length: 0))
    }

    func testSourceEditingPreservesImportedLineEndings() {
        for newline in ["\r\n", "\r", "\u{2028}"] {
            let source = "first\(newline)second"
            let result = CodeTextEditing.insertNewline(in: source, selection: NSRange(location: source.utf16.count, length: 0), language: .swift, useTabs: false, tabWidth: 4)
            XCTAssertEqual(result.text, source + newline)
            let duplicate = CodeTextEditing.duplicateLines(source, selection: NSRange(location: source.utf16.count, length: 0))
            XCTAssertEqual(duplicate.text, source + newline + "second")
            let position = CodeTextEditing.cursorPosition(in: source, selection: NSRange(location: source.utf16.count, length: 99))
            XCTAssertEqual(position.line, 2)
            XCTAssertEqual(position.column, 7)
            XCTAssertEqual(position.selectionLength, 0)
        }
    }

    func testCursorPositionUsesUTF16OffsetsAndTracksSelection() {
        let text = "😀x\nabc"
        let location = ("😀x\na" as NSString).length

        let position = CodeTextEditing.cursorPosition(
            in: text,
            selection: NSRange(location: location, length: 2)
        )

        XCTAssertEqual(position.line, 2)
        XCTAssertEqual(position.column, 2)
        XCTAssertEqual(position.selectionLength, 2)
    }

    func testNewlineBetweenBracesCreatesIndentedBlankLine() {
        let result = CodeTextEditing.insertNewline(
            in: "func run() {}",
            selection: NSRange(location: 12, length: 0),
            language: .swift,
            useTabs: false,
            tabWidth: 4
        )

        XCTAssertEqual(result.text, "func run() {\n    \n}")
        XCTAssertEqual(result.selection, NSRange(location: 17, length: 0))
    }

    func testPythonColonCarriesIndentationForward() {
        let source = "    if ready:"
        let result = CodeTextEditing.insertNewline(
            in: source,
            selection: NSRange(location: (source as NSString).length, length: 0),
            language: .python,
            useTabs: false,
            tabWidth: 4
        )

        XCTAssertEqual(result.text, "    if ready:\n        ")
    }

    func testIndentAndOutdentSelectedLinesRoundTrip() {
        let source = "one\ntwo\n"
        let selection = NSRange(location: 0, length: (source as NSString).length)

        let indented = CodeTextEditing.indent(source, selection: selection, useTabs: false, tabWidth: 2)
        XCTAssertEqual(indented.text, "  one\n  two\n")

        let outdented = CodeTextEditing.outdent(indented.text, selection: indented.selection, tabWidth: 2)
        XCTAssertEqual(outdented.text, source)
    }

    func testToggleCommentPreservesIndentationAndReversesCleanly() {
        let source = "    let value = 3\n    return value\n"
        let selection = NSRange(location: 0, length: (source as NSString).length)

        let commented = CodeTextEditing.toggleLineComment(source, selection: selection, prefix: "//")
        XCTAssertEqual(commented.text, "    // let value = 3\n    // return value\n")

        let uncommented = CodeTextEditing.toggleLineComment(
            commented.text,
            selection: commented.selection,
            prefix: "//"
        )
        XCTAssertEqual(uncommented.text, source)
    }

    func testClosingBraceOutdentsWhitespaceOnlyLine() throws {
        let source = "if ready {\n    "
        let result = try XCTUnwrap(CodeTextEditing.insertClosingDelimiter(
            "}",
            in: source,
            selection: NSRange(location: (source as NSString).length, length: 0),
            tabWidth: 4
        ))

        XCTAssertEqual(result.text, "if ready {\n}")
        XCTAssertEqual(result.selection.location, (result.text as NSString).length)
    }

    func testDuplicateCurrentLinePlacesCaretOnDuplicate() {
        let result = CodeTextEditing.duplicateLines(
            "first\nsecond",
            selection: NSRange(location: 2, length: 0)
        )

        XCTAssertEqual(result.text, "first\nfirst\nsecond")
        XCTAssertEqual(result.selection.location, 8)
    }

    func testLanguageDetectionCoversCommonSourceExtensions() {
        let expectations: [(String, CodeLanguage)] = [
            ("main.swift", .swift),
            ("component.tsx", .typescript),
            ("script.py", .python),
            ("index.html", .html),
            ("theme.scss", .css),
            ("release.zsh", .shell),
            ("README.md", .markdown),
            ("compose.yml", .yaml),
            ("query.sql", .sql)
        ]

        for (filename, expected) in expectations {
            XCTAssertEqual(CodeLanguage.detected(from: URL(fileURLWithPath: filename)), expected, filename)
        }
        XCTAssertNil(CodeLanguage.detected(from: URL(fileURLWithPath: "draft.txt")))
    }

    func testShebangDetectionHandlesExtensionlessScripts() {
        XCTAssertEqual(CodeLanguage.detected(fromShebang: "#!/usr/bin/env python3\nprint('hi')"), .python)
        XCTAssertEqual(CodeLanguage.detected(fromShebang: "#!/bin/zsh\necho hi"), .shell)
        XCTAssertEqual(CodeLanguage.detected(fromShebang: "#!/usr/bin/env node\nconsole.log('hi')"), .javascript)
        XCTAssertNil(CodeLanguage.detected(fromShebang: "ordinary prose"))
    }
}
