import Foundation

/// UTF-16 line positions shared by the source editor's status and cursor paths.
/// Build once per text revision; moving a caret must not rescan the document.
struct TextLineIndex {
    private let starts: [Int]
    let length: Int
    let lineEnding: String
    var count: Int { starts.count }

    init(_ text: String) {
        let source = text as NSString
        length = source.length
        var offsets = [0]
        var offset = 0
        var hasCRLF = false
        var hasCR = false
        while offset < source.length {
            var end = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: offset, length: 0))
            guard end > offset else { break }
            if contentsEnd < end {
                offsets.append(end)
                if source.character(at: contentsEnd) == 13 {
                    if end - contentsEnd == 2 { hasCRLF = true } else { hasCR = true }
                }
            }
            offset = end
        }
        starts = offsets
        lineEnding = hasCRLF ? "CRLF" : (hasCR ? "CR" : "LF")
    }

    func position(at selection: NSRange) -> (line: Int, column: Int, selectionLength: Int) {
        let location = min(max(0, selection.location), length)
        var lower = 0
        var upper = starts.count
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if starts[middle] <= location { lower = middle } else { upper = middle }
        }
        return (lower + 1, location - starts[lower] + 1, min(max(0, selection.length), length - location))
    }
}
