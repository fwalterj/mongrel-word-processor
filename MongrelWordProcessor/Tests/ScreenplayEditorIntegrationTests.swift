import AppKit
import SharedFoundation
import SwiftUI
import XCTest
@testable import MongrelWordProcessor

@MainActor
final class ScreenplayEditorIntegrationTests: XCTestCase {
    func testScreenplayModeInstallsPageBreaksAndProseModeRemovesThem() {
        let harness = makeHarness()

        harness.coordinator.applyEditorMode(.screenplay, to: harness.textView)
        XCTAssertEqual(
            harness.textView.textContainer?.exclusionPaths.count,
            ScreenplayPageLayout.exclusionPaths().count
        )
        XCTAssertEqual(harness.textView.textContainerInset.width, ScreenplayPageLayout.horizontalInset)
        XCTAssertEqual(harness.textView.textContainerInset.height, ScreenplayPageLayout.verticalInset)

        harness.coordinator.applyEditorMode(.prose, to: harness.textView)
        XCTAssertEqual(harness.textView.textContainer?.exclusionPaths, [])
    }

    func testReturnAndTabCommandsDriveTheEditorElementState() {
        var reportedElement = ScreenplayElement.action
        let harness = makeHarness(onElementChange: { reportedElement = $0 })
        harness.textView.string = "MARA"
        harness.textView.setSelectedRange(NSRange(location: 4, length: 0))
        harness.bridge.applyScreenplayElement(.character, to: harness.textView, notifyTextChange: false)

        XCTAssertTrue(harness.coordinator.textView(
            harness.textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertEqual(harness.textView.string, "MARA\n")
        XCTAssertEqual(reportedElement, .dialogue)
        XCTAssertEqual(typingElement(in: harness.textView), .dialogue)

        XCTAssertTrue(harness.coordinator.textView(
            harness.textView,
            doCommandBy: #selector(NSResponder.insertTab(_:))
        ))
        XCTAssertEqual(reportedElement, .transition)
        XCTAssertEqual(typingElement(in: harness.textView), .transition)
    }

    func testScreenplayDelegatePreservesSpacesAcrossInsertedWords() {
        var editedText = NSAttributedString(string: "")
        var editCount = 0
        let bridge = FormattingBridge()
        let editor = TextKit2EditorView(
            attributedText: Binding(
                get: { editedText },
                set: { editedText = $0 }
            ),
            onEdit: { editCount += 1 },
            onScreenplayElementChange: { _ in },
            onPaginationChange: { _ in },
            onCodePositionChange: { _, _, _ in },
            bridge: bridge,
            companionLexicon: MongrelDictionaryCompanionLexicon(headwords: []),
            authoringMode: .screenplay,
            screenplayElement: .action,
            codeLanguage: .swift,
            codeTheme: .cobalt,
            codeFont: .systemMono,
            codeFontSize: 14,
            codeUseTabs: false,
            codeTabWidth: 4,
            codeLineWrap: true,
            editorZoom: 1,
            typewriterMode: false,
            pageBackgroundColor: DocumentPagePalette.warmPaper.colors(
                customBackground: DocumentRGBColor(hex: 0),
                customText: DocumentRGBColor(hex: 0)
            ).background.nsColor,
            pageTextColor: DocumentPagePalette.warmPaper.colors(
                customBackground: DocumentRGBColor(hex: 0),
                customText: DocumentRGBColor(hex: 0)
            ).text.nsColor
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        coordinator.textView = textView
        bridge.textView = textView
        textView.delegate = coordinator
        coordinator.applyEditorMode(.screenplay, to: textView)

        textView.insertText("A quiet room waits.", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertEqual(textView.string, "A quiet room waits.")
        XCTAssertEqual(editedText.string, "A quiet room waits.")
        XCTAssertEqual(editCount, 1)
    }

    func testContrastScreenplayUsesMatchingBlackPageAndWhiteText() {
        let harness = makeHarness(pagePalette: .contrast)

        harness.coordinator.applyEditorMode(.screenplay, to: harness.textView)

        XCTAssertTrue(harness.textView.drawsBackground)
        assertColor(harness.textView.backgroundColor, red: 0, green: 0, blue: 0)
        let typingColor = try? XCTUnwrap(harness.textView.typingAttributes[.foregroundColor] as? NSColor)
        assertColor(typingColor ?? .clear, red: 1, green: 1, blue: 1)
    }

    func testStandardScreenplayUsesDarkInkOnLightPaperInDarkSystemAppearance() {
        let appearance = MongrelAppearancePreferences.shared
        let originalMode = appearance.mode
        defer { appearance.mode = originalMode }
        appearance.mode = .contrast
        let harness = makeHarness(pagePalette: .warmPaper)

        harness.coordinator.applyEditorMode(.screenplay, to: harness.textView)

        let typingColor = try? XCTUnwrap(harness.textView.typingAttributes[.foregroundColor] as? NSColor)
        guard let ink = typingColor?.usingColorSpace(.deviceRGB) else {
            return XCTFail("Ink color could not be converted to RGB")
        }
        XCTAssertLessThan(ink.redComponent, 0.15)
        XCTAssertEqual(ink.redComponent, 24.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(ink.greenComponent, 22.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(ink.blueComponent, 18.0 / 255.0, accuracy: 0.001)
        guard let background = harness.textView.backgroundColor.usingColorSpace(.deviceRGB) else {
            return XCTFail("Page background could not be converted to RGB")
        }
        XCTAssertGreaterThan(background.redComponent, 0.9)
        XCTAssertGreaterThan(background.greenComponent, 0.9)
        XCTAssertGreaterThan(background.blueComponent, 0.8)
    }

    func testBuiltInLayoutPalettesMeetEnhancedContrast() {
        let appearance = MongrelAppearancePreferences.shared
        let originalMode = appearance.mode
        defer { appearance.mode = originalMode }

        for mode in MongrelAppearanceMode.allCases where mode != .custom {
            appearance.mode = mode
            XCTAssertGreaterThanOrEqual(appearance.contrastRatio, 7, mode.title)
        }
    }

    func testMagnifiedCanvasKeepsTheDocumentWidthVisible() {
        let harness = makeHarness()
        let scale: CGFloat = 1.4
        let scrollView = NSScrollView(frame: NSRect(
            origin: .zero,
            size: NSSize(
                width: ScreenplayPageLayout.pageSize.width * scale,
                height: ScreenplayPageLayout.pageSize.height * scale
            )
        ))
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = harness.textView
        harness.textView.setFrameSize(ScreenplayPageLayout.pageSize)

        harness.coordinator.updateMagnification(scale, in: scrollView)

        XCTAssertEqual(scrollView.documentVisibleRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(
            scrollView.documentVisibleRect.width,
            ScreenplayPageLayout.pageSize.width,
            accuracy: 1
        )
    }

    func testCodeNoWrapEnablesHorizontalScrolling() {
        let harness = makeHarness(authoringMode: .code)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scrollView.documentView = harness.textView

        harness.coordinator.applyLineWrap(false, to: scrollView)

        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertTrue(harness.textView.isHorizontallyResizable)
        XCTAssertFalse(harness.textView.textContainer?.widthTracksTextView ?? true)

        harness.coordinator.applyLineWrap(true, to: scrollView)

        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertFalse(harness.textView.isHorizontallyResizable)
        XCTAssertTrue(harness.textView.textContainer?.widthTracksTextView ?? false)
    }

    func testCodeCompletionScanHandlesEmojiWithoutCrashing() {
        let harness = makeHarness(authoringMode: .code)
        harness.textView.string = "😀a"
        harness.textView.setSelectedRange(NSRange(location: (harness.textView.string as NSString).length, length: 0))

        harness.coordinator.textDidChange(
            Notification(name: NSText.didChangeNotification, object: harness.textView)
        )

        XCTAssertEqual(harness.textView.string, "😀a")
    }

    func testCodeReturnAndTabCommandsUseIndentationPreferences() {
        let harness = makeHarness(authoringMode: .code, codeTabWidth: 2)
        harness.textView.string = "{}"
        harness.textView.setSelectedRange(NSRange(location: 1, length: 0))

        XCTAssertTrue(harness.coordinator.textView(
            harness.textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertEqual(harness.textView.string, "{\n  \n}")

        harness.textView.setSelectedRange(NSRange(location: 2, length: 2))
        XCTAssertTrue(harness.coordinator.textView(
            harness.textView,
            doCommandBy: #selector(NSResponder.insertTab(_:))
        ))
        XCTAssertTrue(harness.textView.string.contains("    "))
    }

    func testEmptyCodeDocumentStartsWithMonospacedTypingAttributes() throws {
        let harness = makeHarness(authoringMode: .code)

        harness.coordinator.applyEditorMode(.code, to: harness.textView)

        let font = try XCTUnwrap(harness.textView.typingAttributes[.font] as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertEqual(font.pointSize, 14)
        XCTAssertEqual(harness.textView.textContainerInset, NSSize(width: 28, height: 24))
        XCTAssertNotNil(harness.textView.typingAttributes[.foregroundColor] as? NSColor)
    }

    func testCodeTypographyPreferenceChangesRenderedFontSize() throws {
        let harness = makeHarness(authoringMode: .code, codeFont: .menlo, codeFontSize: 18)

        harness.coordinator.applyEditorMode(.code, to: harness.textView)

        let font = try XCTUnwrap(harness.textView.typingAttributes[.font] as? NSFont)
        XCTAssertEqual(font.pointSize, 18)
        XCTAssertTrue(font.fontName.localizedCaseInsensitiveContains("Menlo"))
    }

    func testURLInsideCodeStringDoesNotBecomeAComment() throws {
        let harness = makeHarness(authoringMode: .code, codeLanguage: .javascript)
        harness.textView.string = "const url = \"https://example.com\" // actual comment"

        harness.coordinator.applyEditorMode(.code, to: harness.textView)

        let source = harness.textView.string as NSString
        let stringColor = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .foregroundColor,
                at: source.range(of: "https").location,
                effectiveRange: nil
            ) as? NSColor
        )
        let commentColor = try XCTUnwrap(
            harness.textView.textStorage?.attribute(
                .foregroundColor,
                at: source.range(of: "actual").location,
                effectiveRange: nil
            ) as? NSColor
        )
        XCTAssertNotEqual(stringColor, commentColor)
    }

    func testLayoutContrastModeDoesNotFlattenCodeSyntaxColors() throws {
        let appearance = MongrelAppearancePreferences.shared
        let originalMode = appearance.mode
        defer { appearance.mode = originalMode }
        appearance.mode = .contrast
        let harness = makeHarness(authoringMode: .code)
        harness.textView.string = "let value = 42"

        harness.coordinator.applyEditorMode(.code, to: harness.textView)

        let keyword = try XCTUnwrap(
            harness.textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        let identifier = try XCTUnwrap(
            harness.textView.textStorage?.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        )
        XCTAssertNotEqual(keyword, identifier)
    }

    func testCodeSelectionReportsLineColumnAndSelectionLength() {
        var reported = (line: 0, column: 0, length: 0)
        let harness = makeHarness(
            authoringMode: .code,
            onCodePositionChange: { reported = ($0, $1, $2) }
        )
        harness.textView.string = "first\nsecond"
        harness.textView.setSelectedRange(NSRange(location: 8, length: 2))

        harness.coordinator.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: harness.textView)
        )

        XCTAssertEqual(reported.line, 2)
        XCTAssertEqual(reported.column, 3)
        XCTAssertEqual(reported.length, 2)
    }

    private func makeHarness(
        authoringMode: AuthoringMode = .screenplay,
        pagePalette: DocumentPagePalette = .warmPaper,
        codeLanguage: CodeLanguage = .swift,
        codeTheme: CodeTheme = .studio,
        codeFont: CodeFont = .systemMono,
        codeFontSize: CGFloat = 14,
        codeUseTabs: Bool = false,
        codeTabWidth: Int = 4,
        onCodePositionChange: @escaping (Int, Int, Int) -> Void = { _, _, _ in },
        onElementChange: @escaping (ScreenplayElement) -> Void = { _ in }
    ) -> (
        coordinator: TextKit2EditorView.Coordinator,
        textView: NSTextView,
        bridge: FormattingBridge
    ) {
        var attributedText = NSAttributedString(string: "")
        let bridge = FormattingBridge()
        let pageColors = pagePalette.colors(
            customBackground: DocumentRGBColor(hex: 0x121820),
            customText: DocumentRGBColor(hex: 0xF2F5F7)
        )
        let editor = TextKit2EditorView(
            attributedText: Binding(
                get: { attributedText },
                set: { attributedText = $0 }
            ),
            onEdit: {},
            onScreenplayElementChange: onElementChange,
            onPaginationChange: { _ in },
            onCodePositionChange: onCodePositionChange,
            bridge: bridge,
            companionLexicon: MongrelDictionaryCompanionLexicon(headwords: []),
            authoringMode: authoringMode,
            screenplayElement: .action,
            codeLanguage: codeLanguage,
            codeTheme: codeTheme,
            codeFont: codeFont,
            codeFontSize: codeFontSize,
            codeUseTabs: codeUseTabs,
            codeTabWidth: codeTabWidth,
            codeLineWrap: true,
            editorZoom: 1,
            typewriterMode: false,
            pageBackgroundColor: pageColors.background.nsColor,
            pageTextColor: pageColors.text.nsColor
        )
        let coordinator = editor.makeCoordinator()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        coordinator.textView = textView
        textView.delegate = coordinator
        bridge.textView = textView
        coordinator.applyEditorMode(authoringMode, to: textView)
        return (coordinator, textView, bridge)
    }

    private func typingElement(in textView: NSTextView) -> ScreenplayElement? {
        guard let raw = textView.typingAttributes[.screenplayElement] as? String else { return nil }
        return ScreenplayElement(rawValue: raw)
    }

    private func assertColor(
        _ color: NSColor,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            XCTFail("Color could not be converted to RGB", file: file, line: line)
            return
        }
        XCTAssertEqual(rgb.redComponent, red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.greenComponent, green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rgb.blueComponent, blue, accuracy: 0.001, file: file, line: line)
    }
}
