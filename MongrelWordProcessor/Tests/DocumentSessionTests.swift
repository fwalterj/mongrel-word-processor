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
        let reopenedColor = try XCTUnwrap(
            reopened.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        assertColor(reopenedColor, matches: .labelColor)
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
    func testOpenPanelSupportsNativeScreenplaysAndCommonTextFormats() {
        let openTypeIdentifiers = Set(DocumentSession.openableDocumentTypes.map(\.identifier))

        XCTAssertEqual(
            openTypeIdentifiers,
            Set([
                UTType.mongrelDocument.identifier,
                UTType.mongrelScreenplay.identifier,
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
    private func makeSession() -> DocumentSession {
        DocumentSession(
            defaults: defaults,
            companionLexicon: MongrelDictionaryCompanionLexicon(headwords: [])
        )
    }
}
