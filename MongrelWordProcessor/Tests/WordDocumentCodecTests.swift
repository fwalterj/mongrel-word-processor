import AppKit
import XCTest
@testable import MongrelWordProcessor

final class WordDocumentCodecTests: XCTestCase {
    private func fixture() -> URL {
        Bundle(for: Self.self).url(forResource: "WordFormatting", withExtension: "docx")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Tests/Fixtures/WordFormatting.docx")
    }
    private func style(_ text: NSAttributedString, _ marker: String) throws -> NSParagraphStyle {
        let offset = (text.string as NSString).range(of: marker).location
        XCTAssertNotEqual(offset, NSNotFound)
        return try XCTUnwrap(text.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle)
    }

    @MainActor
    func testImportsDirectInheritedHangingAndExplicitZeroParagraphProperties() throws {
        let text = try WordDocumentCodec.read(from: fixture())
        let direct = try style(text, "Direct first")
        XCTAssertEqual(direct.firstLineHeadIndent, 72)
        XCTAssertEqual(direct.headIndent, 36)
        XCTAssertEqual(direct.tailIndent, -18)
        let inherited = try style(text, "Inherited body")
        XCTAssertEqual(inherited.headIndent, 72)
        XCTAssertEqual(inherited.firstLineHeadIndent, 108)
        XCTAssertEqual(inherited.lineHeightMultiple, 1.5)
        XCTAssertEqual(inherited.paragraphSpacingBefore, 6)
        XCTAssertEqual(inherited.paragraphSpacing, 12)
        XCTAssertEqual(inherited.alignment, .justified)
        XCTAssertEqual(try style(text, "Hanging paragraph").firstLineHeadIndent, 18)
        let zero = try style(text, "Explicit zero")
        XCTAssertEqual(zero.headIndent, 0)
        XCTAssertEqual(zero.firstLineHeadIndent, 0)
        XCTAssertEqual(zero.paragraphSpacingBefore, 0)
        XCTAssertEqual(zero.paragraphSpacing, 0)
        XCTAssertEqual(zero.alignment, .left)
    }

    @MainActor
    func testImportedStyleFontsRespectDirectRunOverridesAndKeepNativeContent() throws {
        let text = try WordDocumentCodec.read(from: fixture())
        let native = try NSAttributedString(url: fixture(), options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        XCTAssertEqual(text.string, native.string)
        func attributes(_ marker: String) -> [NSAttributedString.Key: Any] { text.attributes(at: (text.string as NSString).range(of: marker).location, effectiveRange: nil) }
        let inherited = try XCTUnwrap(attributes("Inherited body")[.font] as? NSFont)
        XCTAssertEqual(inherited.pointSize, 16)
        XCTAssertTrue(inherited.fontName.contains("Georgia"))
        XCTAssertTrue(inherited.fontDescriptor.symbolicTraits.contains(.bold))
        let override = try XCTUnwrap(attributes("Explicit zero")[.font] as? NSFont)
        XCTAssertFalse(override.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(override.fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertEqual(try XCTUnwrap(attributes("Direct first")[.font] as? NSFont).pointSize, 14)
        XCTAssertNotNil(attributes("After table link")[.link])
        let cell = try style(text, "Inside a table")
        XCTAssertFalse(cell.textBlocks.isEmpty)
        XCTAssertEqual(cell.firstLineHeadIndent, 12)
        XCTAssertEqual(try style(text, "After table").firstLineHeadIndent, 30)
        let list = try style(text, "Numbered item")
        XCTAssertEqual(list.headIndent, 36)
        XCTAssertEqual(list.firstLineHeadIndent, 18)
        let soft = try style(text, "Soft break")
        XCTAssertEqual(soft.minimumLineHeight, 20)
        XCTAssertEqual(soft.maximumLineHeight, 20)
        XCTAssertEqual(soft.firstLineHeadIndent, 18)
        XCTAssertTrue(soft.tabStops.contains { $0.location == 144 && $0.alignment == .right })
    }

    @MainActor
    func testWordAndNativeArchiveRoundTripsKeepParagraphGeometry() throws {
        let original = try WordDocumentCodec.read(from: fixture())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("WordRoundTrip-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: url) }
        try WordDocumentCodec.data(from: original).write(to: url)
        let word = try WordDocumentCodec.read(from: url)
        let archive = try MongrelDocumentArchive(attributedText: original, authoringMode: .prose, pageLayout: .empty)
        let native = try archive.makeAttributedString()
        for restored in [word, native] {
            for marker in ["Direct first", "Inherited body", "Hanging paragraph", "Explicit zero", "Soft break", "Numbered item", "Inside a table", "After table"] {
                let expected = try style(original, marker)
                let actual = try style(restored, marker)
                XCTAssertEqual(actual.headIndent, expected.headIndent, marker)
                XCTAssertEqual(actual.firstLineHeadIndent, expected.firstLineHeadIndent, marker)
                XCTAssertEqual(actual.lineHeightMultiple, expected.lineHeightMultiple, accuracy: 0.01, marker)
            }
        }
    }

    @MainActor
    func testBrokenPackagesAndCyclicStylesDoNotCrashOrShiftUnmatchedParagraphs() throws {
        XCTAssertThrowsError(try WordPackageXML.read(Data([0, 1, 2])))
        var corrupt = try Data(contentsOf: fixture())
        // Damage the compressed document part without changing its directory CRC.
        let signature = Data("word/document.xml".utf8)
        let offset = try XCTUnwrap(corrupt.range(of: signature)).upperBound
        corrupt[offset + 10] ^= 0x7f
        XCTAssertThrowsError(try WordPackageXML.read(corrupt))
        let ns = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let styles = Data("<w:styles xmlns:w=\"\(ns)\"><w:style w:type=\"paragraph\" w:styleId=\"A\"><w:basedOn w:val=\"B\"/><w:pPr><w:ind w:firstLine=\"720\"/></w:pPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"B\"><w:basedOn w:val=\"A\"/></w:style></w:styles>".utf8)
        let xml = Data("<w:document xmlns:w=\"\(ns)\"><w:body><w:p><w:pPr><w:pStyle w:val=\"A\"/></w:pPr><w:r><w:t>Not the native text</w:t></w:r></w:p><w:p><w:pPr><w:pStyle w:val=\"A\"/></w:pPr><w:r><w:t>Matching</w:t></w:r></w:p></w:body></w:document>".utf8)
        let result = try WordDocumentCodec.restoringParagraphs(in: NSAttributedString(string: "Unmatched\nMatching\n"), document: xml, styles: styles)
        XCTAssertNil(result.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
        XCTAssertEqual(try style(result, "Matching").firstLineHeadIndent, 36)
    }
}
