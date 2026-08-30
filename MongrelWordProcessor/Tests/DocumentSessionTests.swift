import AppKit
import Combine
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import MongrelWordProcessor

final class DocumentSessionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        let suiteName = "MongrelWordProcessorTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MongrelWordProcessorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        defaults = nil
        temporaryDirectory = nil
    }

    @MainActor
    func testFreshDocumentCanBeSaved() {
        let session = makeSession()

        XCTAssertTrue(session.canSaveDocument)
        XCTAssertNil(session.currentURL)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testPlainTextSaveCreatesFileAndSubsequentSaveOverwritesIt() throws {
        let session = makeSession()
        let destination = temporaryDirectory.appendingPathComponent("First Draft.txt")

        session.attributedText = NSAttributedString(string: "First version")
        session.markDirty()

        XCTAssertTrue(session.saveDocument(to: destination, type: .plainText))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "First version")
        XCTAssertEqual(session.currentURL, destination)
        XCTAssertEqual(session.title, "First Draft")
        XCTAssertFalse(session.hasUnsavedChanges)

        session.attributedText = NSAttributedString(string: "Second version")
        session.markDirty()
        session.saveDocument()

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "Second version")
        XCTAssertFalse(session.hasUnsavedChanges)

        let reopened = makeSession()
        XCTAssertTrue(reopened.openDocument(at: destination))
        XCTAssertEqual(
            reopened.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            NSColor.labelColor
        )
    }

    @MainActor
    func testRTFRoundTripPreservesTextAndBasicFormatting() throws {
        let source = makeSession()
        let destination = temporaryDirectory.appendingPathComponent("Formatted.rtf")
        let text = NSMutableAttributedString(string: "Bold opening")
        text.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 18),
            range: NSRange(location: 0, length: 4)
        )
        source.attributedText = text
        source.markDirty()

        XCTAssertTrue(source.saveDocument(to: destination, type: .rtf))

        let reopened = makeSession()
        XCTAssertTrue(reopened.openDocument(at: destination))
        XCTAssertEqual(reopened.attributedText.string, "Bold opening")
        XCTAssertTrue(
            try XCTUnwrap(reopened.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
                .fontDescriptor.symbolicTraits.contains(.bold)
        )
        XCTAssertFalse(reopened.hasUnsavedChanges)
    }

    @MainActor
    func testWordDocumentRoundTripPreservesTextAndBasicFormatting() throws {
        let source = makeSession()
        let destination = temporaryDirectory.appendingPathComponent("Interchange.docx")
        let text = NSMutableAttributedString(string: "Word-compatible draft")
        text.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 16),
            range: NSRange(location: 0, length: 4)
        )
        source.attributedText = text
        source.markDirty()

        XCTAssertTrue(source.saveDocument(to: destination, type: .wordDocument))
        XCTAssertGreaterThan(try Data(contentsOf: destination).count, 0)

        let reopened = makeSession()
        XCTAssertTrue(reopened.openDocument(at: destination))
        XCTAssertEqual(
            reopened.attributedText.string.trimmingCharacters(in: .newlines),
            "Word-compatible draft"
        )
        XCTAssertTrue(
            try XCTUnwrap(reopened.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
                .fontDescriptor.symbolicTraits.contains(.bold)
        )
    }

    @MainActor
    func testNewDocumentResetsContentAndMetrics() {
        let session = makeSession()
        session.newScreenplay()

        session.newDocument()

        XCTAssertEqual(session.title, "Untitled")
        XCTAssertEqual(session.attributedText.length, 0)
        XCTAssertNil(session.currentURL)
        XCTAssertEqual(session.wordCount, 0)
        XCTAssertEqual(session.charCount, 0)
        XCTAssertEqual(session.screenplaySceneCount, 0)
        XCTAssertEqual(session.authoringMode, .prose)
        XCTAssertEqual(session.documentInsights, .empty)
    }

    @MainActor
    func testNewScreenplayStartsInSceneHeadingMode() {
        let session = makeSession()

        session.newScreenplay()

        XCTAssertEqual(session.title, "Untitled Screenplay")
        XCTAssertEqual(session.authoringMode, .screenplay)
        XCTAssertEqual(session.screenplayElement, .sceneHeading)
        XCTAssertEqual(session.attributedText.length, 0)
        XCTAssertNil(session.currentURL)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testOpenPanelSupportsNativeScreenplaysAndCommonTextFormats() {
        let openTypeIdentifiers = Set(DocumentSession.openableDocumentTypes.map(\.identifier))

        XCTAssertEqual(
            openTypeIdentifiers,
            Set([
                UTType.mongrelScreenplay.identifier,
                UTType.rtf.identifier,
                UTType.wordDocument.identifier,
                UTType.plainText.identifier
            ])
        )
    }

    @MainActor
    func testRecentDocumentsCanBeClearedWithoutDeletingFiles() throws {
        let session = makeSession()
        let destination = temporaryDirectory.appendingPathComponent("Recent.txt")
        session.attributedText = NSAttributedString(string: "Still on disk")

        XCTAssertTrue(session.saveDocument(to: destination, type: .plainText))
        XCTAssertEqual(session.recentDocuments.count, 1)

        session.clearRecentDocuments()

        XCTAssertTrue(session.recentDocuments.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    @MainActor
    func testMetricsAndSceneCountUpdateAfterEditing() {
        let session = makeSession()
        session.authoringMode = .screenplay
        session.attributedText = NSAttributedString(
            string: "INT. KITCHEN - MORNING\nA kettle screams.\nEXT. ROAD - NIGHT\n"
        )

        session.markDirty()

        XCTAssertEqual(session.wordCount, 11)
        XCTAssertEqual(session.screenplaySceneCount, 2)
        XCTAssertEqual(session.screenplayScenes.map(\.number), [1, 2])
        XCTAssertEqual(session.screenplayScenes.map(\.heading), ["INT. KITCHEN - MORNING", "EXT. ROAD - NIGHT"])
        XCTAssertEqual(session.screenplayScenes.map(\.location), [0, 41])
        XCTAssertGreaterThan(session.charCount, 0)
    }

    @MainActor
    func testDocumentInsightsMeasureScreenplayRhythmAndCharacters() {
        let session = makeSession()
        session.authoringMode = .screenplay
        let script = NSMutableAttributedString(
            string: "INT. LAB - NIGHT\nA monitor blinks.\nMARA\nWe have a signal.\nEXT. ROOF - DAWN\nWind rises.\nMARA\nIt followed us.\n"
        )
        let source = script.string as NSString
        var cueSearchRange = NSRange(location: 0, length: source.length)
        while cueSearchRange.length > 0 {
            let range = source.range(of: "MARA\n", options: [], range: cueSearchRange)
            guard range.location != NSNotFound else { break }
            script.addAttribute(.screenplayElement, value: ScreenplayElement.character.rawValue, range: range)
            let nextLocation = NSMaxRange(range)
            cueSearchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        let dialogueOne = source.range(of: "We have a signal.")
        let dialogueTwo = source.range(of: "It followed us.")
        script.addAttribute(.screenplayElement, value: ScreenplayElement.dialogue.rawValue, range: dialogueOne)
        script.addAttribute(.screenplayElement, value: ScreenplayElement.dialogue.rawValue, range: dialogueTwo)
        session.attributedText = script
        session.markDirty()

        XCTAssertEqual(session.screenplaySceneCount, 2)
        XCTAssertEqual(session.documentInsights.scenes.count, 2)
        XCTAssertGreaterThan(session.documentInsights.dialogueShare, 0)
        XCTAssertEqual(session.documentInsights.characters.first?.name, "MARA")
        XCTAssertEqual(session.documentInsights.characters.first?.cueCount, 2)
        XCTAssertGreaterThan(session.documentInsights.paragraphWordCounts.count, 0)
    }

    @MainActor
    func testNativeScreenplayRoundTripPreservesModeAndElementTags() throws {
        let source = makeSession()
        source.authoringMode = .screenplay
        let script = NSMutableAttributedString(
            string: "INT. ARCHIVE - NIGHT\nThe terminal flickers.\nMARA\nStill here.\n"
        )
        script.addAttribute(.screenplayElement, value: ScreenplayElement.sceneHeading.rawValue, range: NSRange(location: 0, length: 21))
        script.addAttribute(.screenplayElement, value: ScreenplayElement.action.rawValue, range: NSRange(location: 21, length: 23))
        script.addAttribute(.screenplayElement, value: ScreenplayElement.character.rawValue, range: NSRange(location: 44, length: 5))
        script.addAttribute(.screenplayElement, value: ScreenplayElement.dialogue.rawValue, range: NSRange(location: 49, length: 12))
        source.attributedText = script
        source.markDirty()
        let destination = temporaryDirectory.appendingPathComponent("Archive.mgscreenplay")

        XCTAssertTrue(source.saveDocument(to: destination))

        let reopened = makeSession()
        XCTAssertTrue(reopened.openDocument(at: destination))
        XCTAssertEqual(reopened.authoringMode, .screenplay)
        XCTAssertEqual(reopened.attributedText.string, script.string)
        XCTAssertEqual(screenplayElement(in: reopened.attributedText, at: 0), .sceneHeading)
        XCTAssertEqual(screenplayElement(in: reopened.attributedText, at: 22), .action)
        XCTAssertEqual(screenplayElement(in: reopened.attributedText, at: 45), .character)
        XCTAssertEqual(screenplayElement(in: reopened.attributedText, at: 50), .dialogue)
    }

    @MainActor
    func testLongScreenplayExportsAsMultiplePDFPages() throws {
        let session = makeSession()
        session.authoringMode = .screenplay
        let scenes = (1...90).map { index in
            "INT. ROOM \(index) - DAY\nA deliberately substantial action line fills the scripted page with useful layout material."
        }
        session.attributedText = NSAttributedString(string: scenes.joined(separator: "\n"))
        session.markDirty()

        let data = try XCTUnwrap(session.makePDFData())
        let pdf = try XCTUnwrap(PDFDocument(data: data))

        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, ScreenplayPageLayout.pageSize)
    }

    @MainActor
    func testDocumentStatusDistinguishesNewUnsavedAndSaved() {
        let session = makeSession()
        XCTAssertEqual(session.documentStatusLabel, "New")

        session.attributedText = NSAttributedString(string: "Work in progress")
        session.markDirty()
        XCTAssertEqual(session.documentStatusLabel, "Unsaved")

        let destination = temporaryDirectory.appendingPathComponent("Status.txt")
        XCTAssertTrue(session.saveDocument(to: destination, type: .plainText))
        XCTAssertEqual(session.documentStatusLabel, "Saved")
    }

    @MainActor
    func testWritingPreferencesClampAndPersist() {
        let session = makeSession()
        session.setEditorZoom(4)
        session.screenplayViewStyle = .clean
        session.typewriterMode = true

        XCTAssertEqual(session.editorZoom, 2)
        XCTAssertEqual(session.editorZoomPercentage, 200)

        let restored = makeSession()
        XCTAssertEqual(restored.editorZoom, 2)
        XCTAssertEqual(restored.screenplayViewStyle, .clean)
        XCTAssertTrue(restored.typewriterMode)

        restored.setEditorZoom(0.1)
        XCTAssertEqual(restored.editorZoom, 0.6)
        restored.resetEditorZoom()
        XCTAssertEqual(restored.editorZoom, 1)
    }

    @MainActor
    func testRepeatedPaginationReportsDoNotRepublishTheSameCount() {
        let session = makeSession()
        var reports: [Int] = []
        let subscription = session.$screenplayPageCount
            .dropFirst()
            .sink { reports.append($0) }

        session.updateRenderedScreenplayPageCount(1)
        session.updateRenderedScreenplayPageCount(2)
        session.updateRenderedScreenplayPageCount(2)

        XCTAssertEqual(reports, [2])
        withExtendedLifetime(subscription) {}
    }

    @MainActor
    func testManualZoomLeavesAutomaticScreenplayView() {
        let session = makeSession()
        session.authoringMode = .screenplay
        session.screenplayViewStyle = .fitWidth

        session.adjustEditorZoom(by: 0.1)

        XCTAssertEqual(session.screenplayViewStyle, .page)
        XCTAssertEqual(session.editorZoom, 1.1, accuracy: 0.001)
    }

    private func screenplayElement(in text: NSAttributedString, at location: Int) -> ScreenplayElement? {
        guard let raw = text.attribute(.screenplayElement, at: location, effectiveRange: nil) as? String else {
            return nil
        }
        return ScreenplayElement(rawValue: raw)
    }

    @MainActor
    private func makeSession() -> DocumentSession {
        DocumentSession(
            defaults: defaults,
            companionLexicon: MongrelDictionaryCompanionLexicon(headwords: [])
        )
    }
}
