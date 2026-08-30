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

    private func makeHarness(
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
        textView.delegate = coordinator
        bridge.textView = textView
        coordinator.applyEditorMode(.screenplay, to: textView)
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
