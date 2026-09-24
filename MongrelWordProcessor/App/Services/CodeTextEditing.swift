import Foundation

struct CodeEditResult: Equatable {
    let text: String
    let selection: NSRange
}

enum CodeTextEditing {
    static func cursorPosition(in text: String, selection: NSRange) -> (line: Int, column: Int, selectionLength: Int) {
        let source = text as NSString
        let selection = clamped(selection, to: source.length)
        let location = selection.location
        var line = 1
        var lineStart = 0
        for index in 0..<location {
            let character = source.character(at: index)
            if character == 13 || character == 10 || character == 0x2028 || character == 0x2029 {
                if character != 10 || index == 0 || source.character(at: index - 1) != 13 {
                    line += 1
                }
                lineStart = index + 1
            }
        }
        return (line, location - lineStart + 1, selection.length)
    }

    static func insertNewline(
        in text: String,
        selection: NSRange,
        language: CodeLanguage,
        useTabs: Bool,
        tabWidth: Int
    ) -> CodeEditResult {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let lineRange = source.lineRange(for: NSRange(location: safeSelection.location, length: 0))
        let beforeCaretRange = NSRange(
            location: lineRange.location,
            length: max(0, safeSelection.location - lineRange.location)
        )
        let beforeCaret = source.substring(with: beforeCaretRange)
        let baseIndent = String(beforeCaret.prefix { $0 == " " || $0 == "\t" })
        let trimmed = beforeCaret.trimmingCharacters(in: .whitespaces)
        let unit = indentationUnit(useTabs: useTabs, tabWidth: tabWidth)
        let increasesIndent = shouldIncreaseIndent(after: trimmed, language: language)
        let nextLocation = NSMaxRange(safeSelection)
        // A UTF-16 code unit may be half of an emoji, not a Unicode scalar.
        let nextCharacter = nextLocation < source.length
            ? UnicodeScalar(source.character(at: nextLocation)).map(String.init) ?? ""
            : ""
        let matchingClose = matchingClosingDelimiter(for: trimmed.last)
        let newline = preferredLineEnding(in: source)

        let insertion: String
        let caretOffset: Int
        if increasesIndent, !matchingClose.isEmpty, matchingClose == nextCharacter {
            let inner = baseIndent + unit
            insertion = "\(newline)\(inner)\(newline)\(baseIndent)"
            caretOffset = ("\(newline)\(inner)" as NSString).length
        } else {
            insertion = "\(newline)\(baseIndent)\(increasesIndent ? unit : "")"
            caretOffset = (insertion as NSString).length
        }

        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: safeSelection, with: insertion)
        return CodeEditResult(
            text: mutable as String,
            selection: NSRange(location: safeSelection.location + caretOffset, length: 0)
        )
    }

    static func indent(
        _ text: String,
        selection: NSRange,
        useTabs: Bool,
        tabWidth: Int
    ) -> CodeEditResult {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let unit = indentationUnit(useTabs: useTabs, tabWidth: tabWidth)
        if safeSelection.length == 0 {
            let mutable = NSMutableString(string: text)
            mutable.insert(unit, at: safeSelection.location)
            return CodeEditResult(
                text: mutable as String,
                selection: NSRange(location: safeSelection.location + (unit as NSString).length, length: 0)
            )
        }

        let range = selectedLineRange(in: source, selection: safeSelection)
        let starts = lineStarts(in: source, range: range)
        let mutable = NSMutableString(string: text)
        for start in starts.reversed() {
            mutable.insert(unit, at: start)
        }
        let unitLength = (unit as NSString).length
        return CodeEditResult(
            text: mutable as String,
            selection: NSRange(
                location: safeSelection.location + unitLength,
                length: safeSelection.length + (unitLength * max(0, starts.count - 1))
            )
        )
    }

    static func outdent(_ text: String, selection: NSRange, tabWidth: Int) -> CodeEditResult {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let range = selectedLineRange(in: source, selection: safeSelection)
        let starts = lineStarts(in: source, range: range)
        var removals: [(location: Int, length: Int)] = []
        for start in starts {
            guard start < source.length else { continue }
            if source.character(at: start) == 9 {
                removals.append((start, 1))
                continue
            }
            var count = 0
            while count < tabWidth,
                  start + count < source.length,
                  source.character(at: start + count) == 32 {
                count += 1
            }
            if count > 0 { removals.append((start, count)) }
        }

        let mutable = NSMutableString(string: text)
        for removal in removals.reversed() {
            mutable.deleteCharacters(in: NSRange(location: removal.location, length: removal.length))
        }
        func mappedPosition(_ position: Int) -> Int {
            position - removals.reduce(0) { $0 + min($1.length, max(0, position - $1.location)) }
        }
        let start = mappedPosition(safeSelection.location)
        let end = mappedPosition(NSMaxRange(safeSelection))
        return CodeEditResult(
            text: mutable as String,
            selection: NSRange(
                location: start,
                length: end - start
            )
        )
    }

    static func insertClosingDelimiter(
        _ delimiter: String,
        in text: String,
        selection: NSRange,
        tabWidth: Int
    ) -> CodeEditResult? {
        guard ["}", "]", ")"].contains(delimiter), selection.length == 0 else { return nil }
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let lineRange = source.lineRange(for: NSRange(location: safeSelection.location, length: 0))
        let beforeRange = NSRange(
            location: lineRange.location,
            length: max(0, safeSelection.location - lineRange.location)
        )
        let before = source.substring(with: beforeRange)
        guard before.allSatisfy({ $0 == " " || $0 == "\t" }), !before.isEmpty else { return nil }

        let removalLength: Int
        if before.hasSuffix("\t") {
            removalLength = 1
        } else {
            removalLength = min(max(1, tabWidth), before.reversed().prefix { $0 == " " }.count)
        }
        guard removalLength > 0 else { return nil }

        let replacementRange = NSRange(
            location: safeSelection.location - removalLength,
            length: removalLength
        )
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: replacementRange, with: delimiter)
        return CodeEditResult(
            text: mutable as String,
            selection: NSRange(location: replacementRange.location + 1, length: 0)
        )
    }

    static func toggleLineComment(_ text: String, selection: NSRange, prefix: String) -> CodeEditResult {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let range = selectedLineRange(in: source, selection: safeSelection)
        let lineRanges = contentLineRanges(in: source, range: range)
        let nonblank = lineRanges.filter {
            !source.substring(with: $0).trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard !nonblank.isEmpty else { return CodeEditResult(text: text, selection: safeSelection) }

        let allCommented = nonblank.allSatisfy { lineRange in
            let line = source.substring(with: lineRange)
            let index = line.firstIndex { $0 != " " && $0 != "\t" } ?? line.endIndex
            return line[index...].hasPrefix(prefix)
        }
        let mutable = NSMutableString(string: text)
        var totalDelta = 0
        var firstLineDelta = 0

        for lineRange in lineRanges.reversed() {
            let line = source.substring(with: lineRange)
            guard let firstContent = line.firstIndex(where: { $0 != " " && $0 != "\t" }) else { continue }
            let indentationLength = (String(line[..<firstContent]) as NSString).length
            let editLocation = lineRange.location + indentationLength
            if allCommented {
                let remainder = (line as NSString).substring(from: indentationLength)
                guard remainder.hasPrefix(prefix) else { continue }
                var removalLength = (prefix as NSString).length
                if remainder.dropFirst(prefix.count).hasPrefix(" ") { removalLength += 1 }
                mutable.deleteCharacters(in: NSRange(location: editLocation, length: removalLength))
                totalDelta -= removalLength
                if lineRange.location == range.location { firstLineDelta = -removalLength }
            } else {
                let marker = "\(prefix) "
                mutable.insert(marker, at: editLocation)
                totalDelta += (marker as NSString).length
                if lineRange.location == range.location { firstLineDelta = (marker as NSString).length }
            }
        }

        if safeSelection.length == 0 {
            return CodeEditResult(
                text: mutable as String,
                selection: NSRange(location: max(range.location, safeSelection.location + firstLineDelta), length: 0)
            )
        }
        return CodeEditResult(
            text: mutable as String,
            selection: NSRange(location: range.location, length: max(0, range.length + totalDelta))
        )
    }

    static func duplicateLines(_ text: String, selection: NSRange) -> CodeEditResult {
        let source = text as NSString
        let safeSelection = clamped(selection, to: source.length)
        let range = selectedLineRange(in: source, selection: safeSelection)
        let block = source.substring(with: range)
        let endsWithNewline = block.last?.isNewline == true
        let separator = endsWithNewline || source.length == 0 ? "" : preferredLineEnding(in: source)
        let insertion = separator + block
        let mutable = NSMutableString(string: text)
        mutable.insert(insertion, at: NSMaxRange(range))
        let insertedLength = (insertion as NSString).length
        if safeSelection.length == 0 {
            return CodeEditResult(
                text: mutable as String,
                selection: NSRange(location: safeSelection.location + insertedLength, length: 0)
            )
        }
        return CodeEditResult(
            text: mutable as String,
            selection: NSRange(location: NSMaxRange(range), length: insertedLength)
        )
    }

    private static func indentationUnit(useTabs: Bool, tabWidth: Int) -> String {
        useTabs ? "\t" : String(repeating: " ", count: max(1, tabWidth))
    }

    private static func preferredLineEnding(in source: NSString) -> String {
        let first = source.rangeOfCharacter(from: .newlines)
        guard first.location != NSNotFound else { return "\n" }
        let character = source.character(at: first.location)
        if character == 13, first.location + 1 < source.length, source.character(at: first.location + 1) == 10 {
            return "\r\n"
        }
        return UnicodeScalar(character).map(String.init) ?? "\n"
    }

    private static func shouldIncreaseIndent(after trimmed: String, language: CodeLanguage) -> Bool {
        guard !trimmed.isEmpty else { return false }
        if let last = trimmed.last, "{[(".contains(last) { return true }
        switch language {
        case .python:
            return trimmed.hasSuffix(":")
        case .shell:
            return trimmed.hasSuffix("then") || trimmed.hasSuffix("do") || trimmed.hasSuffix("{")
        case .sql:
            return trimmed.uppercased().hasSuffix("BEGIN")
        default:
            return false
        }
    }

    private static func matchingClosingDelimiter(for character: Character?) -> String {
        switch character {
        case "{": return "}"
        case "[": return "]"
        case "(": return ")"
        default: return ""
        }
    }

    private static func clamped(_ range: NSRange, to length: Int) -> NSRange {
        let location = min(max(0, range.location == NSNotFound ? length : range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }

    private static func selectedLineRange(in source: NSString, selection: NSRange) -> NSRange {
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }
        var effective = selection
        if effective.length > 0 { effective.length -= 1 }
        return source.lineRange(for: effective)
    }

    private static func lineStarts(in source: NSString, range: NSRange) -> [Int] {
        contentLineRanges(in: source, range: range).map(\.location)
    }

    private static func contentLineRanges(in source: NSString, range: NSRange) -> [NSRange] {
        if source.length == 0 { return [NSRange(location: 0, length: 0)] }
        var result: [NSRange] = []
        var cursor = range.location
        let limit = min(source.length, NSMaxRange(range))
        while cursor < limit {
            var start = 0
            var end = 0
            var contentsEnd = 0
            source.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            result.append(NSRange(location: start, length: max(0, contentsEnd - start)))
            guard end > cursor else { break }
            cursor = end
        }
        return result.isEmpty ? [NSRange(location: range.location, length: 0)] : result
    }
}
