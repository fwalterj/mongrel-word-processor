import AppKit
import SharedFoundation
import SwiftUI
import XCTest
@testable import MongrelWordProcessor

@MainActor
final class ScreenplayEditorIntegrationTests: XCTestCase {
    func testContrastDefaultsToBlackAndRemembersBothPolarityAndOtherPalettes() throws {
        let name = "ContrastPreferences-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = MongrelAppearancePreferences(defaults: defaults)
        XCTAssertEqual(preferences.mode, .contrast)
        XCTAssertEqual(preferences.contrastPolarity, .black)
        preferences.contrastPolarity = .white
        XCTAssertEqual(preferences.contrastRatio, 21, accuracy: 0.01)
        XCTAssertEqual(MongrelAppearancePreferences(defaults: defaults).contrastPolarity, .white)
        preferences.mode = .graphite
        let reopened = MongrelAppearancePreferences(defaults: defaults)
        XCTAssertEqual(reopened.mode, .graphite)
        XCTAssertEqual(reopened.contrastPolarity, .white)
    }

    func testBothContrastPolaritiesRenderAllModesWithoutChangingDocumentAttributes() throws {
        for mode in AuthoringMode.allCases {
            let harness = makeHarness(authoringMode: mode, useTextKit2: true)
            harness.textView.string = mode == .code ? "let answer = 42 // a comment\n" : "INT. ROOM - DAY\nA quiet room.\n"
            harness.coordinator.applyEditorMode(mode, to: harness.textView)
            harness.textView.setSelectedRange(NSRange(location: 4, length: 3))
            let original = NSAttributedString(attributedString: harness.textView.attributedString())
            for polarity in MongrelContrastPolarity.allCases {
                harness.coordinator.parent.contrastPolarity = polarity
                harness.coordinator.applyEditorPresentation(to: harness.textView)
                let value: CGFloat = polarity == .black ? 1 : 0
                assertColor(harness.textView.backgroundColor, red: 1 - value, green: 1 - value, blue: 1 - value)
                assertColor(harness.textView.insertionPointColor, red: value, green: value, blue: value)
                let manager = try XCTUnwrap(harness.textView.textLayoutManager)
                manager.ensureLayout(for: manager.documentRange)
                assertColor(try XCTUnwrap(renderedColor(in: manager, at: 0)), red: value, green: value, blue: value)
                XCTAssertTrue(harness.textView.attributedString().isEqual(to: original))
                XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 4, length: 3))
                let selectionInk = try XCTUnwrap(harness.textView.selectedTextAttributes[.foregroundColor] as? NSColor)
                assertColor(selectionInk, red: 1 - value, green: 1 - value, blue: 1 - value)
            }
            harness.coordinator.parent.contrastPolarity = nil
            harness.coordinator.applyEditorPresentation(to: harness.textView)
            XCTAssertNil(renderedColor(in: try XCTUnwrap(harness.textView.textLayoutManager), at: 0))
            XCTAssertTrue(harness.textView.attributedString().isEqual(to: original))
        }
    }

    func testContrastTypingKeepsExportInkAndUndoIntact() throws {
        let harness = makeHarness(authoringMode: .prose, contrastPolarity: .black, useTextKit2: true)
        harness.textView.allowsUndo = true
        let manager = try XCTUnwrap(harness.textView.textLayoutManager)
        let undo = try XCTUnwrap(harness.textView.undoManager)
        undo.beginUndoGrouping()
        harness.textView.insertText("A quiet page.\n", replacementRange: NSRange(location: 0, length: 0))
        undo.endUndoGrouping()
        manager.ensureLayout(for: manager.documentRange)
        assertColor(try XCTUnwrap(renderedColor(in: manager, at: 0)), red: 1, green: 1, blue: 1)
        let sourceInk = try XCTUnwrap(harness.coordinator.parent.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        XCTAssertEqual(sourceInk, harness.coordinator.parent.pageTextColor)
        harness.coordinator.parent.contrastPolarity = .white
        harness.coordinator.applyEditorPresentation(to: harness.textView)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(harness.textView.string, "")
        undo.redo()
        XCTAssertEqual(harness.textView.string, "A quiet page.\n")
        let archive = try MongrelDocumentArchive(attributedText: harness.coordinator.parent.attributedText, authoringMode: .prose, pageLayout: .empty)
        let restored = try archive.makeAttributedString()
        XCTAssertEqual(restored.string, "A quiet page.\n")
        let restoredInk = try XCTUnwrap(restored.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor).usingColorSpace(.sRGB)!
        XCTAssertLessThan(restoredInk.redComponent, 0.15)
    }

    func testCodeContrastUsesReadableNeutralSyntaxAndMonochromeLinks() throws {
        for polarity in MongrelContrastPolarity.allCases {
            let harness = makeHarness(authoringMode: .code, contrastPolarity: polarity, useTextKit2: true)
            harness.textView.string = "let answer = 42 // a comment\n"
            harness.coordinator.applyEditorMode(.code, to: harness.textView)
            let manager = try XCTUnwrap(harness.textView.textLayoutManager)
            manager.ensureLayout(for: manager.documentRange)
            let offset = (harness.textView.string as NSString).range(of: "comment").location
            let comment = try XCTUnwrap(renderedColor(in: manager, at: offset)?.usingColorSpace(.sRGB))
            XCTAssertEqual(comment.redComponent, comment.greenComponent, accuracy: 0.001)
            XCTAssertEqual(comment.greenComponent, comment.blueComponent, accuracy: 0.001)
            let expected: CGFloat = polarity == .black ? 0.66 : 0.34
            XCTAssertEqual(comment.redComponent, expected, accuracy: 0.01)
            let attrs = manager.renderingAttributes(forLink: "https://example.com", at: manager.documentRange.location)
            XCTAssertEqual(attrs[.foregroundColor] as? NSColor, polarity.foreground)
        }
    }

    func testContrastKeepsUnterminatedParagraphsVisibleDuringContinuedEditing() throws {
        for mode in AuthoringMode.allCases {
            for polarity in MongrelContrastPolarity.allCases {
                let harness = makeHarness(authoringMode: mode, contrastPolarity: polarity, useTextKit2: true)
                let manager = try XCTUnwrap(harness.textView.textLayoutManager)
                for addition in ["A quiet room.\n\nThe final paragraph", " continues.", "\nAnother line"] {
                    harness.textView.insertText(addition, replacementRange: harness.textView.selectedRange())
                    manager.ensureLayout(for: manager.documentRange)
                    let end = (harness.textView.string as NSString).length - 1
                    let ink = try XCTUnwrap(renderedColor(in: manager, at: end))
                    let value: CGFloat = polarity == .black ? 1 : 0
                    assertColor(ink, red: value, green: value, blue: value)
                }
            }
        }
    }

    func testContrastKeepsImportedHighlightsReadableWithoutChangingTheirSavedColors() throws {
        for mode in [AuthoringMode.prose, .screenplay] {
            let harness = makeHarness(authoringMode: mode, useTextKit2: true)
            let original = NSAttributedString(string: "Highlighted text", attributes: [
                .foregroundColor: NSColor.blue, .backgroundColor: NSColor.yellow,
                .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: NSColor.red
            ])
            harness.textView.textStorage?.setAttributedString(original)
            let manager = try XCTUnwrap(harness.textView.textLayoutManager)
            for polarity in MongrelContrastPolarity.allCases {
                harness.coordinator.parent.contrastPolarity = polarity
                harness.coordinator.applyEditorPresentation(to: harness.textView)
                manager.ensureLayout(for: manager.documentRange)
                var rendering: [NSAttributedString.Key: Any] = [:]
                manager.enumerateRenderingAttributes(from: manager.documentRange.location, reverse: false) { _, attributes, _ in
                    rendering = attributes
                    return false
                }
                let background = try XCTUnwrap(rendering[.backgroundColor] as? NSColor).usingColorSpace(.sRGB)!
                XCTAssertGreaterThan(background.alphaComponent, 0)
                XCTAssertLessThan(background.alphaComponent, 0.25)
                XCTAssertEqual(background.redComponent, background.blueComponent, accuracy: 0.001)
                XCTAssertEqual(rendering[.underlineColor] as? NSColor, polarity.foreground)
                XCTAssertTrue(harness.textView.attributedString().isEqual(to: original))
            }
        }
    }

    func testMultiscenePasteRefreshesContrastAcrossEveryFormattedParagraph() throws {
        let harness = makeHarness(contrastPolarity: .black, useTextKit2: true)
        let source = (1...18).map { "INT. ROOM \($0) - DAWN\n\nA quiet room.\n\nMARA\nSomeone has to speak first.\n\n" }.joined()
        harness.textView.insertText(source, replacementRange: NSRange(location: 0, length: 0))
        let manager = try XCTUnwrap(harness.textView.textLayoutManager)
        let text = harness.textView.string as NSString
        var offset = 0
        while offset < text.length {
            let paragraph = text.paragraphRange(for: NSRange(location: offset, length: 0))
            assertColor(try XCTUnwrap(renderedColor(in: manager, at: offset)), red: 1, green: 1, blue: 1)
            offset = NSMaxRange(paragraph)
        }
        XCTAssertEqual(harness.textView.string, source)
    }

    private func renderedColor(in manager: NSTextLayoutManager, at offset: Int) -> NSColor? {
        guard let content = manager.textContentManager else { return nil }
        var result: NSColor?
        manager.enumerateRenderingAttributes(from: content.documentRange.location, reverse: false) { _, attributes, range in
            let start = content.offset(from: content.documentRange.location, to: range.location)
            let end = content.offset(from: content.documentRange.location, to: range.endLocation)
            if offset >= start, offset < end { result = attributes[.foregroundColor] as? NSColor; return false }
            return true
        }
        return result
    }

    func testToolbarFormattingCanBeUndoneAndRedone() {
        for action in ["strike", "heading", "element", "suggestion"] {
            let view = UndoablePolishTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
            view.allowsUndo = true
            view.string = "Quiet room\nSecond paragraph."
            view.setSelectedRange(NSRange(location: 0, length: 5))
            let bridge = FormattingBridge()
            bridge.textView = view
            let before = NSAttributedString(attributedString: view.attributedString())
            view.testUndoManager.removeAllActions()
            view.testUndoManager.beginUndoGrouping()
            switch action {
            case "strike": bridge.strikethrough()
            case "heading": bridge.applyHeading(1)
            case "element": bridge.applyScreenplayElement(.sceneHeading)
            default: bridge.applySuggestion(ScreenplaySuggestion(label: "INT. ROOM - DAY", text: "INT. ROOM - DAY", element: .sceneHeading, behavior: .replaceParagraph))
            }
            view.testUndoManager.endUndoGrouping()
            let after = NSAttributedString(attributedString: view.attributedString())
            XCTAssertFalse(after.isEqual(to: before))
            XCTAssertTrue(view.testUndoManager.canUndo, action)
            guard view.testUndoManager.canUndo else { continue }
            view.testUndoManager.undo()
            XCTAssertTrue(view.attributedString().isEqual(to: before), action)
            view.testUndoManager.redo()
            XCTAssertTrue(view.attributedString().isEqual(to: after), action)
        }
    }

    func testExplicitUppercaseFormattingKeepsUnicodeSelectionOnItsText() {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        view.string = "straße\nSecond paragraph."
        view.setSelectedRange(NSRange(location: 0, length: 6))
        let bridge = FormattingBridge()
        bridge.textView = view
        bridge.applyScreenplayElement(.sceneHeading)
        XCTAssertEqual(view.string, "STRASSE\nSecond paragraph.")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 7))
    }

    func testSuggestionKeepsFollowingParagraphAndItsFormatting() {
        let harness = makeHarness()
        harness.textView.string = "INT. ROOM - DAY\r\nMara waits.\n"
        let action = (harness.textView.string as NSString).range(of: "Mara waits.")
        harness.textView.textStorage?.addAttribute(.screenplayElement, value: ScreenplayElement.action.rawValue, range: action)
        harness.textView.setSelectedRange(NSRange(location: 5, length: 0))
        harness.bridge.applySuggestion(ScreenplaySuggestion(label: "NIGHT", text: "NIGHT", element: .sceneHeading, behavior: .appendSlugSuffix))
        XCTAssertEqual(harness.textView.string, "INT. ROOM - NIGHT\r\nMara waits.\n")
        let after = (harness.textView.string as NSString).range(of: "Mara waits.")
        XCTAssertEqual(harness.textView.textStorage?.attribute(.screenplayElement, at: after.location, effectiveRange: nil) as? String, ScreenplayElement.action.rawValue)
    }

    func testExplicitAutoFormattingDoesNotReclassifyManualActionAsCharacter() {
        let harness = makeHarness()
        harness.textView.string = "NOTHING\nMara waits.\n"
        harness.textView.setSelectedRange(NSRange(location: 0, length: 7))
        harness.bridge.applyScreenplayElement(.action)
        harness.bridge.autoFormatEntireScreenplay()
        XCTAssertEqual(harness.textView.textStorage?.attribute(.screenplayManualElement, at: 0, effectiveRange: nil) as? String, ScreenplayElement.action.rawValue)
        XCTAssertEqual(harness.textView.textStorage?.attribute(.screenplayElement, at: 0, effectiveRange: nil) as? String, ScreenplayElement.action.rawValue)
    }

    func testAutoFormattingPreservesUnicodeParagraphSeparators() {
        let harness = makeHarness()
        harness.textView.string = "int. room - day\u{2029}Mara waits.\u{2029}"
        harness.bridge.autoFormatEntireScreenplay()
        XCTAssertEqual(harness.textView.string, "INT. ROOM - DAY\u{2029}Mara waits.\u{2029}")
    }

    func testLiveUnicodeCaseExpansionDoesNotLeaveTextBehindOnUndo() {
        let harness = makeHarness()
        let view = UndoablePolishTextView(frame: harness.textView.frame)
        view.allowsUndo = true
        view.delegate = harness.coordinator
        harness.coordinator.textView = view
        harness.bridge.textView = view
        harness.coordinator.applyEditorMode(.screenplay, to: view)
        view.testUndoManager.beginUndoGrouping()
        view.insertText("int. straße - day", replacementRange: NSRange(location: 0, length: 0))
        view.testUndoManager.endUndoGrouping()
        XCTAssertTrue(view.testUndoManager.canUndo)
        view.testUndoManager.undo()
        XCTAssertEqual(view.string, "")
        view.testUndoManager.redo()
        XCTAssertEqual(view.string.lowercased(), "int. straße - day")
    }

    func testOutOfBoundsFocusRequestsAreIgnoredWithoutOverflow() {
        let harness = makeHarness(authoringMode: .prose)
        harness.textView.string = "Safe draft"
        harness.textView.setSelectedRange(NSRange(location: 2, length: 0))
        harness.bridge.focusRange(NSRange(location: Int.max - 1, length: Int.max))
        harness.bridge.focusRange(NSRange(location: 1, length: Int.max))
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testPublishedEditorSnapshotDoesNotMutateBehindTheSessionsBack() {
        let harness = makeHarness(authoringMode: .prose)
        harness.textView.insertText("First", replacementRange: NSRange(location: 0, length: 0))
        let first = harness.coordinator.parent.attributedText
        harness.textView.insertText(" second", replacementRange: NSRange(location: 5, length: 0))
        XCTAssertEqual(first.string, "First")
        XCTAssertEqual(harness.coordinator.parent.attributedText.string, "First second")
    }

    func testFreshDocumentClearsPreviousHeadingStyleAndUndoHistory() {
        let harness = makeHarness(authoringMode: .prose)
        harness.textView.allowsUndo = true
        harness.textView.string = "A heading"
        harness.textView.setSelectedRange(NSRange(location: 0, length: 9))
        harness.bridge.applyHeading(1)
        harness.textView.setSelectedRange(NSRange(location: 9, length: 0))
        harness.textView.textStorage?.setAttributedString(NSAttributedString(string: ""))
        harness.coordinator.resetDocumentEditingState(in: harness.textView)
        let font = harness.textView.typingAttributes[.font] as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
        XCTAssertFalse(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? true)
        XCTAssertFalse(harness.textView.undoManager?.canUndo ?? true)
        harness.textView.insertText("A new draft.", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual((harness.textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize, 14)
    }

    func testEditorUndoManagersDoNotShareAWindowHistory() {
        let prose = makeHarness(authoringMode: .prose)
        let screenplay = makeHarness()
        prose.textView.allowsUndo = true
        screenplay.textView.allowsUndo = true
        XCTAssertNotNil(prose.textView.undoManager)
        XCTAssertNotNil(screenplay.textView.undoManager)
        XCTAssertFalse(prose.textView.undoManager === screenplay.textView.undoManager)
        prose.textView.undoManager?.beginUndoGrouping()
        prose.textView.insertText("Prose draft", replacementRange: NSRange(location: 0, length: 0))
        prose.textView.undoManager?.endUndoGrouping()
        XCTAssertTrue(prose.textView.undoManager?.canUndo ?? false)
        XCTAssertFalse(screenplay.textView.undoManager?.canUndo ?? true)
    }

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

    func testNativeClipboardPreservesCutSceneIdentityButSeparatesCopies() {
        let textView = ScreenplayTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.isScreenplayPaginationActive = true
        textView.string = "INT. ROOM - DAY\n"
        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        textView.textStorage?.addAttributes([.screenplaySceneIdentity: "stable-scene", .screenplayElement: ScreenplayElement.sceneHeading.rawValue], range: fullRange)
        textView.setSelectedRange(fullRange)
        let clipboard = NSPasteboard(name: NSPasteboard.Name("MongrelTest-\(UUID().uuidString)"))
        defer { clipboard.releaseGlobally() }
        clipboard.declareTypes([ScreenplayTextView.nativeSelectionType], owner: nil)
        XCTAssertTrue(textView.writeSelection(to: clipboard, type: ScreenplayTextView.nativeSelectionType))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(textView.readSelection(from: clipboard, type: ScreenplayTextView.nativeSelectionType))
        XCTAssertNotNil(textView.textStorage?.attribute(.screenplaySceneIdentity, at: 0, effectiveRange: nil))
        XCTAssertNotEqual(textView.textStorage?.attribute(.screenplaySceneIdentity, at: 0, effectiveRange: nil) as? String, "stable-scene")
        XCTAssertEqual(textView.textStorage?.attribute(.screenplaySceneIdentity, at: fullRange.length, effectiveRange: nil) as? String, "stable-scene")
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertTrue(textView.readSelection(from: clipboard, type: ScreenplayTextView.nativeSelectionType))
        XCTAssertEqual(textView.textStorage?.attribute(.screenplaySceneIdentity, at: 0, effectiveRange: nil) as? String, "stable-scene")
    }

    func testSceneNumbersHaveVisiblePlacementsWithTextKit2() {
        let content = NSTextContentStorage()
        let manager = NSTextLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 432, height: 10000))
        content.addTextLayoutManager(manager)
        manager.textContainer = container
        let textView = ScreenplayTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792), textContainer: container)
        textView.textContainerInset = NSSize(width: 90, height: 72)
        textView.string = "INT. HOUSE - NIGHT\nQuiet.\nEXT. ROAD - DAY\n"
        let second = (textView.string as NSString).range(of: "EXT.").location
        textView.numberedScenes = [ScreenplayScene(number: 1, heading: "INT. HOUSE - NIGHT", location: 0), ScreenplayScene(number: 2, heading: "EXT. ROAD - DAY", location: second)]
        manager.ensureLayout(for: manager.documentRange)
        let placements = textView.sceneNumberPlacements()
        XCTAssertEqual(placements.count, 2)
        guard placements.count == 2 else { return }
        XCTAssertEqual(placements.first?.0, "1")
        XCTAssertGreaterThanOrEqual(placements.first!.1.minY, 72)
        XCTAssertGreaterThan(placements.last!.1.minY, placements.first!.1.minY)
    }

    func testProseEditorTracksViewportWidth() {
        let harness = makeHarness(authoringMode: .prose)
        XCTAssertTrue(harness.textView.autoresizingMask.contains(.width))
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scrollView.documentView = harness.textView
        scrollView.setFrameSize(NSSize(width: 800, height: 400))
        scrollView.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(harness.textView.frame.width, 0)
    }

    func testPaginationExtendsItsPageBoundariesForLongScripts() {
        let harness = makeHarness()
        harness.textView.textContainer?.exclusionPaths = ScreenplayPageLayout.exclusionPaths(maximumPageCount: 2)
        harness.textView.string = String(repeating: "A door opens. A figure steps inside.\n", count: 600)
        harness.coordinator.updateScreenplayPagination(for: harness.textView)
        XCTAssertGreaterThan(harness.textView.textContainer!.exclusionPaths.count, 1)
        XCTAssertGreaterThan(harness.textView.frame.height, ScreenplayPageLayout.pageSize.height * 2)
    }

    func testMultilineInsertionFormatsAllParagraphsWithoutInheritingHeadingBold() {
        let harness = makeHarness()
        harness.bridge.configureTypingAttributes(for: .sceneHeading, in: harness.textView)
        let text = "INT. ROOM - DAY\nMara waits.\nMARA\nHello.\n"
        harness.textView.insertText(text, replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(harness.textView.string, text)
        let source = harness.textView.string as NSString
        let action = source.range(of: "Mara waits.")
        let dialogue = source.range(of: "Hello.")
        XCTAssertEqual(harness.textView.textStorage?.attribute(.screenplayElement, at: action.location, effectiveRange: nil) as? String, ScreenplayElement.action.rawValue)
        XCTAssertEqual(harness.textView.textStorage?.attribute(.screenplayElement, at: dialogue.location, effectiveRange: nil) as? String, ScreenplayElement.dialogue.rawValue)
        let font = harness.textView.textStorage?.attribute(.font, at: action.location, effectiveRange: nil) as! NSFont
        XCTAssertFalse(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
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
        XCTAssertNotNil(harness.textView.selectedTextAttributes[.backgroundColor] as? NSColor)
        XCTAssertNotNil(harness.textView.selectedTextAttributes[.foregroundColor] as? NSColor)
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

    func testCodeQuotesAndKeywordsInsideCommentsCannotChangeLaterTokens() throws {
        let harness = makeHarness(authoringMode: .code)
        harness.textView.string = "// an unmatched \" quote and let\nlet url = \"https://example.com\"\n/* let \"quoted\" 42 */\nlet answer = 42"
        harness.coordinator.applyEditorMode(.code, to: harness.textView)
        let source = harness.textView.string as NSString
        let storage = try XCTUnwrap(harness.textView.textStorage)
        let commentColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        for token in ["unmatched", "quote and let", "quoted", "42 */"] {
            let offset = source.range(of: token).location
            XCTAssertEqual(storage.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor, commentColor)
            let font = try XCTUnwrap(storage.attribute(.font, at: offset, effectiveRange: nil) as? NSFont)
            XCTAssertFalse(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        }
        let url = source.range(of: "https").location
        XCTAssertNotEqual(storage.attribute(.foregroundColor, at: url, effectiveRange: nil) as? NSColor, commentColor)
        let keyword = source.range(of: "let answer").location
        let keywordFont = try XCTUnwrap(storage.attribute(.font, at: keyword, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: keywordFont).contains(.boldFontMask))
    }

    func testLargeCodeBurstPreservesTextUndoAndTheFinalSyntaxSnapshot() throws {
        let harness = makeHarness(authoringMode: .code, contrastPolarity: .black, useTextKit2: true)
        harness.textView.allowsUndo = true
        let source = String(repeating: "let value = \"https://example.com\" // a comment with \"quotes\"\n", count: 8_000)
        harness.textView.string = source
        harness.coordinator.applyEditorMode(.code, to: harness.textView)
        harness.textView.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        let undo = try XCTUnwrap(harness.textView.undoManager)
        undo.removeAllActions()
        undo.beginUndoGrouping()
        let start = Date()
        for _ in 0..<80 { harness.textView.insertText(" ", replacementRange: harness.textView.selectedRange()) }
        let typingDuration = Date().timeIntervalSince(start)
        undo.endUndoGrouping()
        harness.coordinator.flushPendingCodeHighlighting()
        XCTAssertEqual(harness.textView.string, source + String(repeating: " ", count: 80))
        XCTAssertTrue(harness.coordinator.parent.attributedText.isEqual(to: harness.textView.attributedString()))
        undo.undo()
        XCTAssertEqual(harness.textView.string, source)
        undo.redo()
        XCTAssertEqual(harness.textView.string, source + String(repeating: " ", count: 80))
        harness.coordinator.flushPendingCodeHighlighting()
        let archive = try MongrelDocumentArchive(attributedText: harness.coordinator.parent.attributedText, authoringMode: .code, pageLayout: .empty)
        XCTAssertEqual(try archive.makeAttributedString().string, harness.textView.string)
        print("Large code: \(source.utf16.count) UTF-16 units, 80 native edits \(typingDuration)s")
    }

    func testPendingCodeHighlightCannotAlterAReplacementProseDocument() {
        let harness = makeHarness(authoringMode: .code, useTextKit2: true)
        harness.textView.insertText(String(repeating: "let answer = 42\n", count: 2_000), replacementRange: NSRange(location: 0, length: 0))
        let replacement = makeHarness(authoringMode: .prose)
        harness.coordinator.parent = replacement.coordinator.parent
        harness.coordinator.parent.documentID = UUID()
        harness.coordinator.parent.bridge.textView = harness.textView
        harness.textView.string = "A fresh prose draft."
        harness.coordinator.resetDocumentEditingState(in: harness.textView)
        let before = NSAttributedString(attributedString: harness.textView.attributedString())
        harness.coordinator.flushPendingCodeHighlighting()
        XCTAssertTrue(harness.textView.attributedString().isEqual(to: before))
    }

    func testDeletingAllCodeKeepsTheContrastCaretVisible() {
        let harness = makeHarness(authoringMode: .code, contrastPolarity: .black, useTextKit2: true)
        harness.textView.insertText("let answer = 42", replacementRange: NSRange(location: 0, length: 0))
        harness.textView.insertText("", replacementRange: NSRange(location: 0, length: harness.textView.string.utf16.count))
        XCTAssertEqual(harness.textView.string, "")
        assertColor(harness.textView.insertionPointColor, red: 1, green: 1, blue: 1)
    }

    func testCompletionIgnoresInvalidOrStaleNativeRanges() {
        let harness = makeHarness(authoringMode: .code)
        harness.textView.string = "le"
        for range in [NSRange(location: NSNotFound, length: 0), NSRange(location: 3, length: 1), NSRange(location: 0, length: Int.max)] {
            XCTAssertEqual(harness.coordinator.textView(harness.textView, completions: ["let"], forPartialWordRange: range, indexOfSelectedItem: nil), [])
        }
        XCTAssertEqual(harness.coordinator.textView(harness.textView, completions: [], forPartialWordRange: NSRange(location: 0, length: 2), indexOfSelectedItem: nil), ["let"])
    }

    func testNativeCompletionReentryPublishesTheCompletedTextOnlyOnce() {
        let harness = makeHarness(authoringMode: .code)
        let view = ReentrantCompletionTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        harness.coordinator.textView = view
        harness.bridge.textView = view
        view.delegate = harness.coordinator
        harness.coordinator.applyEditorMode(.code, to: view)
        view.insertText("le", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(view.completionCalls, 1)
        XCTAssertEqual(view.string, "let")
        XCTAssertEqual(harness.coordinator.parent.attributedText.string, "let")
        XCTAssertFalse(harness.coordinator.isApplyingEdit)
        view.insertText(" ", replacementRange: view.selectedRange())
        XCTAssertEqual(view.completionCalls, 1)
    }

    func testCodeCompletionDoesNotRewriteUndoOrRedo() throws {
        let harness = makeHarness(authoringMode: .code)
        let view = ReentrantCompletionTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.allowsUndo = true
        harness.coordinator.textView = view
        harness.bridge.textView = view
        view.delegate = harness.coordinator
        harness.coordinator.applyEditorMode(.code, to: view)
        view.string = "let"
        view.setSelectedRange(NSRange(location: 3, length: 0))
        let undo = try XCTUnwrap(view.undoManager)
        undo.removeAllActions()
        undo.beginUndoGrouping()
        view.insertText(" ", replacementRange: view.selectedRange())
        undo.endUndoGrouping()
        undo.undo()
        XCTAssertEqual(view.string, "let")
        XCTAssertEqual(view.completionCalls, 0)
        undo.redo()
        XCTAssertEqual(view.string, "let ")
        XCTAssertEqual(view.completionCalls, 0)
    }

    func testCodeCompletionSkipsCommentsStringsAndOrdinaryIdentifiers() {
        let harness = makeHarness(authoringMode: .code)
        let view = ReentrantCompletionTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        harness.coordinator.textView = view
        harness.bridge.textView = view
        view.delegate = harness.coordinator
        for (source, offset) in [("// co", 5), ("let message = \"co\"", 17), ("longIdentifier", 14)] {
            view.string = source
            harness.coordinator.applyEditorMode(.code, to: view)
            view.setSelectedRange(NSRange(location: offset, length: 0))
            view.insertText("n", replacementRange: view.selectedRange())
            XCTAssertEqual(view.completionCalls, 0, source)
        }
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

    func testZoomAndResizeReflowProseAndCodeWithoutMovingTheReadingAnchor() throws {
        for mode in [AuthoringMode.prose, .code] {
            let harness = makeHarness(authoringMode: mode, useTextKit2: true)
            let (window, viewport) = makeViewport(for: harness.textView)
            defer { window.close() }
            harness.textView.string = (1...80).map { "Paragraph \($0). " + String(repeating: "The city waited for the rain. ", count: 8) + "\n\n" }.joined()
            harness.coordinator.applyEditorMode(mode, to: harness.textView)
            viewport.synchronizeDocumentGeometry()
            let location = (harness.textView.string as NSString).range(of: "Paragraph 12.").location + 14
            let selection = NSRange(location: location, length: 8)
            harness.textView.setSelectedRange(selection)
            harness.textView.scrollRangeToVisible(selection)
            let original = NSAttributedString(attributedString: harness.textView.attributedString())
            let anchor = try XCTUnwrap(viewport.captureAnchor())
            for scale: CGFloat in [1.4, 2, 0.6, 1] {
                viewport.setEditorMagnification(scale)
                XCTAssertEqual(harness.textView.frame.width, viewport.documentVisibleRect.width, accuracy: 1)
                XCTAssertEqual(viewport.documentVisibleRect.minX, 0, accuracy: 1)
                XCTAssertEqual(harness.textView.selectedRange(), selection)
                let usage = try XCTUnwrap(harness.textView.textLayoutManager).usageBoundsForTextContainer
                XCTAssertGreaterThanOrEqual(harness.textView.frame.height, usage.maxY + harness.textView.textContainerInset.height * 2 - 1)
                let current = try XCTUnwrap(viewport.captureAnchor())
                XCTAssertEqual(current.location, anchor.location)
                XCTAssertEqual(current.viewportOffset.y, anchor.viewportOffset.y, accuracy: 3)
                XCTAssertTrue(harness.textView.attributedString().isEqual(to: original))
            }
            for width: CGFloat in [420, 900, 600] {
                viewport.setFrameSize(NSSize(width: width, height: 420))
                XCTAssertEqual(harness.textView.frame.width, viewport.documentVisibleRect.width, accuracy: 1)
                XCTAssertEqual(try XCTUnwrap(viewport.captureAnchor()).viewportOffset.y, anchor.viewportOffset.y, accuracy: 3)
                XCTAssertEqual(harness.textView.selectedRange(), selection)
            }
        }
    }

    func testZoomPreservesOffscreenSelectionAndAnchorsTheVisibleParagraph() throws {
        let harness = makeHarness(authoringMode: .prose, useTextKit2: true)
        let (window, viewport) = makeViewport(for: harness.textView)
        defer { window.close() }
        harness.textView.string = String(repeating: "A long paragraph with enough words to wrap over several lines.\n\n", count: 200)
        viewport.synchronizeDocumentGeometry()
        harness.textView.setSelectedRange(NSRange(location: 0, length: 0))
        viewport.contentView.scroll(to: NSPoint(x: 0, y: 900))
        let anchor = try XCTUnwrap(viewport.captureAnchor())
        XCTAssertGreaterThan(anchor.location, 0)
        viewport.setEditorMagnification(1.4)
        let restored = try XCTUnwrap(viewport.captureAnchor())
        XCTAssertEqual((harness.textView.string as NSString).paragraphRange(for: NSRange(location: restored.location, length: 0)),
                       (harness.textView.string as NSString).paragraphRange(for: NSRange(location: anchor.location, length: 0)))
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    func testReturningFocusForZoomPreservesAnOffscreenSelection() throws {
        let harness = makeHarness(authoringMode: .prose, useTextKit2: true)
        let (window, viewport) = makeViewport(for: harness.textView)
        defer { window.close() }
        harness.textView.string = String(repeating: "A paragraph with enough words to wrap across lines.\n\n", count: 200)
        viewport.synchronizeDocumentGeometry()
        harness.textView.setSelectedRange(NSRange(location: 0, length: 4))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        viewport.contentView.scroll(to: NSPoint(x: 0, y: 900))
        let anchor = try XCTUnwrap(viewport.captureAnchor())
        harness.bridge.focusEditor(revealSelection: false)
        XCTAssertTrue(window.firstResponder === harness.textView)
        XCTAssertEqual(harness.textView.selectedRange(), NSRange(location: 0, length: 4))
        let restored = try XCTUnwrap(viewport.captureAnchor())
        XCTAssertEqual(restored.location, anchor.location)
        XCTAssertEqual(restored.viewportOffset.y, anchor.viewportOffset.y, accuracy: 1)
    }

    func testNoWrapCanReturnToWrappingAfterMagnificationAndLongLine() throws {
        let harness = makeHarness(authoringMode: .code, useTextKit2: true)
        let (window, viewport) = makeViewport(for: harness.textView)
        defer { window.close() }
        harness.textView.string = String(repeating: "let value = 123; ", count: 200)
        harness.coordinator.applyLineWrap(false, to: viewport)
        viewport.setEditorMagnification(1.6)
        XCTAssertGreaterThan(harness.textView.frame.width, viewport.documentVisibleRect.width)
        XCTAssertTrue(viewport.hasHorizontalScroller)
        harness.coordinator.applyLineWrap(true, to: viewport)
        XCTAssertEqual(harness.textView.frame.width, viewport.documentVisibleRect.width, accuracy: 1)
        XCTAssertEqual(viewport.documentVisibleRect.minX, 0, accuracy: 1)
        XCTAssertFalse(viewport.hasHorizontalScroller)
        harness.textView.string = ""
        viewport.setEditorMagnification(0.6)
        viewport.setFrameSize(NSSize(width: 380, height: 250))
        XCTAssertEqual(harness.textView.frame.width, viewport.documentVisibleRect.width, accuracy: 1)
    }

    func testScreenplayZoomKeepsPageCountAndPrintGeometryUnchanged() throws {
        let harness = makeHarness(useTextKit2: true)
        let (window, viewport) = makeViewport(for: harness.textView)
        defer { window.close() }
        harness.coordinator.applyEditorMode(.screenplay, to: harness.textView)
        harness.textView.insertText(String(repeating: "INT. ROOM - DAY\n\nThe city waited for the rain.\n\n", count: 45), replacementRange: NSRange(location: 0, length: 0))
        harness.coordinator.updateScreenplayPagination(for: harness.textView)
        let editor = try XCTUnwrap(harness.textView as? ScreenplayTextView)
        let pages = editor.screenplayPageCount
        let original = NSAttributedString(attributedString: editor.attributedString())
        XCTAssertGreaterThan(pages, 1)
        for scale: CGFloat in [0.6, 1.4, 2, 1] {
            viewport.setEditorMagnification(scale)
            harness.coordinator.updateScreenplayPagination(for: editor)
            XCTAssertEqual(editor.frame.width, ScreenplayPageLayout.pageSize.width, accuracy: 0.01)
            XCTAssertEqual(editor.textContainer!.containerSize.width, ScreenplayPageLayout.contentWidth, accuracy: 0.01)
            XCTAssertEqual(editor.screenplayPageCount, pages)
            XCTAssertTrue(editor.attributedString().isEqual(to: original))
        }
    }

    func testFontSizeActionRestoresFocusPreservesSelectionAndUndoesSeparately() throws {
        let harness = makeHarness(authoringMode: .prose, useTextKit2: true)
        let (window, _) = makeViewport(for: harness.textView)
        defer { window.close() }
        let editor = harness.textView
        editor.allowsUndo = true
        let undo = try XCTUnwrap(editor.undoManager)
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        editor.insertText("First second", replacementRange: NSRange(location: 0, length: 0))
        undo.endUndoGrouping()
        let selection = NSRange(location: 0, length: 5)
        editor.setSelectedRange(selection)
        let original = try XCTUnwrap(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        window.contentView?.addSubview(field)
        window.makeFirstResponder(field)
        undo.beginUndoGrouping()
        harness.bridge.increaseFontSize()
        undo.endUndoGrouping()
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), selection)
        XCTAssertEqual(try XCTUnwrap(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).pointSize, original.pointSize + 1, accuracy: 0.01)
        undo.undo()
        XCTAssertEqual(editor.string, "First second")
        XCTAssertEqual(try XCTUnwrap(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).pointSize, original.pointSize, accuracy: 0.01)
        undo.redo()
        XCTAssertEqual(try XCTUnwrap(editor.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont).pointSize, original.pointSize + 1, accuracy: 0.01)
        undo.undo()
        undo.undo()
        XCTAssertEqual(editor.string, "")
        undo.beginUndoGrouping()
        editor.insertText("New branch", replacementRange: NSRange(location: 0, length: 0))
        undo.endUndoGrouping()
        XCTAssertFalse(undo.canRedo)
    }

    func testExternalScreenplayPasteUsesDestinationElementAndSingleUndo() throws {
        let harness = makeHarness(useTextKit2: true)
        let editor = try XCTUnwrap(harness.textView as? ScreenplayTextView)
        editor.allowsUndo = true
        editor.string = "Before after"
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        harness.bridge.applyScreenplayElement(.dialogue)
        editor.setSelectedRange(NSRange(location: 7, length: 0))
        let original = NSAttributedString(attributedString: editor.attributedString())
        let clipboard = NSPasteboard(name: NSPasteboard.Name("MongrelPaste-\(UUID().uuidString)"))
        defer { clipboard.releaseGlobally() }
        clipboard.setString("MARY\nINT. FALSE SCENE - NIGHT\nOrdinary words.\n", forType: .string)
        let undo = try XCTUnwrap(editor.undoManager)
        undo.removeAllActions()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        XCTAssertTrue(editor.pasteScreenplay(from: clipboard))
        undo.endUndoGrouping()
        editor.textStorage?.enumerateAttribute(.screenplayElement, in: NSRange(location: 7, length: editor.string.utf16.count - original.length)) { value, _, _ in
            XCTAssertEqual(value as? String, ScreenplayElement.dialogue.rawValue)
        }
        XCTAssertTrue(editor.string.contains("INT. FALSE SCENE - NIGHT"))
        undo.undo()
        XCTAssertTrue(editor.attributedString().isEqual(to: original))
        undo.redo()
        XCTAssertTrue(editor.string.contains("MARY\nINT."))
    }

    func testRichScreenplayPasteKeepsEmphasisButUsesDestinationGeometry() throws {
        let harness = makeHarness(useTextKit2: true)
        let editor = try XCTUnwrap(harness.textView as? ScreenplayTextView)
        editor.string = "Existing dialogue."
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        harness.bridge.applyScreenplayElement(.dialogue)
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 36), toHaveTrait: [.boldFontMask, .italicFontMask])
        let paragraph = NSMutableParagraphStyle()
        paragraph.headIndent = 200
        paragraph.lineSpacing = 40
        let source = NSAttributedString(string: "emphasis", attributes: [.font: font, .paragraphStyle: paragraph, .backgroundColor: NSColor.red, .underlineStyle: 1])
        let clipboard = NSPasteboard(name: NSPasteboard.Name("MongrelRichPaste-\(UUID().uuidString)"))
        defer { clipboard.releaseGlobally() }
        clipboard.setData(try source.data(from: NSRange(location: 0, length: source.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]), forType: .rtf)
        XCTAssertTrue(editor.pasteScreenplay(from: clipboard))
        let attributes = try XCTUnwrap(editor.textStorage?.attributes(at: 4, effectiveRange: nil))
        let pastedFont = try XCTUnwrap(attributes[.font] as? NSFont)
        XCTAssertEqual(pastedFont.pointSize, 12, accuracy: 0.01)
        XCTAssertTrue(NSFontManager.shared.traits(of: pastedFont).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: pastedFont).contains(.italicFontMask))
        XCTAssertEqual(attributes[.screenplayElement] as? String, ScreenplayElement.dialogue.rawValue)
        XCTAssertEqual((attributes[.backgroundColor] as? NSColor)?.alphaComponent ?? 0, 0, accuracy: 0.001)
        XCTAssertEqual(attributes[.underlineStyle] as? Int, 1)
        XCTAssertNotEqual((attributes[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing, 40)
    }

    func testExplicitParseCreatesScreenplayElementsAndNativePastePreservesThem() throws {
        let harness = makeHarness(useTextKit2: true)
        let editor = try XCTUnwrap(harness.textView as? ScreenplayTextView)
        editor.string = "Replace this dialogue."
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        harness.bridge.applyScreenplayElement(.dialogue)
        let clipboard = NSPasteboard(name: NSPasteboard.Name("MongrelParse-\(UUID().uuidString)"))
        defer { clipboard.releaseGlobally() }
        let source = "INT. ROOM - DAY\nA door opens.\nMARY\nHello there.\n"
        clipboard.setString(source, forType: .string)
        harness.bridge.pasteAndParseScreenplay(from: clipboard)
        XCTAssertEqual(editor.string, source)
        XCTAssertEqual(ScreenplayCatalog.analyze(editor.attributedString()).headings, ["INT. ROOM - DAY"])
        let expected: [(String, ScreenplayElement)] = [("INT.", .sceneHeading), ("A door", .action), ("MARY", .character), ("Hello", .dialogue)]
        for (text, element) in expected {
            let offset = (source as NSString).range(of: text).location
            XCTAssertEqual(editor.textStorage?.attribute(.screenplayElement, at: offset, effectiveRange: nil) as? String, element.rawValue)
            XCTAssertEqual(ScreenplayCatalog.elementTag(in: editor.attributedString(), at: offset), element)
        }
        editor.setSelectedRange(NSRange(location: 0, length: source.utf16.count))
        clipboard.clearContents()
        XCTAssertTrue(editor.writeSelection(to: clipboard, type: ScreenplayTextView.nativeSelectionType))
        editor.setSelectedRange(NSRange(location: source.utf16.count, length: 0))
        XCTAssertTrue(editor.readSelection(from: clipboard, type: ScreenplayTextView.nativeSelectionType))
        XCTAssertEqual(editor.string, source + source)
        for (text, element) in expected {
            let offset = source.utf16.count + (source as NSString).range(of: text).location
            XCTAssertEqual(editor.textStorage?.attribute(.screenplayElement, at: offset, effectiveRange: nil) as? String, element.rawValue)
        }
    }

    func testParsingAndUndoReportTheRestoredElement() throws {
        var reported = ScreenplayElement.action
        let harness = makeHarness(useTextKit2: true, onElementChange: { reported = $0 })
        let editor = harness.textView
        editor.allowsUndo = true
        editor.string = "Old dialogue."
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        harness.bridge.applyScreenplayElement(.dialogue)
        let clipboard = NSPasteboard(name: NSPasteboard.Name("MongrelParseState-\(UUID().uuidString)"))
        defer { clipboard.releaseGlobally() }
        clipboard.setString("INT. ROOM - DAY\nA door opens.\nMARY", forType: .string)
        let undo = try XCTUnwrap(editor.undoManager)
        undo.removeAllActions()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        harness.bridge.pasteAndParseScreenplay(from: clipboard)
        undo.endUndoGrouping()
        XCTAssertEqual(reported, .character)
        XCTAssertEqual(harness.bridge.activeScreenplayElement, .character)
        undo.undo()
        XCTAssertEqual(editor.string, "Old dialogue.")
        XCTAssertEqual(reported, .dialogue)
        undo.redo()
        XCTAssertEqual(reported, .character)
    }

    func testLargeCodeEditDoesNotRewriteFormattingOfUnchangedParagraphs() throws {
        let harness = makeHarness(authoringMode: .code, contrastPolarity: .black, useTextKit2: true)
        let source = String(repeating: "let answer = 42 // a quiet comment\n", count: 12_000)
        harness.textView.string = source
        harness.coordinator.applyEditorMode(.code, to: harness.textView)
        let recorder = EditorAttributeEditRecorder()
        let storage = try XCTUnwrap(harness.textView.textStorage)
        storage.delegate = recorder
        let offset = storage.length - 34 + 1
        harness.textView.setSelectedRange(NSRange(location: offset, length: 0))
        harness.textView.insertText("x", replacementRange: harness.textView.selectedRange())
        harness.coordinator.flushPendingCodeHighlighting()
        XCTAssertTrue(recorder.ranges.allSatisfy { $0.location >= offset - 2 && $0.length < 40 })
        XCTAssertEqual(harness.textView.string.utf16.count, source.utf16.count + 1)
        XCTAssertEqual(harness.coordinator.parent.attributedText.string, harness.textView.string)
    }

    func testSyntaxChangeStillPropagatesAcrossMultilineCommentBoundary() throws {
        let harness = makeHarness(authoringMode: .code, contrastPolarity: .black, useTextKit2: true)
        harness.textView.allowsUndo = true
        harness.textView.string = "/* comment */\nlet answer = 42\n" + String(repeating: "let other = 10\n", count: 2_000)
        harness.coordinator.applyEditorMode(.code, to: harness.textView)
        let storage = try XCTUnwrap(harness.textView.textStorage)
        let original = try XCTUnwrap(storage.attribute(.foregroundColor, at: 15, effectiveRange: nil) as? NSColor)
        harness.textView.insertText("", replacementRange: NSRange(location: 11, length: 2))
        harness.coordinator.flushPendingCodeHighlighting()
        // Close the comment later: the following lines must then become comments.
        harness.textView.insertText("*/", replacementRange: NSRange(location: 200, length: 0))
        harness.coordinator.flushPendingCodeHighlighting()
        XCTAssertNotEqual(storage.attribute(.foregroundColor, at: 15, effectiveRange: nil) as? NSColor, original)
        let undo = try XCTUnwrap(harness.textView.undoManager)
        XCTAssertTrue(undo.canUndo)
    }

    func testRepeatedUnchangedViewportTilingDoesNotRevisitDocumentLayout() throws {
        let harness = makeHarness(authoringMode: .prose, useTextKit2: true)
        let (window, viewport) = makeViewport(for: harness.textView)
        defer { window.close() }
        harness.textView.string = String(repeating: "A long paragraph with enough words to wrap across the canvas.\n\n", count: 7_000)
        viewport.synchronizeDocumentGeometry()
        let end = harness.textView.string.utf16.count - 20
        harness.textView.setSelectedRange(NSRange(location: end, length: 0))
        harness.textView.scrollRangeToVisible(harness.textView.selectedRange())
        let anchor = try XCTUnwrap(viewport.captureAnchor())
        let started = Date()
        for _ in 0..<1_000 { viewport.tile() }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertEqual(try XCTUnwrap(viewport.captureAnchor()).location, anchor.location)
    }

    func testLargeDocumentZoomMaterializesTheRestoredViewportAtDocumentEnd() throws {
        let harness = makeHarness(authoringMode: .prose, useTextKit2: true)
        let (window, viewport) = makeViewport(for: harness.textView)
        defer { window.close() }
        harness.textView.string = String(repeating: "A paragraph for the long document zoom regression.\n", count: 8_000)
        viewport.synchronizeDocumentGeometry()
        let end = harness.textView.string.utf16.count
        harness.textView.setSelectedRange(NSRange(location: end, length: 0))
        harness.textView.scrollRangeToVisible(harness.textView.selectedRange())
        for scale: CGFloat in [1.2, 1.6, 0.8] {
            viewport.setEditorMagnification(scale)
            let manager = try XCTUnwrap(harness.textView.textLayoutManager)
            let content = try XCTUnwrap(manager.textContentManager)
            let visible = try XCTUnwrap(manager.textViewportLayoutController.viewportRange)
            let last = content.offset(from: content.documentRange.location, to: visible.endLocation)
            XCTAssertEqual(last, end)
            XCTAssertEqual(harness.textView.selectedRange().location, end)
        }
    }

    private func makeViewport(for editor: NSTextView) -> (NSWindow, EditorScrollView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let viewport = EditorScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 420))
        viewport.minMagnification = 0.6
        viewport.maxMagnification = 2
        viewport.documentView = editor
        window.contentView = viewport
        window.makeFirstResponder(editor)
        return (window, viewport)
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
        contrastPolarity: MongrelContrastPolarity? = nil,
        useTextKit2: Bool = false,
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
            pageTextColor: pageColors.text.nsColor,
            contrastPolarity: contrastPolarity
        )
        let coordinator = editor.makeCoordinator()
        let textView: NSTextView
        if useTextKit2 {
            let content = NSTextContentStorage()
            let manager = NSTextLayoutManager()
            let container = NSTextContainer(size: NSSize(width: 432, height: 10000))
            content.addTextLayoutManager(manager)
            manager.textContainer = container
            textView = ScreenplayTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792), textContainer: container)
        } else {
            textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        }
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

private final class UndoablePolishTextView: NSTextView {
    let testUndoManager = UndoManager()
    override var undoManager: UndoManager? { testUndoManager }
}

private final class ReentrantCompletionTextView: NSTextView {
    var completionCalls = 0
    override func complete(_ sender: Any?) {
        completionCalls += 1
        // Native completion previews synchronously change text. Bound the probe
        // so a regression fails an assertion instead of crashing the test runner.
        if completionCalls < 4 {
            insertText("t", replacementRange: selectedRange())
        }
    }
}

private final class EditorAttributeEditRecorder: NSObject, NSTextStorageDelegate {
    var ranges: [NSRange] = []
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        ranges.append(editedRange)
    }
}
