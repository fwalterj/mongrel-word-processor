import AppKit
import PDFKit
import XCTest
@testable import MongrelWordProcessor

@MainActor
final class ScreenplayPolishTests: XCTestCase {
    func testRecoveryWriterKeepsOnlyTheNewestSnapshotWhenDiskIsBusy() {
        let writer = CoalescingWorkspaceRecoveryWriter()
        let recorder = RecoveryWriteRecorder()
        let started = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        writer.enqueue {
            started.signal()
            resume.wait()
            recorder.append(0)
        }
        let began = started.wait(timeout: .now() + 2) == .success
        XCTAssertTrue(began)
        guard began else { resume.signal(); return }
        for value in 1...2_000 { writer.enqueue { recorder.append(value) } }
        resume.signal()
        writer.flush()
        XCTAssertEqual(recorder.values, [0, 2_000])
        writer.enqueue { recorder.append(2_001) }
        writer.flush()
        XCTAssertEqual(recorder.values, [0, 2_000, 2_001])
    }

    func testActiveSceneFollowsCursorBoundariesAndDocumentChanges() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = session(directory: directory)
        session.newScreenplay()
        session.attributedText = NSAttributedString(string: "Prologue\nINT. ROOM - DAY\nA door opens.\nEXT. ROAD - NIGHT\nRain.")
        session.markDirty()
        let scenes = session.screenplayScenes
        XCTAssertEqual(scenes.count, 2)
        guard scenes.count == 2 else { return }
        session.updateScreenplayCursor(location: 0)
        XCTAssertNil(session.activeScreenplaySceneID)
        session.updateScreenplayCursor(location: scenes[0].location)
        XCTAssertEqual(session.activeScreenplaySceneID, scenes[0].id)
        session.updateScreenplayCursor(location: scenes[1].location - 1)
        XCTAssertEqual(session.activeScreenplaySceneID, scenes[0].id)
        session.updateScreenplayCursor(location: Int.max)
        XCTAssertEqual(session.activeScreenplaySceneID, scenes[1].id)
        session.newDocument()
        XCTAssertNil(session.activeScreenplaySceneID)
    }

    private func session(directory: URL) -> DocumentSession {
        DocumentSession(
            defaults: UserDefaults(suiteName: "PolishTests-\(UUID().uuidString)")!,
            companionLexicon: MongrelDictionaryCompanionLexicon(headwords: []),
            workspaceRecoveryDirectory: directory,
            errorPresenter: { _, message in XCTFail(message) }
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testCatalogRetainsEveryCharacterAndCanonicalizesExtensions() {
        let text = NSMutableAttributedString(string: "INT. HOUSE - KITCHEN - NIGHT\nINT. HOUSE - KITCHEN - DAY\nEXT. ROAD – DUSK\n")
        for index in 0..<40 {
            text.append(NSAttributedString(string: "PERSON \(index) (CONT’D)\n", attributes: [.screenplayElement: ScreenplayElement.character.rawValue]))
            text.append(NSAttributedString(string: "PERSON \(index) (V.O.)\n", attributes: [.screenplayElement: ScreenplayElement.character.rawValue]))
        }
        let catalog = ScreenplayCatalog.analyze(text)
        XCTAssertEqual(catalog.characters.count, 40)
        XCTAssertEqual(catalog.locations, ["HOUSE - KITCHEN", "ROAD"])
        XCTAssertFalse(catalog.characters.contains { $0.contains("(") })
        let insights = DocumentInsightsAnalyzer.analyze(text, scenes: [], mode: .screenplay)
        XCTAssertEqual(insights.characters.count, 40)
        XCTAssertTrue(insights.characters.allSatisfy { $0.cueCount == 2 })
    }

    func testProfileAndProductionNumbersSurviveSaveReopenAndRecovery() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = session(directory: directory.appendingPathComponent("recovery"))
        session.newScreenplay()
        session.attributedText = NSAttributedString(string: "INT. HOUSE - DAY\nQuiet.\nEXT. ROAD - NIGHT\nEmpty.\n")
        session.markDirty()
        let words = session.attributedText.string
        session.screenplaySettings.voice = .literary
        session.screenplaySettings.format = .short
        session.screenplaySettings.showsSceneCount = false
        session.screenplaySettings.draft = .production
        XCTAssertEqual(session.attributedText.string, words)
        XCTAssertEqual(session.screenplayScenes.map(\.displayNumber), ["1", "2"])

        let originalSecondID = session.screenplaySettings.sceneRecords[1].id
        let inserted = NSMutableAttributedString(attributedString: session.attributedText)
        inserted.insert(NSAttributedString(string: "INT. GARAGE - DAY\nAn engine starts.\n"), at: session.screenplayScenes[1].location)
        session.attributedText = inserted
        session.markDirty()
        XCTAssertEqual(session.screenplayScenes.map(\.displayNumber), ["1", "1A", "2"])
        XCTAssertEqual(session.screenplayScenes(matching: "#1A").count, 1)

        let destination = directory.appendingPathComponent("Production.mgscreenplay")
        XCTAssertTrue(session.saveDocument(to: destination, type: .mongrelScreenplay))
        session.newDocument()
        XCTAssertTrue(session.openDocument(at: destination))
        XCTAssertEqual(session.screenplaySettings.voice, .literary)
        XCTAssertEqual(session.screenplaySettings.format, .short)
        XCTAssertFalse(session.screenplaySettings.showsSceneCount)
        XCTAssertEqual(session.screenplayScenes.map(\.displayNumber), ["1", "1A", "2"])
        XCTAssertEqual(session.screenplaySettings.sceneRecords.first { $0.number == "2" }?.id, originalSecondID)
        XCTAssertEqual(session.screenplayCatalog.locations, ["GARAGE", "HOUSE", "ROAD"])

        let removed = NSMutableAttributedString(attributedString: session.attributedText)
        let second = session.screenplayScenes.last!
        removed.deleteCharacters(in: NSRange(location: second.location, length: removed.length - second.location))
        session.attributedText = removed
        session.markDirty()
        XCTAssertTrue(session.screenplaySettings.sceneRecords.first { $0.number == "2" }!.isOmitted)
        session.flushWorkspaceRecovery()
        let restored = self.session(directory: directory.appendingPathComponent("recovery"))
        XCTAssertEqual(restored.screenplaySettings, session.screenplaySettings)
        XCTAssertEqual(restored.attributedText.string, session.attributedText.string)
        XCTAssertEqual(restored.screenplayScenes.map(\.displayNumber), ["1", "1A"])
    }

    func testSceneIdentitySurvivesEditingFirstCharacterAndVoiceChanges() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = session(directory: directory)
        session.newScreenplay()
        session.attributedText = NSAttributedString(string: "INT. KITCHEN - DAY\n")
        session.markDirty()
        session.screenplaySettings.draft = .production
        let identity = session.screenplaySettings.sceneRecords.first!.id
        let edited = NSMutableAttributedString(attributedString: session.attributedText)
        edited.deleteCharacters(in: NSRange(location: 0, length: 1))
        session.attributedText = edited
        // Semantic headings keep their identity even while their text is being edited.
        edited.addAttribute(.screenplayElement, value: ScreenplayElement.sceneHeading.rawValue, range: NSRange(location: 0, length: edited.length))
        session.markDirty()
        session.screenplaySettings.voice = .suspense
        XCTAssertEqual(session.screenplaySettings.sceneRecords.first!.id, identity)
        XCTAssertEqual(session.screenplayScenes.map(\.displayNumber), ["1"])
    }

    func testMultilinePastePreservesTextAndFormatsEveryParagraph() {
        let text = "INT. KITCHEN - NIGHT\nMara waits.\nMARA\nAre you there?\n\nEXT. ROAD - DAY\nNobody answers.\n"
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        editor.string = text
        editor.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        let bridge = FormattingBridge()
        bridge.textView = editor
        bridge.formatInsertedScreenplay(in: editor, range: NSRange(location: 0, length: text.utf16.count))
        XCTAssertEqual(editor.string, text)
        let source = editor.string as NSString
        XCTAssertEqual(editor.textStorage?.attribute(.screenplayElement, at: source.range(of: "MARA").location, effectiveRange: nil) as? String, ScreenplayElement.character.rawValue)
        XCTAssertEqual(editor.textStorage?.attribute(.screenplayElement, at: source.range(of: "Are you").location, effectiveRange: nil) as? String, ScreenplayElement.dialogue.rawValue)
        XCTAssertEqual(editor.textStorage?.attribute(.screenplayElement, at: source.range(of: "EXT.").location, effectiveRange: nil) as? String, ScreenplayElement.sceneHeading.rawValue)
    }

    func testManualActionAndEmphasisSurviveAutoFormatAndArchive() throws {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        editor.string = "NOTHING\nSomething is wrong with this room."
        let bridge = FormattingBridge()
        bridge.textView = editor
        editor.setSelectedRange(NSRange(location: 0, length: 7))
        bridge.applyScreenplayElement(.action, to: editor, notifyTextChange: false)
        XCTAssertEqual(bridge.autoFormatScreenplay(in: editor), .action)
        let emphasis = (editor.string as NSString).range(of: "wrong")
        editor.textStorage?.addAttribute(.font, value: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 12), toHaveTrait: .italicFontMask), range: emphasis)
        bridge.autoFormatEntireScreenplay()
        XCTAssertEqual(editor.string, "NOTHING\nSomething is wrong with this room.")
        let font = editor.textStorage?.attribute(.font, at: emphasis.location, effectiveRange: nil) as! NSFont
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        let archive = try MongrelDocumentArchive(attributedText: editor.attributedString(), authoringMode: .screenplay, pageLayout: .empty)
        let restored = try archive.makeAttributedString()
        XCTAssertEqual(restored.attribute(.screenplayManualElement, at: 0, effectiveRange: nil) as? String, ScreenplayElement.action.rawValue)
    }

    func testLargeNativeDocumentAndRapidMixedTabsRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = session(directory: directory.appendingPathComponent("recovery"))
        let largeText = String(repeating: "A quiet room. Café, 東京, and a face: 🙂.\n", count: 12_000)
        session.attributedText = NSAttributedString(string: largeText)
        session.markDirty(deferMetrics: true)
        let prose = directory.appendingPathComponent("Large.mongreldoc")
        XCTAssertTrue(session.saveDocument(to: prose, type: .mongrelDocument))
        let proseID = session.activeTabID!
        for index in 0..<12 {
            session.newScreenplay()
            session.attributedText = NSAttributedString(string: "INT. ROOM \(index) - DAY\nA door opens.\n")
            session.markDirty(deferMetrics: true)
            XCTAssertTrue(session.saveDocument(to: directory.appendingPathComponent("Scene-\(index).mgscreenplay"), type: .mongrelScreenplay))
        }
        for tab in session.workspaceTabs.reversed() { session.switchToTab(tab.id) }
        session.switchToTab(proseID)
        XCTAssertEqual(session.attributedText.string, largeText)
        session.flushWorkspaceRecovery()
        let restored = self.session(directory: directory.appendingPathComponent("recovery"))
        XCTAssertEqual(restored.workspaceTabs.count, 13)
        XCTAssertEqual(restored.attributedText.string, largeText)
    }

    func testProductionPDFDrawsBothMarginNumbersWithoutChangingText() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = session(directory: directory)
        session.newScreenplay()
        let source = "INT. HOUSE - NIGHT\nA door opens.\nEXT. ROAD - DAY\nEmpty."
        session.attributedText = NSAttributedString(string: source, attributes: [.font: NSFont(name: "Courier", size: 12)!])
        session.markDirty()
        session.screenplaySettings.draft = .production
        let data = session.makePDFData()!
        let numbered = PDFDocument(data: data)!.string!.split(whereSeparator: \.isWhitespace)
        XCTAssertEqual(numbered.filter { $0 == "1" }.count, 2)
        XCTAssertEqual(numbered.filter { $0 == "2" }.count, 2)
        XCTAssertEqual(session.attributedText.string, source)
        if let output = ProcessInfo.processInfo.environment["MONGREL_QA_PDF"] { try data.write(to: URL(fileURLWithPath: output)) }
        session.screenplaySettings.showsSceneNumbers = false
        let clean = PDFDocument(data: session.makePDFData()!)!.string!.split(whereSeparator: \.isWhitespace)
        XCTAssertEqual(clean.filter { $0 == "1" || $0 == "2" }.count, 0)
    }

    func testNativeFormatsPreserveControlCharactersAndSemanticOffsets() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "Before 🙂\r\n\u{FFFC}\u{0}\u{000C}\u{2028}\u{2029}After\tend"
        let attributed = NSMutableAttributedString(string: text)
        let range = (text as NSString).range(of: "After")
        attributed.addAttribute(.screenplayElement, value: ScreenplayElement.character.rawValue, range: range)
        let archive = try MongrelDocumentArchive(attributedText: attributed, authoringMode: .screenplay, pageLayout: .empty)
        let restored = try archive.makeAttributedString()
        XCTAssertEqual(restored.string, text)
        XCTAssertEqual(restored.attribute(.screenplayElement, at: range.location, effectiveRange: nil) as? String, ScreenplayElement.character.rawValue)
        let session = session(directory: directory.appendingPathComponent("recovery"))
        session.newScreenplay()
        session.attributedText = attributed
        session.markDirty()
        let url = directory.appendingPathComponent("Control.mgscreenplay")
        XCTAssertTrue(session.saveDocument(to: url, type: .mongrelScreenplay))
        let reopened = self.session(directory: directory.appendingPathComponent("other"))
        XCTAssertTrue(reopened.openDocument(at: url))
        XCTAssertEqual(reopened.attributedText.string, text)
    }

    func testNativeScreenplayPreservesImageAttachments() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let data = bitmap.representation(using: .png, properties: [:])!
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "reference.png"
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: NSImage(data: data))
        let text = NSMutableAttributedString(string: "A reference image.\n")
        text.append(NSAttributedString(attachment: attachment))
        let session = session(directory: directory.appendingPathComponent("recovery"))
        session.newScreenplay()
        session.attributedText = text
        session.markDirty()
        let url = directory.appendingPathComponent("Image.mgscreenplay")
        XCTAssertTrue(session.saveDocument(to: url, type: .mongrelScreenplay))
        let reopened = self.session(directory: directory.appendingPathComponent("other"))
        XCTAssertTrue(reopened.openDocument(at: url))
        XCTAssertEqual(reopened.attributedText.string, text.string)
        XCTAssertTrue(reopened.attributedText.attribute(.attachment, at: text.length - 1, effectiveRange: nil) is NSTextAttachment)
    }

    func testMoreThanFiftyTabsRecoverWithoutDiscardingWorkspace() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = session(directory: directory)
        for index in 0..<55 {
            session.newDocument()
            session.attributedText = NSAttributedString(string: "Draft \(index)")
            session.markDirty(deferMetrics: true)
        }
        session.flushWorkspaceRecovery()
        let restored = self.session(directory: directory)
        XCTAssertEqual(restored.workspaceTabs.count, 55)
        XCTAssertEqual(restored.attributedText.string, "Draft 54")
    }

    func testSampleScriptsCanBePastedAndSavedWithoutChangingTheirText() throws {
        let samples = ProcessInfo.processInfo.environment["MONGREL_SAMPLE_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("screenplay_examples")
        guard FileManager.default.fileExists(atPath: samples.path) else { return }
        let files = try FileManager.default.contentsOfDirectory(at: samples, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "pdf" }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = session(directory: directory.appendingPathComponent("recovery"))
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try autoreleasepool {
                guard let pdf = PDFDocument(url: file), let text = pdf.string, !text.isEmpty else { return }
                let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
                editor.string = text
                let bridge = FormattingBridge()
                bridge.textView = editor
                let start = Date()
                bridge.formatInsertedScreenplay(in: editor, range: NSRange(location: 0, length: text.utf16.count))
                XCTAssertEqual(editor.string, text)
                session.newScreenplay()
                session.attributedText = editor.attributedString()
                session.markDirty()
                let saved = directory.appendingPathComponent(file.deletingPathExtension().lastPathComponent + ".mgscreenplay")
                XCTAssertTrue(session.saveDocument(to: saved, type: .mongrelScreenplay))
                let reopened = self.session(directory: directory.appendingPathComponent(UUID().uuidString))
                XCTAssertTrue(reopened.openDocument(at: saved))
                XCTAssertEqual(reopened.attributedText.string, text)
                print("Sample \(file.lastPathComponent): \(pdf.pageCount) pages, \(text.utf16.count) UTF-16 units, paste + save \(String(format: "%.3f", Date().timeIntervalSince(start)))s")
            }
        }
    }

    func testNumberAllocationDoesNotReuseOmittedNumbersAndExtendsPastZ() {
        var reserved: Set<String> = ["1", "2"]
        for index in 0..<30 {
            let number = ScreenplayProductionNumbering.nextNumber(after: "1", reserved: reserved, initial: false)
            XCTAssertTrue(reserved.insert(number).inserted)
            if index == 26 { XCTAssertEqual(number, "1AA") }
        }
        XCTAssertEqual(ScreenplayProductionNumbering.nextNumber(after: nil, reserved: reserved, initial: false), "0A")
    }
}

private final class RecoveryWriteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Int] = []
    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func append(_ value: Int) {
        lock.lock()
        stored.append(value)
        lock.unlock()
    }
}
