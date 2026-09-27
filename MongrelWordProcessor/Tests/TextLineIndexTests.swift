import Foundation
import XCTest
@testable import MongrelWordProcessor

final class TextLineIndexTests: XCTestCase {
    func testMixedNewlinesTrailingEmptyLineAndUTF16Columns() {
        let source = "one\r\ntwo\rthree\nfour\u{2028}five\u{2029}🙂end\n"
        let index = TextLineIndex(source)
        XCTAssertEqual(index.count, 7)
        XCTAssertEqual(index.lineEnding, "CRLF")
        let last = (source as NSString).range(of: "🙂end").location
        XCTAssertEqual(index.position(at: NSRange(location: last + 2, length: 3)).line, 6)
        XCTAssertEqual(index.position(at: NSRange(location: last + 2, length: 3)).column, 3)
        XCTAssertEqual(index.position(at: NSRange(location: source.utf16.count, length: 99)).selectionLength, 0)
        XCTAssertEqual(index.position(at: NSRange(location: NSNotFound, length: 0)).line, 7)
        XCTAssertEqual(TextLineIndex("").count, 1)
    }

    func testRepeatedCursorQueriesNearEndOfLargeSource() {
        let index = TextLineIndex(String(repeating: "let answer = 42\n", count: 100_000))
        let start = Date()
        for offset in 0..<10_000 {
            let position = index.position(at: NSRange(location: index.length - 1 - offset % 10, length: 0))
            XCTAssertEqual(position.line, 100_000)
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
