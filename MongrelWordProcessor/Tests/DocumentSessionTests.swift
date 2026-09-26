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
    func testCodeLineCountIncludesImportedWindowsAndUnicodeLineEndings() {
        let session = makeSession()
        for newline in ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"] {
            session.attributedText = NSAttributedString(string: "first\(newline)second\(newline)")
            XCTAssertEqual(session.codeLineCount, 3, newline.debugDescription)
        }
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
        let reopenedColor = try XCTUnwrap(
            reopened.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        assertColor(reopenedColor, matches: .labelColor)
    }

    @MainActor
    func testSaveRefusesToOverwriteExternallyChangedBackingFile() throws {
        let destination = temporaryDirectory.appendingPathComponent("Shared Draft.txt")
        try "Version from disk".write(to: destination, atomically: true, encoding: .utf8)
        var presentedErrors: [(String, String)] = []
        let session = makeSession { message, details in
            presentedErrors.append((message, details))
        }
        XCTAssertTrue(session.openDocument(at: destination))

        try "External revision".write(to: destination, atomically: true, encoding: .utf8)
        session.attributedText = NSAttributedString(string: "Local unsaved revision")
        session.markDirty()

        XCTAssertFalse(session.saveDocument(to: destination, type: .plainText))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "External revision")
        XCTAssertEqual(session.attributedText.string, "Local unsaved revision")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(presentedErrors.last?.0, "File Changed on Disk")
    }

    @MainActor
    func testSaveAsPreservesBothVersionsAfterExternalChange() throws {
        let original = temporaryDirectory.appendingPathComponent("Shared Draft.txt")
        let preservedCopy = temporaryDirectory.appendingPathComponent("Shared Draft Local.txt")
        try "Version from disk".write(to: original, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: original))

        try "External revision".write(to: original, atomically: true, encoding: .utf8)
        session.attributedText = NSAttributedString(string: "Local unsaved revision")
        session.markDirty()

        XCTAssertTrue(session.saveDocument(to: preservedCopy, type: .plainText))
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "External revision")
        XCTAssertEqual(try String(contentsOf: preservedCopy, encoding: .utf8), "Local unsaved revision")
        XCTAssertEqual(session.currentURL, preservedCopy)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testSaveCopyCannotReplaceActiveBackingFile() throws {
        let destination = temporaryDirectory.appendingPathComponent("Current Draft.txt")
        try "Current contents".write(to: destination, atomically: true, encoding: .utf8)
        var presentedErrors: [(String, String)] = []
        let session = makeSession { message, details in
            presentedErrors.append((message, details))
        }
        XCTAssertTrue(session.openDocument(at: destination))

        session.attributedText = NSAttributedString(string: "Untracked copy contents")
        session.markDirty()

        XCTAssertFalse(session.saveDocumentCopy(to: destination, type: .plainText))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "Current contents")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(presentedErrors.last?.0, "Choose a Different Filename")
    }

    @MainActor
    func testPlainTextImportDetectsUTF16Encoding() throws {
        let destination = temporaryDirectory.appendingPathComponent("Legacy Draft.txt")
        try "Café after midnight".write(to: destination, atomically: true, encoding: .utf16)

        let session = makeSession()

        XCTAssertTrue(session.openDocument(at: destination))
        XCTAssertEqual(session.attributedText.string, "Café after midnight")
        XCTAssertEqual(session.authoringMode, .prose)
        XCTAssertFalse(session.hasUnsavedChanges)
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
        text.addAttribute(
            .foregroundColor,
            value: NSColor.systemRed,
            range: NSRange(location: 5, length: 7)
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
        let reopenedRed = try XCTUnwrap(
            reopened.attributedText.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
        )
        guard let reopenedRGB = reopenedRed.usingColorSpace(.sRGB),
              let expectedRGB = NSColor.systemRed.usingColorSpace(.sRGB) else {
            return XCTFail("RTF colors could not be converted to sRGB")
        }
        XCTAssertEqual(reopenedRGB.redComponent, expectedRGB.redComponent, accuracy: 0.01)
        XCTAssertEqual(reopenedRGB.greenComponent, expectedRGB.greenComponent, accuracy: 0.01)
        XCTAssertEqual(reopenedRGB.blueComponent, expectedRGB.blueComponent, accuracy: 0.01)
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
    func testEmptyRichDocumentsCanBeSavedAndReopened() throws {
        for (filename, type) in [("Blank.rtf", UTType.rtf), ("Blank.docx", UTType.wordDocument)] {
            let destination = temporaryDirectory.appendingPathComponent(filename)
            let source = makeSession()

            XCTAssertTrue(source.saveDocument(to: destination, type: type), filename)
            XCTAssertGreaterThan(try Data(contentsOf: destination).count, 0, filename)

            let reopened = makeSession()
            XCTAssertTrue(reopened.openDocument(at: destination), filename)
            XCTAssertTrue(
                reopened.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                filename
            )
        }
    }

    @MainActor
    func testRTFDPreservesBodyImageAttachments() throws {
        let imageData = try makePNGData()
        let wrapper = FileWrapper(regularFileWithContents: imageData)
        wrapper.preferredFilename = "mark.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: try XCTUnwrap(NSImage(data: imageData)))
        let source = makeSession()
        source.attributedText = NSAttributedString(attachment: attachment)
        let destination = temporaryDirectory.appendingPathComponent("Image.rtfd", isDirectory: true)

        XCTAssertTrue(source.saveDocument(to: destination, type: .rtfd))
        source.markDirty()
        XCTAssertTrue(source.saveDocument(to: destination, type: .rtfd))

        let reopened = makeSession()
        XCTAssertTrue(reopened.openDocument(at: destination))
        XCTAssertNotNil(
            reopened.attributedText.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
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
    func testNewCodeDocumentUsesPersistedLanguageAndStartsClean() {
        defaults.set(CodeLanguage.python.rawValue, forKey: "wordprocessor.codeLanguage")
        let session = makeSession()

        session.newCodeDocument()

        XCTAssertEqual(session.title, "Untitled Source")
        XCTAssertEqual(session.authoringMode, .code)
        XCTAssertEqual(session.codeLanguage, .python)
        XCTAssertEqual(session.attributedText.length, 0)
        XCTAssertNil(session.currentURL)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testWorkspaceTabsRestoreMixedModeProjectsIndependently() throws {
        let session = makeSession()
        session.attributedText = NSAttributedString(string: "Prose notes")
        session.markDirty()
        let proseID = session.activeTabID

        session.newScreenplay()
        let screenplayID = session.activeTabID
        session.attributedText = NSAttributedString(string: "INT. STUDIO - NIGHT\n")
        session.pageLayout.header.isEnabled = true
        session.pageLayout.header.text = "Private draft"
        session.markDirty()

        session.newCodeDocument()
        let codeID = session.activeTabID
        session.codeLanguage = .sql
        session.attributedText = NSAttributedString(string: "print(\"ready\")\n")
        session.markDirty()

        XCTAssertEqual(session.workspaceTabs.count, 3)
        XCTAssertEqual(session.authoringMode, .code)

        session.switchToTab(try XCTUnwrap(proseID))
        XCTAssertEqual(session.authoringMode, .prose)
        XCTAssertEqual(session.attributedText.string, "Prose notes")
        XCTAssertTrue(session.hasUnsavedChanges)

        session.switchToTab(try XCTUnwrap(screenplayID))
        XCTAssertEqual(session.authoringMode, .screenplay)
        XCTAssertEqual(session.attributedText.string, "INT. STUDIO - NIGHT\n")
        XCTAssertEqual(session.pageLayout.header.text, "Private draft")

        session.switchToTab(try XCTUnwrap(codeID))
        XCTAssertEqual(session.authoringMode, .code)
        XCTAssertEqual(session.codeLanguage, .sql)
        XCTAssertEqual(session.attributedText.string, "print(\"ready\")\n")
    }

    @MainActor
    func testCodingModeUsesUserFacingCodingLabelAndReportsLineEndings() {
        let session = makeSession()

        XCTAssertEqual(AuthoringMode.code.title, "Coding")

        session.newCodeDocument()
        XCTAssertEqual(session.codeStorageSummary, "UTF-8 SAVE")
        session.attributedText = NSAttributedString(string: "one\r\ntwo\r\n")
        XCTAssertEqual(session.codeLineEndingSummary, "CRLF")

        session.attributedText = NSAttributedString(string: "one\rtwo\r")
        XCTAssertEqual(session.codeLineEndingSummary, "CR")

        session.attributedText = NSAttributedString(string: "one\ntwo\n")
        XCTAssertEqual(session.codeLineEndingSummary, "LF")
    }

    @MainActor
    func testDuplicateTabCreatesIndependentUnsavedCopyAcrossModes() throws {
        let session = makeSession()
        let destination = temporaryDirectory.appendingPathComponent("Original.mgscreenplay")
        session.newScreenplay()
        session.attributedText = NSAttributedString(string: "INT. STUDIO - NIGHT\n")
        session.pageLayout.header.isEnabled = true
        session.pageLayout.header.text = "Private"
        session.markDirty()
        XCTAssertTrue(session.saveDocument(to: destination, type: .mongrelScreenplay))
        let originalID = try XCTUnwrap(session.activeTabID)

        session.duplicateTab(originalID)
        let duplicateID = try XCTUnwrap(session.activeTabID)

        XCTAssertNotEqual(duplicateID, originalID)
        XCTAssertEqual(session.workspaceTabs.count, 2)
        XCTAssertEqual(session.title, "Original Copy")
        XCTAssertEqual(session.authoringMode, .screenplay)
        XCTAssertEqual(session.attributedText.string, "INT. STUDIO - NIGHT\n")
        XCTAssertEqual(session.pageLayout.header.text, "Private")
        XCTAssertNil(session.currentURL)
        XCTAssertTrue(session.hasUnsavedChanges)

        session.attributedText = NSAttributedString(string: "EXT. STREET - MORNING\n")
        session.markDirty()
        session.switchToTab(originalID)
        XCTAssertEqual(session.attributedText.string, "INT. STUDIO - NIGHT\n")
        XCTAssertEqual(session.currentURL, destination)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testAutosaveOnTabSwitchSavesNamedDocumentWithoutPrompt() throws {
        let destination = temporaryDirectory.appendingPathComponent("Autosave.txt")
        let session = makeSession()
        session.attributedText = NSAttributedString(string: "First")
        XCTAssertTrue(session.saveDocument(to: destination, type: .plainText))

        session.attributedText = NSAttributedString(string: "Second")
        session.markDirty()
        session.autosaveOnTabSwitch = true
        session.newScreenplay()

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "Second")
        let savedTab = try XCTUnwrap(session.workspaceTabs.first(where: { $0.url == destination }))
        XCTAssertFalse(savedTab.isDirty)
        XCTAssertEqual(session.authoringMode, .screenplay)
        XCTAssertTrue(makeSession().autosaveOnTabSwitch)
    }

    @MainActor
    func testAutosaveOnTabSwitchPreservesDraftWhenBackingFileChangedExternally() throws {
        let destination = temporaryDirectory.appendingPathComponent("Autosave Conflict.txt")
        var presentedErrors: [(String, String)] = []
        let session = makeSession { message, details in
            presentedErrors.append((message, details))
        }
        session.attributedText = NSAttributedString(string: "Saved baseline")
        XCTAssertTrue(session.saveDocument(to: destination, type: .plainText))
        let sourceID = try XCTUnwrap(session.activeTabID)

        session.attributedText = NSAttributedString(string: "Local unsaved continuation")
        session.markDirty()
        session.autosaveOnTabSwitch = true
        try "External edit that must survive".write(to: destination, atomically: true, encoding: .utf8)

        session.newScreenplay()

        XCTAssertEqual(
            try String(contentsOf: destination, encoding: .utf8),
            "External edit that must survive"
        )
        let sourceTab = try XCTUnwrap(session.workspaceTabs.first(where: { $0.id == sourceID }))
        XCTAssertTrue(sourceTab.isDirty)
        XCTAssertEqual(presentedErrors.first?.0, "File Changed on Disk")

        session.switchToTab(sourceID)
        XCTAssertEqual(session.attributedText.string, "Local unsaved continuation")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(session.currentURL, destination)
    }

    @MainActor
    func testUntitledDirtyTabSurvivesSwitchWithoutForcingSavePanel() throws {
        let session = makeSession()
        session.autosaveOnTabSwitch = true
        session.attributedText = NSAttributedString(string: "Unfiled thought")
        session.markDirty()
        let untitledID = try XCTUnwrap(session.activeTabID)

        session.newCodeDocument()
        XCTAssertEqual(session.workspaceTabs.count, 2)

        session.switchToTab(untitledID)
        XCTAssertEqual(session.attributedText.string, "Unfiled thought")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertNil(session.currentURL)
    }

    @MainActor
    func testTabSwitchRestoresCaretLocation() throws {
        let session = makeSession()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        textView.string = "First workspace"
        session.formattingBridge.textView = textView
        session.attributedText = NSAttributedString(string: textView.string)
        session.markDirty()
        textView.setSelectedRange(NSRange(location: 6, length: 3))
        let firstID = try XCTUnwrap(session.activeTabID)

        session.newCodeDocument()
        textView.string = "let value = 1"
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        session.switchToTab(firstID)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))

        XCTAssertEqual(textView.selectedRange(), NSRange(location: 6, length: 3))
    }

    @MainActor
    func testOpeningAnAlreadyOpenFileFocusesItsExistingTab() throws {
        let destination = temporaryDirectory.appendingPathComponent("Existing.py")
        try "print('one')\n".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()

        XCTAssertTrue(session.openDocument(at: destination))
        let sourceID = try XCTUnwrap(session.activeTabID)
        session.newScreenplay()
        XCTAssertEqual(session.workspaceTabs.count, 2)

        XCTAssertTrue(session.openDocument(at: destination))
        XCTAssertEqual(session.activeTabID, sourceID)
        XCTAssertEqual(session.workspaceTabs.count, 2)
        XCTAssertEqual(session.authoringMode, .code)
    }

    @MainActor
    func testReopeningActiveCleanFileReloadsExternalChanges() throws {
        let destination = temporaryDirectory.appendingPathComponent("Active Refresh.txt")
        try "Original contents".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: destination))

        try "Updated outside the app".write(to: destination, atomically: true, encoding: .utf8)
        XCTAssertTrue(session.openDocument(at: destination))

        XCTAssertEqual(session.workspaceTabs.count, 1)
        XCTAssertEqual(session.attributedText.string, "Updated outside the app")
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testReopeningActiveDirtyFileKeepsLocalDraft() throws {
        let destination = temporaryDirectory.appendingPathComponent("Active Dirty.txt")
        try "Original contents".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: destination))
        session.attributedText = NSAttributedString(string: "Local unfinished draft")
        session.markDirty()

        try "External version".write(to: destination, atomically: true, encoding: .utf8)
        XCTAssertTrue(session.openDocument(at: destination))

        XCTAssertEqual(session.workspaceTabs.count, 1)
        XCTAssertEqual(session.attributedText.string, "Local unfinished draft")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "External version")
    }

    @MainActor
    func testSwitchingToCleanTabReloadsExternalDiskChanges() throws {
        let destination = temporaryDirectory.appendingPathComponent("Background.txt")
        try "Original disk contents".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: destination))
        let fileTabID = try XCTUnwrap(session.activeTabID)
        session.newScreenplay()

        try "Updated outside Mongrel".write(to: destination, atomically: true, encoding: .utf8)
        session.switchToTab(fileTabID)

        XCTAssertEqual(session.attributedText.string, "Updated outside Mongrel")
        XCTAssertEqual(session.currentURL, destination)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testSwitchingToDeletedCleanTabPreservesARecoveredCopy() throws {
        let destination = temporaryDirectory.appendingPathComponent("Deleted Background.txt")
        try "Contents worth retaining".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: destination))
        let fileTabID = try XCTUnwrap(session.activeTabID)
        session.newScreenplay()

        try FileManager.default.removeItem(at: destination)
        session.switchToTab(fileTabID)

        XCTAssertEqual(session.attributedText.string, "Contents worth retaining")
        XCTAssertEqual(session.title, "Deleted Background (Recovered)")
        XCTAssertNil(session.currentURL)
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    @MainActor
    func testOpeningAFileDoesNotAbandonDirtyUntitledWork() throws {
        let destination = temporaryDirectory.appendingPathComponent("Reference.txt")
        try "Filed reference".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        session.attributedText = NSAttributedString(string: "Unfiled work")
        session.markDirty()
        let untitledID = try XCTUnwrap(session.activeTabID)

        XCTAssertTrue(session.openDocument(at: destination))
        XCTAssertEqual(session.workspaceTabs.count, 2)
        XCTAssertEqual(session.attributedText.string, "Filed reference")

        session.switchToTab(untitledID)
        XCTAssertEqual(session.attributedText.string, "Unfiled work")
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertNil(session.currentURL)
    }

    @MainActor
    func testOpeningSymlinkToOpenFileFocusesExistingTab() throws {
        let destination = temporaryDirectory.appendingPathComponent("Canonical.txt")
        let symlink = temporaryDirectory.appendingPathComponent("Alias.txt")
        try "One document".write(to: destination, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: destination)
        let session = makeSession()

        XCTAssertTrue(session.openDocument(at: destination))
        let sourceID = try XCTUnwrap(session.activeTabID)
        session.newScreenplay()

        XCTAssertTrue(session.openDocument(at: symlink))
        XCTAssertEqual(session.activeTabID, sourceID)
        XCTAssertEqual(session.workspaceTabs.count, 2)
    }

    @MainActor
    func testSaveAsRefusesToOverwriteFileOwnedByAnotherTab() throws {
        let destination = temporaryDirectory.appendingPathComponent("Owned.txt")
        try "Original contents".write(to: destination, atomically: true, encoding: .utf8)
        var presentedErrors: [(String, String)] = []
        let session = makeSession { message, details in
            presentedErrors.append((message, details))
        }
        XCTAssertTrue(session.openDocument(at: destination))
        session.newScreenplay()
        session.attributedText = NSAttributedString(string: "Competing contents")
        session.markDirty()

        XCTAssertFalse(session.saveDocument(to: destination, type: .plainText))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "Original contents")
        XCTAssertNil(session.currentURL)
        XCTAssertTrue(session.hasUnsavedChanges)
        XCTAssertEqual(presentedErrors.first?.0, "File Is Already Open")
        XCTAssertTrue(presentedErrors.first?.1.contains("Owned.txt") == true)
    }

    @MainActor
    func testClosingCleanBackgroundTabDoesNotChangeActiveTab() throws {
        let destination = temporaryDirectory.appendingPathComponent("Background.txt")
        try "Background document".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: destination))
        let backgroundID = try XCTUnwrap(session.activeTabID)
        session.newScreenplay()
        let foregroundID = try XCTUnwrap(session.activeTabID)

        session.closeTab(backgroundID)

        XCTAssertEqual(session.activeTabID, foregroundID)
        XCTAssertEqual(session.authoringMode, .screenplay)
        XCTAssertFalse(session.workspaceTabs.contains(where: { $0.id == backgroundID }))
        XCTAssertTrue(session.canReopenClosedTab)
    }

    @MainActor
    func testReopeningCleanClosedTabReloadsItsLatestDiskVersion() throws {
        let destination = temporaryDirectory.appendingPathComponent("Closed Reference.txt")
        try "Original reference".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: destination))
        let referenceID = try XCTUnwrap(session.activeTabID)
        session.newScreenplay()
        session.closeTab(referenceID)

        try "Externally revised reference".write(to: destination, atomically: true, encoding: .utf8)
        session.reopenClosedTab()

        XCTAssertEqual(session.attributedText.string, "Externally revised reference")
        XCTAssertEqual(session.currentURL, destination)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testReopeningDeletedCleanTabRetainsDetachedRecovery() throws {
        let destination = temporaryDirectory.appendingPathComponent("Closed Then Deleted.txt")
        try "Archived reference".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: destination))
        let referenceID = try XCTUnwrap(session.activeTabID)
        session.newScreenplay()
        session.closeTab(referenceID)

        try FileManager.default.removeItem(at: destination)
        session.reopenClosedTab()

        XCTAssertEqual(session.attributedText.string, "Archived reference")
        XCTAssertEqual(session.title, "Closed Then Deleted (Recovered)")
        XCTAssertNil(session.currentURL)
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    @MainActor
    func testReopeningClosedFileAlreadyOpenFocusesExistingTabWithoutDuplication() throws {
        let destination = temporaryDirectory.appendingPathComponent("Reopened.txt")
        try "One live copy".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()
        XCTAssertTrue(session.openDocument(at: destination))
        let originalID = try XCTUnwrap(session.activeTabID)
        session.newScreenplay()
        session.closeTab(originalID)
        XCTAssertTrue(session.openDocument(at: destination))
        let reopenedID = try XCTUnwrap(session.activeTabID)
        let countBeforeRestore = session.workspaceTabs.count

        session.reopenClosedTab()

        XCTAssertEqual(session.activeTabID, reopenedID)
        XCTAssertEqual(session.workspaceTabs.count, countBeforeRestore)
        XCTAssertFalse(session.canReopenClosedTab)
    }

    @MainActor
    func testClosingPristineBlankTabDoesNotPopulateClosedTabHistory() {
        let session = makeSession()

        session.closeDocument()

        XCTAssertEqual(session.workspaceTabs.count, 1)
        XCTAssertFalse(session.canReopenClosedTab)
        XCTAssertEqual(session.title, "Untitled")
        XCTAssertEqual(session.authoringMode, .prose)
    }

    @MainActor
    func testAutosaveSkipsLossyFormatWhenNativePageLayoutIsPresent() throws {
        let destination = temporaryDirectory.appendingPathComponent("Layout.txt")
        let session = makeSession()
        session.attributedText = NSAttributedString(string: "Saved body")
        XCTAssertTrue(session.saveDocument(to: destination, type: .plainText))
        let sourceID = try XCTUnwrap(session.activeTabID)

        session.attributedText = NSAttributedString(string: "Unsaved body")
        session.pageLayout.header.isEnabled = true
        session.pageLayout.header.text = "Keep this editable"
        session.markDirty()
        session.autosaveOnTabSwitch = true
        session.newCodeDocument()

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "Saved body")
        let sourceTab = try XCTUnwrap(session.workspaceTabs.first(where: { $0.id == sourceID }))
        XCTAssertTrue(sourceTab.isDirty)

        session.switchToTab(sourceID)
        XCTAssertEqual(session.attributedText.string, "Unsaved body")
        XCTAssertEqual(session.pageLayout.header.text, "Keep this editable")
    }

    @MainActor
    func testWorkspaceRecoveryRestoresMixedDirtyProjectsAndActiveTab() throws {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("MixedRecovery", isDirectory: true)
        var session: DocumentSession? = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        session?.attributedText = NSAttributedString(string: "Prose in progress")
        session?.markDirty()
        let proseID = try XCTUnwrap(session?.activeTabID)

        session?.newScreenplay()
        session?.attributedText = NSAttributedString(string: "INT. ARCHIVE - NIGHT\n")
        session?.pageLayout.header.isEnabled = true
        session?.pageLayout.header.text = "Recovery draft"
        session?.markDirty()
        let screenplayID = try XCTUnwrap(session?.activeTabID)

        session?.newCodeDocument()
        session?.codeLanguage = .sql
        session?.attributedText = NSAttributedString(string: "SELECT * FROM drafts;\n")
        session?.markDirty()
        let codeID = try XCTUnwrap(session?.activeTabID)
        session?.flushWorkspaceRecovery()
        session = nil

        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        XCTAssertEqual(restored.workspaceTabs.count, 3)
        XCTAssertEqual(restored.activeTabID, codeID)
        XCTAssertEqual(restored.authoringMode, .code)
        XCTAssertEqual(restored.codeLanguage, .sql)
        XCTAssertEqual(restored.attributedText.string, "SELECT * FROM drafts;\n")
        XCTAssertTrue(restored.hasUnsavedChanges)

        restored.switchToTab(screenplayID)
        XCTAssertEqual(restored.authoringMode, .screenplay)
        XCTAssertEqual(restored.pageLayout.header.text, "Recovery draft")
        XCTAssertEqual(restored.attributedText.string, "INT. ARCHIVE - NIGHT\n")

        restored.switchToTab(proseID)
        XCTAssertEqual(restored.authoringMode, .prose)
        XCTAssertEqual(restored.attributedText.string, "Prose in progress")
    }

    @MainActor
    func testWorkspaceRecoveryReloadsCleanNamedFileFromDisk() throws {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("NamedRecovery", isDirectory: true)
        let destination = temporaryDirectory.appendingPathComponent("LivingDocument.txt")
        var session: DocumentSession? = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        session?.attributedText = NSAttributedString(string: "Version one")
        XCTAssertTrue(try XCTUnwrap(session).saveDocument(to: destination, type: .plainText))
        session?.flushWorkspaceRecovery()
        session = nil

        try "Version two from disk".write(to: destination, atomically: true, encoding: .utf8)
        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        XCTAssertEqual(restored.attributedText.string, "Version two from disk")
        XCTAssertEqual(
            restored.currentURL?.standardizedFileURL.resolvingSymlinksInPath(),
            destination.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertFalse(restored.hasUnsavedChanges)
    }

    @MainActor
    func testWorkspaceRecoveryStillReadsVersionOneManifestWithoutFileIdentityFields() throws {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("LegacyRecovery", isDirectory: true)
        let destination = temporaryDirectory.appendingPathComponent("LegacyRecovery.txt")
        var session: DocumentSession? = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        session?.attributedText = NSAttributedString(string: "Legacy recovery contents")
        XCTAssertTrue(try XCTUnwrap(session).saveDocument(to: destination, type: .plainText))
        session?.flushWorkspaceRecovery()
        session = nil

        let manifestURL = recoveryDirectory.appendingPathComponent("WorkspaceRecovery.json")
        let manifestData = try Data(contentsOf: manifestURL)
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )
        var tabs = try XCTUnwrap(manifest["tabs"] as? [[String: Any]])
        for index in tabs.indices {
            tabs[index].removeValue(forKey: "fileNumber")
            tabs[index].removeValue(forKey: "systemNumber")
        }
        manifest["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL, options: .atomic)

        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        XCTAssertEqual(restored.attributedText.string, "Legacy recovery contents")
        XCTAssertEqual(
            restored.currentURL?.standardizedFileURL.resolvingSymlinksInPath(),
            destination.standardizedFileURL.resolvingSymlinksInPath()
        )
        XCTAssertFalse(restored.hasUnsavedChanges)
    }

    @MainActor
    func testWorkspaceRecoveryPreservesDirtyNamedDraftOverChangedDiskFile() throws {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("DirtyNamedRecovery", isDirectory: true)
        let destination = temporaryDirectory.appendingPathComponent("ConflictedDraft.txt")
        var session: DocumentSession? = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        session?.attributedText = NSAttributedString(string: "Saved version")
        XCTAssertTrue(try XCTUnwrap(session).saveDocument(to: destination, type: .plainText))
        session?.attributedText = NSAttributedString(string: "Unsaved recovered version")
        session?.markDirty()
        session?.flushWorkspaceRecovery()
        session = nil

        try "External disk version".write(to: destination, atomically: true, encoding: .utf8)
        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        XCTAssertEqual(restored.attributedText.string, "Unsaved recovered version")
        XCTAssertTrue(restored.hasUnsavedChanges)
        XCTAssertEqual(restored.title, "ConflictedDraft (Recovered Conflict)")
        XCTAssertNil(restored.currentURL)
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "External disk version")
    }

    @MainActor
    func testWorkspaceRecoveryKeepsOriginalDiskBaselineWhenExternalChangePrecedesSnapshot() throws {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("DirtyBaselineRecovery", isDirectory: true)
        let destination = temporaryDirectory.appendingPathComponent("BaselineConflict.txt")
        var session: DocumentSession? = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        session?.attributedText = NSAttributedString(string: "Saved baseline")
        XCTAssertTrue(try XCTUnwrap(session).saveDocument(to: destination, type: .plainText))
        session?.attributedText = NSAttributedString(string: "Local unsaved continuation")
        session?.markDirty()

        try "External edit before recovery flush".write(to: destination, atomically: true, encoding: .utf8)
        session?.flushWorkspaceRecovery()
        session = nil

        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        XCTAssertEqual(restored.attributedText.string, "Local unsaved continuation")
        XCTAssertEqual(restored.title, "BaselineConflict (Recovered Conflict)")
        XCTAssertNil(restored.currentURL)
        XCTAssertTrue(restored.hasUnsavedChanges)
        XCTAssertEqual(
            try String(contentsOf: destination, encoding: .utf8),
            "External edit before recovery flush"
        )
    }

    @MainActor
    func testWorkspaceRecoveryKeepsDirtyNamedDraftAttachedWhenDiskIsUnchanged() throws {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("DirtyUnchangedRecovery", isDirectory: true)
        let destination = temporaryDirectory.appendingPathComponent("OngoingDraft.txt")
        var session: DocumentSession? = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        session?.attributedText = NSAttributedString(string: "Saved version")
        XCTAssertTrue(try XCTUnwrap(session).saveDocument(to: destination, type: .plainText))
        session?.attributedText = NSAttributedString(string: "Unsaved continuation")
        session?.markDirty()
        session?.flushWorkspaceRecovery()
        session = nil

        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        XCTAssertEqual(restored.attributedText.string, "Unsaved continuation")
        XCTAssertTrue(restored.hasUnsavedChanges)
        XCTAssertEqual(restored.title, "OngoingDraft")
        XCTAssertEqual(
            restored.currentURL?.standardizedFileURL.resolvingSymlinksInPath(),
            destination.standardizedFileURL.resolvingSymlinksInPath()
        )
    }

    @MainActor
    func testWorkspaceRecoveryPreservesDeletedNamedFileAsUnsavedCopy() throws {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("MissingFileRecovery", isDirectory: true)
        let destination = temporaryDirectory.appendingPathComponent("DeletedDraft.txt")
        var session: DocumentSession? = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        session?.attributedText = NSAttributedString(string: "Do not lose this")
        XCTAssertTrue(try XCTUnwrap(session).saveDocument(to: destination, type: .plainText))
        session?.flushWorkspaceRecovery()
        session = nil
        try FileManager.default.removeItem(at: destination)

        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        XCTAssertEqual(restored.attributedText.string, "Do not lose this")
        XCTAssertEqual(restored.title, "DeletedDraft (Recovered)")
        XCTAssertNil(restored.currentURL)
        XCTAssertTrue(restored.hasUnsavedChanges)
    }

    @MainActor
    func testCorruptWorkspaceRecoveryIsQuarantinedAndStartsClean() throws {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("CorruptRecovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: recoveryDirectory.appendingPathComponent("WorkspaceRecovery.json")
        )

        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        XCTAssertEqual(restored.workspaceTabs.count, 1)
        XCTAssertEqual(restored.title, "Untitled")
        XCTAssertFalse(restored.hasUnsavedChanges)
        let recoveryFiles = try FileManager.default.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(recoveryFiles.contains(where: { $0.lastPathComponent == "WorkspaceRecovery.json" }))
        XCTAssertTrue(recoveryFiles.contains(where: { $0.lastPathComponent.hasPrefix("WorkspaceRecovery-corrupt-") }))
    }

    @MainActor
    func testRecoveryDetachesCleanDraftWhenItsBackingFileBecameUnreadable() throws {
        let recovery = temporaryDirectory.appendingPathComponent("UnreadableRecovery")
        let destination = temporaryDirectory.appendingPathComponent("Draft.mongreldoc")
        var source: DocumentSession? = makeSession(workspaceRecoveryDirectory: recovery)
        source?.attributedText = NSAttributedString(string: "The recoverable draft.")
        source?.markDirty()
        XCTAssertTrue(source!.saveDocument(to: destination, type: .mongrelDocument))
        source?.flushWorkspaceRecovery()
        source = nil
        try Data("broken document".utf8).write(to: destination)
        let restored = makeSession(workspaceRecoveryDirectory: recovery)
        XCTAssertEqual(restored.attributedText.string, "The recoverable draft.")
        XCTAssertNil(restored.currentURL)
        XCTAssertTrue(restored.hasUnsavedChanges)
        XCTAssertTrue(restored.title.contains("Recovered"))
        XCTAssertEqual(try String(contentsOf: destination), "broken document")
    }

    @MainActor
    func testRecoveryGivesDuplicateTabIdentifiersIndependentOwnership() throws {
        let recovery = temporaryDirectory.appendingPathComponent("DuplicateIDRecovery")
        var source: DocumentSession? = makeSession(workspaceRecoveryDirectory: recovery)
        source?.attributedText = NSAttributedString(string: "First recoverable draft")
        source?.markDirty()
        source?.newDocument()
        source?.attributedText = NSAttributedString(string: "Second recoverable draft")
        source?.markDirty()
        source?.flushWorkspaceRecovery()
        source = nil
        let url = recovery.appendingPathComponent("WorkspaceRecovery.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var tabs = try XCTUnwrap(json["tabs"] as? [[String: Any]])
        tabs[1]["id"] = tabs[0]["id"]
        json["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let restored = makeSession(workspaceRecoveryDirectory: recovery)
        XCTAssertEqual(restored.workspaceTabs.count, 2)
        XCTAssertEqual(Set(restored.workspaceTabs.map(\.id)).count, 2)
        var contents = Set<String>()
        for tab in restored.workspaceTabs {
            restored.switchToTab(tab.id)
            contents.insert(restored.attributedText.string)
        }
        XCTAssertEqual(contents, ["First recoverable draft", "Second recoverable draft"])
    }

    @MainActor
    func testSeededMixedDocumentLifecyclePreservesEveryDraft() throws {
        let recovery = temporaryDirectory.appendingPathComponent("LifecycleStress")
        let session = makeSession(workspaceRecoveryDirectory: recovery)
        var expected = [session.activeTabID!: ""]
        var seed: UInt64 = 0x4D4F4E4752454C
        var exercised = Set<Int>()
        for step in 0..<240 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let operation = Int((seed >> 32) % 8)
            exercised.insert(operation)
            switch operation {
            case 0:
                if step.isMultiple(of: 2) { session.newScreenplay() } else { session.newDocument() }
                expected[session.activeTabID!] = ""
            case 1:
                let value = "INT. ROOM \(step) - NIGHT\nCafé 👩🏽‍💻 — Straße.\r\n" + String(repeating: "A quiet line.\n", count: step % 31)
                session.attributedText = NSAttributedString(string: value)
                // Switch/save/recover before deferred analysis has an opportunity to run.
                session.markDirty(deferMetrics: true)
                expected[session.activeTabID!] = value
            case 2:
                let tabs = session.workspaceTabs
                session.switchToTab(tabs[Int(seed % UInt64(tabs.count))].id)
            case 3:
                let contents = expected[session.activeTabID!]
                session.duplicateTab(session.activeTabID!)
                expected[session.activeTabID!] = contents
            case 4, 5:
                let destination = temporaryDirectory.appendingPathComponent("Stress-\(session.activeTabID!).mongreldoc")
                XCTAssertTrue(session.saveDocument(to: destination, type: .mongrelDocument))
                if operation == 5 { XCTAssertTrue(session.openDocument(at: destination)) }
            case 6:
                if let clean = session.workspaceTabs.first(where: { !$0.isDirty }), session.workspaceTabs.count > 1 {
                    session.closeTab(clean.id)
                    expected.removeValue(forKey: clean.id)
                }
            default:
                if session.authoringMode == .screenplay { session.screenplaySettings.draft = .production }
            }
            XCTAssertEqual(session.attributedText.string, expected[session.activeTabID!], "Step \(step)")
            XCTAssertEqual(Set(session.workspaceTabs.map(\.id)), Set(expected.keys))
            if step.isMultiple(of: 24) {
                session.flushWorkspaceRecovery()
                let restored = makeSession(workspaceRecoveryDirectory: recovery)
                // A single pristine empty tab deliberately has no recovery file.
                if expected.count > 1 || session.hasUnsavedChanges || session.currentURL != nil {
                    XCTAssertEqual(restored.activeTabID, session.activeTabID)
                    XCTAssertEqual(Set(restored.workspaceTabs.map(\.id)), Set(expected.keys))
                    for tab in restored.workspaceTabs {
                        restored.switchToTab(tab.id)
                        XCTAssertEqual(restored.attributedText.string, expected[tab.id], "Recovered at step \(step)")
                    }
                }
            }
        }
        XCTAssertEqual(exercised.count, 8)
        session.flushWorkspaceRecovery()
    }

    @MainActor
    func testPristineWorkspaceDoesNotCreateRecoveryManifest() {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("EmptyRecovery", isDirectory: true)
        let session = makeSession(workspaceRecoveryDirectory: recoveryDirectory)

        session.flushWorkspaceRecovery()

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: recoveryDirectory.appendingPathComponent("WorkspaceRecovery.json").path
        ))
    }

    @MainActor
    func testRecoveryReschedulesPageLayoutChangesAfterDocumentIsAlreadyDirty() {
        let recoveryDirectory = temporaryDirectory.appendingPathComponent("RescheduledRecovery", isDirectory: true)
        var session: DocumentSession? = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        session?.attributedText = NSAttributedString(string: "Dirty body")
        session?.markDirty()
        session?.pageLayout.header.isEnabled = true
        session?.pageLayout.header.text = "First header"
        RunLoop.main.run(until: Date().addingTimeInterval(0.55))

        session?.pageLayout.header.text = "Updated header"
        RunLoop.main.run(until: Date().addingTimeInterval(0.55))
        session = nil

        let restored = makeSession(workspaceRecoveryDirectory: recoveryDirectory)
        XCTAssertEqual(restored.pageLayout.header.text, "Updated header")
        XCTAssertTrue(restored.hasUnsavedChanges)
    }

    @MainActor
    func testCleanClosedTabCanBeReopened() throws {
        let session = makeSession()
        session.newScreenplay()
        let destination = temporaryDirectory.appendingPathComponent("Closed.mgscreenplay")
        XCTAssertTrue(session.saveDocument(to: destination, type: .mongrelScreenplay))
        let screenplayID = try XCTUnwrap(session.activeTabID)
        session.newCodeDocument()

        session.closeTab(screenplayID)
        XCTAssertFalse(session.workspaceTabs.contains(where: { $0.id == screenplayID }))
        XCTAssertTrue(session.canReopenClosedTab)

        session.reopenClosedTab()
        XCTAssertEqual(session.activeTabID, screenplayID)
        XCTAssertEqual(session.authoringMode, .screenplay)
    }

    @MainActor
    func testSourceFileOpeningDetectsLanguageAndPreservesExtensionOnSave() throws {
        let destination = temporaryDirectory.appendingPathComponent("component.tsx")
        try "const value: number = 3\n".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()

        XCTAssertTrue(session.openDocument(at: destination))
        XCTAssertEqual(session.authoringMode, .code)
        XCTAssertEqual(session.codeLanguage, .typescript)
        XCTAssertEqual(session.currentURL?.pathExtension, "tsx")

        session.attributedText = NSAttributedString(string: "const value: number = 4\n")
        session.markDirty()
        session.saveDocument()

        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "const value: number = 4\n")
        XCTAssertEqual(session.currentURL?.pathExtension, "tsx")
    }

    @MainActor
    func testExtensionlessShebangScriptOpensInCodeMode() throws {
        let destination = temporaryDirectory.appendingPathComponent("release")
        try "#!/bin/zsh\necho ready\n".write(to: destination, atomically: true, encoding: .utf8)
        let session = makeSession()

        XCTAssertTrue(session.openDocument(at: destination))
        XCTAssertEqual(session.authoringMode, .code)
        XCTAssertEqual(session.codeLanguage, .shell)
        XCTAssertEqual(session.currentURL?.lastPathComponent, "release")
    }

    @MainActor
    func testCodePreferencesPersistAcrossSessionsAndNormalizeTabWidth() {
        let first = makeSession()
        first.codeLanguage = .sql
        first.codeTheme = .amber
        first.codeFont = .menlo
        first.codeFontSize = 18
        first.codeUseTabs = true
        first.codeTabWidth = 8
        first.codeLineWrap = true

        let reopened = makeSession()

        XCTAssertEqual(reopened.codeLanguage, .sql)
        XCTAssertEqual(reopened.codeTheme, .amber)
        XCTAssertEqual(reopened.codeFont, .menlo)
        XCTAssertEqual(reopened.codeFontSize, 18)
        XCTAssertTrue(reopened.codeUseTabs)
        XCTAssertEqual(reopened.codeTabWidth, 8)
        XCTAssertEqual(reopened.codeIndentationSummary, "Tabs · 8 columns")
        XCTAssertTrue(reopened.codeLineWrap)

        reopened.codeTabWidth = 3
        XCTAssertEqual(reopened.codeTabWidth, 4)
        reopened.codeFontSize = 30
        XCTAssertEqual(reopened.codeFontSize, 24)
    }

    @MainActor
    func testOpenPanelSupportsNativeScreenplaysAndCommonTextFormats() {
        let openTypeIdentifiers = Set(DocumentSession.openableDocumentTypes.map(\.identifier))

        XCTAssertEqual(
            openTypeIdentifiers,
            Set([
                UTType.mongrelDocument.identifier,
                UTType.mongrelScreenplay.identifier,
                UTType.sourceCode.identifier,
                UTType.rtfd.identifier,
                UTType.rtf.identifier,
                UTType.wordDocument.identifier,
                UTType.plainText.identifier
            ])
        )
    }

    @MainActor
    func testNativeDocumentRoundTripPreservesPageLayoutAndBodyAttachment() throws {
        let source = makeSession()
        let imageData = try makePNGData()
        let wrapper = FileWrapper(regularFileWithContents: imageData)
        wrapper.preferredFilename = "mark.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: try XCTUnwrap(NSImage(data: imageData)))
        let richText = NSMutableAttributedString(string: "Opening\n")
        richText.append(NSAttributedString(attachment: attachment))
        source.attributedText = richText
        source.pageLayout.header.isEnabled = true
        source.pageLayout.header.text = "{title}"
        source.pageLayout.header.image = DocumentPageImage(
            data: imageData,
            contentTypeIdentifier: UTType.png.identifier,
            filename: "mark.png"
        )
        source.pageLayout.footer.isEnabled = true
        source.pageLayout.footer.includesPageNumber = true
        source.applyPagePalette(.midnight)
        let destination = temporaryDirectory.appendingPathComponent("Native.mongreldoc")

        XCTAssertTrue(source.saveDocument(to: destination, type: .mongrelDocument))
        XCTAssertEqual(source.codeStorageSummary, "MONGREL")

        let reopened = makeSession()
        XCTAssertTrue(reopened.openDocument(at: destination))
        XCTAssertEqual(reopened.authoringMode, .prose)
        XCTAssertEqual(reopened.pageLayout, source.pageLayout)
        XCTAssertNotNil(
            reopened.attributedText.attribute(
                .attachment,
                at: reopened.attributedText.length - 1,
                effectiveRange: nil
            ) as? NSTextAttachment
        )
        XCTAssertFalse(reopened.hasUnsavedChanges)
    }

    @MainActor
    func testNativeFormatsPreserveTrimmedProjectTitles() throws {
        let documentURL = temporaryDirectory.appendingPathComponent("Container Name.mongreldoc")
        let document = makeSession()
        document.title = "  Working Novel Title  "
        document.attributedText = NSAttributedString(string: "Chapter one")
        XCTAssertTrue(document.saveDocument(to: documentURL, type: .mongrelDocument))
        XCTAssertEqual(document.title, "Working Novel Title")

        let reopenedDocument = makeSession()
        XCTAssertTrue(reopenedDocument.openDocument(at: documentURL))
        XCTAssertEqual(reopenedDocument.title, "Working Novel Title")

        let screenplayURL = temporaryDirectory.appendingPathComponent("Container Name.mgscreenplay")
        let screenplay = makeSession()
        screenplay.newScreenplay()
        screenplay.title = "  Glassline  "
        screenplay.attributedText = NSAttributedString(string: "INT. STUDIO - NIGHT\n")
        XCTAssertTrue(screenplay.saveDocument(to: screenplayURL, type: .mongrelScreenplay))
        XCTAssertEqual(screenplay.title, "Glassline")

        let reopenedScreenplay = makeSession()
        XCTAssertTrue(reopenedScreenplay.openDocument(at: screenplayURL))
        XCTAssertEqual(reopenedScreenplay.title, "Glassline")
        XCTAssertEqual(reopenedScreenplay.authoringMode, .screenplay)
    }

    @MainActor
    func testNativeFirstSaveReplacesPlaceholderTitleWithFilename() throws {
        let screenplayURL = temporaryDirectory.appendingPathComponent("Night Signal.mgscreenplay")
        let screenplay = makeSession()
        screenplay.newScreenplay()
        XCTAssertTrue(screenplay.saveDocument(to: screenplayURL, type: .mongrelScreenplay))
        XCTAssertEqual(screenplay.title, "Night Signal")

        let codeURL = temporaryDirectory.appendingPathComponent("Parser Notes.mongreldoc")
        let code = makeSession()
        code.newCodeDocument()
        XCTAssertTrue(code.saveDocument(to: codeURL, type: .mongrelDocument))
        XCTAssertEqual(code.title, "Parser Notes")
    }

    @MainActor
    func testNativeCodeDocumentRoundTripPreservesLanguage() throws {
        let source = makeSession()
        source.newCodeDocument()
        source.codeLanguage = .yaml
        source.attributedText = NSAttributedString(string: "service:\n  enabled: true\n")
        let destination = temporaryDirectory.appendingPathComponent("Configuration.mongreldoc")

        XCTAssertTrue(source.saveDocument(to: destination, type: .mongrelDocument))

        let reopened = makeSession()
        XCTAssertTrue(reopened.openDocument(at: destination))
        XCTAssertEqual(reopened.authoringMode, .code)
        XCTAssertEqual(reopened.codeLanguage, .yaml)
        XCTAssertEqual(reopened.attributedText.string, "service:\n  enabled: true\n")
    }

    @MainActor
    func testNativeDocumentPreservesScreenplayElementTagsWhenExplicitlySelected() throws {
        let source = makeSession()
        source.authoringMode = .screenplay
        let text = NSMutableAttributedString(string: "INT. LAB - NIGHT\nA monitor waits.\n")
        text.addAttribute(
            .screenplayElement,
            value: ScreenplayElement.sceneHeading.rawValue,
            range: NSRange(location: 0, length: 17)
        )
        source.attributedText = text
        let destination = temporaryDirectory.appendingPathComponent("Script.mongreldoc")

        XCTAssertTrue(source.saveDocument(to: destination, type: .mongrelDocument))

        let reopened = makeSession()
        XCTAssertTrue(reopened.openDocument(at: destination))
        XCTAssertEqual(reopened.authoringMode, .screenplay)
        XCTAssertEqual(screenplayElement(in: reopened.attributedText, at: 0), .sceneHeading)
    }

    @MainActor
    func testNewDocumentClearsPageLayout() throws {
        let session = makeSession()
        session.pageLayout.header.isEnabled = true
        session.pageLayout.header.text = "Private draft"
        let destination = temporaryDirectory.appendingPathComponent("Configured.mongreldoc")
        XCTAssertTrue(session.saveDocument(to: destination, type: .mongrelDocument))

        session.newDocument()

        XCTAssertEqual(session.pageLayout, .empty)
        XCTAssertFalse(session.hasUnsavedChanges)
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
    func testSceneCountRejectsPrefixLookalikes() {
        let session = makeSession()
        session.authoringMode = .screenplay
        session.attributedText = NSAttributedString(
            string: "INT. KITCHEN - DAY\nINT.ERIOR LOG ENTRY\nEXT.RA DETAIL\n"
        )

        session.markDirty()

        XCTAssertEqual(session.screenplaySceneCount, 1)
        XCTAssertEqual(session.screenplayScenes.first?.heading, "INT. KITCHEN - DAY")
    }

    @MainActor
    func testAdjacentSceneNavigationMovesBothDirectionsAndWraps() throws {
        let session = makeSession()
        session.authoringMode = .screenplay
        session.attributedText = NSAttributedString(
            string: "INT. KITCHEN - DAY\nAction.\nEXT. STREET - NIGHT\nMore action.\nINT. CAR - DAWN\n"
        )
        session.markDirty()
        let scenes = session.screenplayScenes
        XCTAssertEqual(scenes.count, 3)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.textStorage?.setAttributedString(session.attributedText)
        session.formattingBridge.textView = textView
        textView.setSelectedRange(NSRange(location: scenes[0].location, length: 0))

        session.selectAdjacentScene(offset: 1)
        XCTAssertEqual(textView.selectedRange().location, scenes[1].location)

        session.selectAdjacentScene(offset: -1)
        XCTAssertEqual(textView.selectedRange().location, scenes[0].location)

        session.selectAdjacentScene(offset: -1)
        XCTAssertEqual(textView.selectedRange().location, scenes[2].location)
        XCTAssertEqual(session.screenplayElement, .sceneHeading)
    }

    @MainActor
    func testSceneFilteringSupportsTermsAndSceneNumbers() {
        let session = makeSession()
        session.authoringMode = .screenplay
        session.attributedText = NSAttributedString(
            string: "INT. KITCHEN - DAY\nAction.\nEXT. CITY STREET - NIGHT\nAction.\nINT. CAR - NIGHT\n"
        )
        session.markDirty()

        XCTAssertEqual(session.screenplayScenes(matching: "night").map(\.number), [2, 3])
        XCTAssertEqual(session.screenplayScenes(matching: "city night").map(\.number), [2])
        XCTAssertEqual(session.screenplayScenes(matching: "#3").map(\.heading), ["INT. CAR - NIGHT"])
        XCTAssertEqual(session.screenplayScenes(matching: "  ").count, 3)
        XCTAssertTrue(session.screenplayScenes(matching: "warehouse").isEmpty)
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
    func testOversizedScreenplayMetadataIsIgnoredWithoutOverflow() throws {
        let destination = temporaryDirectory.appendingPathComponent("Hostile.mgscreenplay")
        let richText = try NSAttributedString(string: "Safe text").data(
            from: NSRange(location: 0, length: 9),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let json = """
        {
          "formatVersion": 1,
          "richTextData": "\(richText.base64EncodedString())",
          "elementRanges": [
            {"location": \(Int.max), "length": \(Int.max), "element": "action"}
          ]
        }
        """
        try XCTUnwrap(json.data(using: .utf8)).write(to: destination)

        let session = makeSession()

        XCTAssertTrue(session.openDocument(at: destination))
        XCTAssertEqual(session.attributedText.string, "Safe text")
        XCTAssertNil(session.attributedText.attribute(.screenplayElement, at: 0, effectiveRange: nil))
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
    func testPDFRendersHeaderFooterFieldsAcrossPages() throws {
        let session = makeSession()
        session.title = "Field Test"
        session.attributedText = NSAttributedString(
            string: Array(repeating: "A line long enough to paginate cleanly.", count: 260).joined(separator: "\n")
        )
        session.pageLayout.header.isEnabled = true
        session.pageLayout.header.text = "{title}"
        session.pageLayout.footer.isEnabled = true
        session.pageLayout.footer.text = "Page {page} / {pages}"

        let pdf = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(session.makePDFData())))

        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: 0)?.string).contains("Field Test"))
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: 0)?.string).contains("Page 1 / \(pdf.pageCount)"))
    }

    @MainActor
    func testPDFCanSuppressPageFurnitureOnFirstPage() throws {
        let session = makeSession()
        session.title = "Second Page Header"
        session.attributedText = NSAttributedString(
            string: Array(repeating: "Another line for reliable pagination.", count: 260).joined(separator: "\n")
        )
        session.pageLayout.header.isEnabled = true
        session.pageLayout.header.text = "{title}"
        session.pageLayout.showsOnFirstPage = false

        let pdf = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(session.makePDFData())))

        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertFalse(try XCTUnwrap(pdf.page(at: 0)?.string).contains("Second Page Header"))
        XCTAssertTrue(try XCTUnwrap(pdf.page(at: 1)?.string).contains("Second Page Header"))
    }

    func testPageFieldsAndAppleFriendlyImageTypes() throws {
        var layout = DocumentPageLayout.empty
        layout.footer.isEnabled = true
        layout.footer.text = "{title} | {page}/{pages}"
        let resolved = layout.resolvedText(
            for: layout.footer,
            title: "Draft",
            pageNumber: 2,
            pageCount: 7,
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(resolved, "Draft | 2/7")
        XCTAssertEqual(
            Set(DocumentImageSupport.contentTypes.map(\.identifier)),
            Set([UTType.png, .jpeg, .heic, .tiff, .gif, .pdf].map(\.identifier))
        )

        layout.header.image = DocumentPageImage(
            data: Data("not an image".utf8),
            contentTypeIdentifier: UTType.png.identifier,
            filename: "broken.png"
        )
        XCTAssertNil(layout.sanitized.header.image)
    }

    func testBuiltInPagePalettesAreReadableAndIncludeLightAndDarkOptions() {
        var lightBackgrounds = 0
        var darkBackgrounds = 0

        for palette in DocumentPagePalette.allCases where palette != .custom {
            let colors = palette.colors(
                customBackground: DocumentRGBColor(hex: 0),
                customText: DocumentRGBColor(hex: 0xffffff)
            )
            XCTAssertGreaterThanOrEqual(colors.contrastRatio, 7, palette.title)
            if colors.background.relativeLuminance > colors.text.relativeLuminance {
                lightBackgrounds += 1
            } else {
                darkBackgrounds += 1
            }
        }

        XCTAssertGreaterThanOrEqual(lightBackgrounds, 3)
        XCTAssertGreaterThanOrEqual(darkBackgrounds, 3)
    }

    func testLegacyPageLayoutDecodingDefaultsToWarmPaper() throws {
        struct LegacyPageLayout: Encodable {
            let header = DocumentPageBand(text: "Legacy")
            let footer = DocumentPageBand(alignment: .center, includesPageNumber: true)
            let showsOnFirstPage = false
        }

        let decoded = try JSONDecoder().decode(
            DocumentPageLayout.self,
            from: JSONEncoder().encode(LegacyPageLayout())
        )

        XCTAssertEqual(decoded.palette, .warmPaper)
        XCTAssertEqual(decoded.header.text, "Legacy")
        XCTAssertFalse(decoded.showsOnFirstPage)
    }

    func testDecodedDocumentColorsAreClampedToValidRGBChannels() throws {
        let decoded = try JSONDecoder().decode(
            DocumentRGBColor.self,
            from: Data(#"{"red":-0.25,"green":0.5,"blue":1.4}"#.utf8)
        )

        XCTAssertEqual(decoded.red, 0)
        XCTAssertEqual(decoded.green, 0.5)
        XCTAssertEqual(decoded.blue, 1)
    }

    func testUnknownFuturePagePaletteFallsBackWithoutRejectingDocument() throws {
        let data = Data(
            #"{"header":{"isEnabled":false,"text":"","alignment":"leading","includesPageNumber":false},"footer":{"isEnabled":false,"text":"","alignment":"center","includesPageNumber":true},"showsOnFirstPage":true,"palette":"futurePalette"}"#.utf8
        )

        let decoded = try JSONDecoder().decode(DocumentPageLayout.self, from: data)

        XCTAssertEqual(decoded.palette, .warmPaper)
    }

    @MainActor
    func testApplyingPagePaletteRecolorsExistingTextAndMarksDocumentDirty() throws {
        let session = makeSession()
        session.attributedText = NSAttributedString(
            string: "Palette target",
            attributes: [.foregroundColor: NSColor.systemRed]
        )

        session.applyPagePalette(.forest)

        XCTAssertEqual(session.pageLayout.palette, .forest)
        XCTAssertTrue(session.hasUnsavedChanges)
        let color = try XCTUnwrap(
            session.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        assertColor(color, matches: session.pageLayout.pageColors.text)
    }

    func testPageImageLoaderAcceptsPNGAndRejectsOversizedFiles() throws {
        let pngURL = temporaryDirectory.appendingPathComponent("mark.png")
        try makePNGData().write(to: pngURL)

        let loaded = try DocumentImageSupport.loadPageImage(from: pngURL)

        XCTAssertEqual(loaded.filename, "mark.png")
        XCTAssertEqual(loaded.contentTypeIdentifier, UTType.png.identifier)
        XCTAssertNotNil(loaded.image)

        let hugeURL = temporaryDirectory.appendingPathComponent("huge.png")
        try Data(count: DocumentImageSupport.maximumFileSize + 1).write(to: hugeURL)
        XCTAssertThrowsError(try DocumentImageSupport.loadPageImage(from: hugeURL))
    }

    @MainActor
    func testPDFRasterUsesSelectedDarkPageBackground() throws {
        let session = makeSession()
        session.attributedText = NSAttributedString(string: "Visible pale text")
        session.applyPagePalette(.midnight)

        let pdf = try XCTUnwrap(PDFDocument(data: try XCTUnwrap(session.makePDFData())))
        let page = try XCTUnwrap(pdf.page(at: 0))
        let thumbnail = page.thumbnail(of: ScreenplayPageLayout.pageSize, for: .mediaBox)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(thumbnail.tiffRepresentation)))
        let sample = try XCTUnwrap(bitmap.colorAt(x: 6, y: 6))

        assertColor(sample, matches: session.pageLayout.pageColors.background, accuracy: 0.04)
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
    func testCloseFromScreenplayReturnsToCleanProseState() {
        let session = makeSession()
        session.newScreenplay()
        session.attributedText = NSAttributedString(string: "")

        session.closeDocument()

        XCTAssertEqual(session.authoringMode, .prose)
        XCTAssertEqual(session.screenplayElement, .action)
        XCTAssertEqual(session.title, "Untitled")
        XCTAssertNil(session.currentURL)
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    @MainActor
    func testStaleLanguageToolIssueCannotModifyDocument() {
        let session = makeSession()
        session.attributedText = NSAttributedString(string: "Their ready.")
        let staleIssue = LanguageToolIssue(
            id: "stale",
            message: "Possible agreement error",
            shortMessage: "Agreement",
            offset: 0,
            length: 5,
            replacements: ["They're"],
            ruleID: "TEST"
        )

        session.applyLanguageToolReplacement("They're", for: staleIssue)

        XCTAssertEqual(session.attributedText.string, "Their ready.")
        XCTAssertFalse(session.hasUnsavedChanges)
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

    @MainActor
    func testZoomFromFitStartsAtVisibleScaleAndRejectsNonfiniteValues() {
        let session = makeSession()
        session.authoringMode = .screenplay
        session.screenplayViewStyle = .fitWidth
        let viewport = EditorScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        viewport.documentView = editor
        viewport.magnification = 1.4
        session.formattingBridge.textView = editor
        session.adjustEditorZoom(by: 0.1)
        XCTAssertEqual(session.editorZoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(session.screenplayViewStyle, .page)
        session.setEditorZoom(.nan)
        session.adjustEditorZoom(by: .infinity)
        XCTAssertEqual(session.editorZoom, 1.5, accuracy: 0.001)
    }

    @MainActor
    func testSceneNavigationAndCatalogHonorDestinationElementsOverTextPatterns() {
        let session = makeSession()
        session.authoringMode = .screenplay
        let pasted = session.formattingBridge.screenplayPaste(NSAttributedString(string: "MARY\nINT. SPOKEN WORDS - DAY\nMore dialogue.\n"), matching: .dialogue)
        session.attributedText = pasted
        session.markDirty()
        XCTAssertEqual(session.screenplaySceneCount, 0)
        XCTAssertTrue(session.screenplayCatalog.headings.isEmpty)
        XCTAssertTrue(session.screenplayCatalog.characters.isEmpty)
        let combined = NSMutableAttributedString(string: "INT. REAL ROOM - DAY\n")
        combined.append(pasted)
        session.attributedText = combined
        session.markDirty()
        XCTAssertEqual(session.screenplaySceneCount, 1)
        XCTAssertEqual(session.screenplayCatalog.locations, ["REAL ROOM"])
        XCTAssertEqual(session.screenplayScenes.first?.location, 0)
        let explicitAction = NSMutableAttributedString(attributedString: combined)
        let heading = (explicitAction.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
        explicitAction.addAttributes([.screenplayElement: ScreenplayElement.sceneHeading.rawValue,
                                      .screenplayManualElement: ScreenplayElement.action.rawValue], range: heading)
        session.attributedText = explicitAction
        session.markDirty()
        XCTAssertEqual(session.screenplaySceneCount, 0)
        XCTAssertTrue(session.screenplayCatalog.locations.isEmpty)
    }

    private func screenplayElement(in text: NSAttributedString, at location: Int) -> ScreenplayElement? {
        guard let raw = text.attribute(.screenplayElement, at: location, effectiveRange: nil) as? String else {
            return nil
        }
        return ScreenplayElement(rawValue: raw)
    }

    private func makePNGData() throws -> Data {
        let image = NSImage(size: NSSize(width: 24, height: 12))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 24, height: 12).fill()
        image.unlockFocus()
        let representation = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }

    private func assertColor(
        _ color: NSColor,
        matches expected: DocumentRGBColor,
        accuracy: Double = 0.002,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let rgb = color.usingColorSpace(.sRGB) else {
            return XCTFail("Color could not be converted to sRGB", file: file, line: line)
        }
        XCTAssertEqual(Double(rgb.redComponent), expected.red, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Double(rgb.greenComponent), expected.green, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Double(rgb.blueComponent), expected.blue, accuracy: accuracy, file: file, line: line)
    }

    private func assertColor(
        _ color: NSColor,
        matches expected: NSColor,
        accuracy: Double = 0.002,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let rgb = color.usingColorSpace(.sRGB),
              let expectedRGB = expected.usingColorSpace(.sRGB) else {
            return XCTFail("Color could not be converted to sRGB", file: file, line: line)
        }
        XCTAssertEqual(rgb.redComponent, expectedRGB.redComponent, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rgb.greenComponent, expectedRGB.greenComponent, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rgb.blueComponent, expectedRGB.blueComponent, accuracy: accuracy, file: file, line: line)
    }

    @MainActor
    private func makeSession(
        workspaceRecoveryDirectory: URL? = nil,
        errorPresenter: ((String, String) -> Void)? = nil
    ) -> DocumentSession {
        let isolatedRecoveryDirectory = workspaceRecoveryDirectory
            ?? temporaryDirectory.appendingPathComponent("Recovery-\(UUID().uuidString)", isDirectory: true)
        return DocumentSession(
            defaults: defaults,
            companionLexicon: MongrelDictionaryCompanionLexicon(headwords: []),
            workspaceRecoveryDirectory: isolatedRecoveryDirectory,
            errorPresenter: errorPresenter
        )
    }
}
