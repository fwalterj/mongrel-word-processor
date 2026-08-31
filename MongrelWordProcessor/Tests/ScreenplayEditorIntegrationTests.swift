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
            bridge: bridge,
            companionLexicon: MongrelDictionaryCompanionLexicon(headwords: []),
            authoringMode: .screenplay,
            screenplayElement: .action,
            codeLanguage: .swift,
            codeTheme: .cobalt,
            codeUseTabs: false,
            codeTabWidth: 4,
            codeLineWrap: true,
            editorZoom: 1,
            typewriterMode: false
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
        let appearance = MongrelAppearancePreferences.shared
        let originalMode = appearance.mode
        defer { appearance.mode = originalMode }
        appearance.mode = .contrast
        let harness = makeHarness()

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
        appearance.mode = .standard
        let harness = makeHarness()

        harness.coordinator.applyEditorMode(.screenplay, to: harness.textView)

        let typingColor = try? XCTUnwrap(harness.textView.typingAttributes[.foregroundColor] as? NSColor)
        guard let ink = typingColor?.usingColorSpace(.deviceRGB) else {
            return XCTFail("Ink color could not be converted to RGB")
        }
        XCTAssertLessThan(ink.redComponent, 0.15)
        XCTAssertEqual(ink.redComponent, ink.greenComponent, accuracy: 0.001)
        XCTAssertEqual(ink.greenComponent, ink.blueComponent, accuracy: 0.001)
        guard let background = harness.textView.backgroundColor.usingColorSpace(.deviceRGB) else {
            return XCTFail("Page background could not be converted to RGB")
        }
        XCTAssertGreaterThan(background.redComponent, 0.9)
        XCTAssertGreaterThan(background.greenComponent, 0.9)
        XCTAssertGreaterThan(background.blueComponent, 0.8)
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

    private func makeHarness(
        authoringMode: AuthoringMode = .screenplay,
        onElementChange: @escaping (ScreenplayElement) -> Void = { _ in }
    ) -> (
        coordinator: TextKit2EditorView.Coordinator,
        textView: NSTextView,
        bridge: FormattingBridge
    ) {
        var attributedText = NSAttributedString(string: "")
        let bridge = FormattingBridge()
        let editor = TextKit2EditorView(
            attributedText: Binding(
                get: { attributedText },
                set: { attributedText = $0 }
            ),
            onEdit: {},
            onScreenplayElementChange: onElementChange,
            onPaginationChange: { _ in },
            bridge: bridge,
            companionLexicon: MongrelDictionaryCompanionLexicon(headwords: []),
            authoringMode: authoringMode,
            screenplayElement: .action,
            codeLanguage: .swift,
            codeTheme: .cobalt,
            codeUseTabs: false,
            codeTabWidth: 4,
            codeLineWrap: true,
            editorZoom: 1,
            typewriterMode: false
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
