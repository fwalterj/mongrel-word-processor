import AppKit
import zlib

/// Supplement AppKit's Word converter with inherited paragraph/run formatting
/// and web links. Keep native attachments/tables and match paragraph text before
/// applying style properties. Export also preserves indentation and line height.
enum WordDocumentCodec {
    static func read(from url: URL) throws -> NSAttributedString {
        let native = try NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
        let parts = try WordPackageXML.read(from: url)
        guard let document = parts["word/document.xml"] else { return native }
        return try restoringParagraphs(in: native, document: document, styles: parts["word/styles.xml"], numbering: parts["word/numbering.xml"], relationships: parts["word/_rels/document.xml.rels"])
    }

    static func data(from text: NSAttributedString) throws -> Data {
        let native = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        guard let xml = try WordPackageXML.read(native)["word/document.xml"] else { return native }
        let root = try parse(xml)
        let source = text.string as NSString
        let ranges = paragraphRanges(in: source)
        var next = 0
        for paragraph in root.child("body")?.paragraphs() ?? [] {
            let expected = normalized(paragraph.visibleText())
            guard let index = (next..<min(next + 12, ranges.count)).first(where: { normalized(source.substring(with: ranges[$0])) == expected }) else { continue }
            next = index + 1
            guard let style = text.attribute(.paragraphStyle, at: ranges[index].location, effectiveRange: nil) as? NSParagraphStyle else { continue }
            let prefix = paragraph.prefix.map { $0 + ":" } ?? ""
            func element(_ name: String) -> XMLElement { XMLElement(name: prefix + name, uri: paragraph.uri) }
            let properties = paragraph.child("pPr") ?? element("pPr")
            if properties.parent == nil { paragraph.insertChild(properties, at: 0) }
            func setting(_ name: String, _ attributes: [String: String]) {
                for old in properties.childrenNamed(name) { old.detach() }
                let node = element(name)
                for (key, value) in attributes { node.addAttribute(XMLNode.attribute(withName: prefix + key, uri: paragraph.uri ?? "http://schemas.openxmlformats.org/wordprocessingml/2006/main", stringValue: value) as! XMLNode) }
                properties.addChild(node)
            }
            func twips(_ value: CGFloat) -> String { String(Int((min(max(value.isFinite ? value : 0, -500_000), 500_000) * 20).rounded())) }
            let delta = style.firstLineHeadIndent - style.headIndent
            var indentation = ["left": twips(style.headIndent), delta < 0 ? "hanging" : "firstLine": twips(abs(delta))]
            if style.tailIndent <= 0 { indentation["right"] = twips(-style.tailIndent) }
            setting("ind", indentation)
            var spacing = ["before": twips(style.paragraphSpacingBefore), "after": twips(style.paragraphSpacing)]
            if style.lineHeightMultiple > 0 {
                spacing["line"] = String(Int((min(style.lineHeightMultiple, 100) * 240).rounded()))
                spacing["lineRule"] = "auto"
            } else if style.minimumLineHeight > 0 {
                spacing["line"] = twips(style.minimumLineHeight)
                spacing["lineRule"] = style.maximumLineHeight == style.minimumLineHeight ? "exact" : "atLeast"
            }
            setting("spacing", spacing)
        }
        root.detach()
        let document = XMLDocument(rootElement: root)
        document.characterEncoding = "UTF-8"
        return try WordPackageXML.replacingDocument(in: native, with: document.xmlData)
    }

    static func restoringParagraphs(in native: NSAttributedString, document: Data, styles: Data?, numbering: Data? = nil, relationships: Data? = nil) throws -> NSAttributedString {
        let body = try parse(document).child("body")
        let styleRoot = try styles.map(parse)
        let numberRoot = try numbering.map(parse)
        var links: [String: URL] = [:]
        if let relationships {
            for node in try parse(relationships).children?.compactMap({ $0 as? XMLElement }) ?? [] {
                guard node.localName == "Relationship", node.value("Type")?.hasSuffix("/hyperlink") == true,
                      let id = node.value("Id"), let target = node.value("Target"), let url = URL(string: target),
                      ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { continue }
                links[id] = url
            }
        }
        let defaults = Properties(styleRoot?.child("docDefaults")?.child("pPrDefault")?.child("pPr"))
        var definitions: [String: XMLElement] = [:]
        var defaultStyle: String?
        for style in styleRoot?.childrenNamed("style") ?? [] {
            guard let id = style.value("styleId") else { continue }
            definitions[id] = style
            if style.value("type") == "paragraph", ["1", "true", "on"].contains(style.value("default") ?? "") { defaultStyle = id }
        }
        var resolved: [String: Properties] = [:]
        func resolve(_ id: String?, visiting: Set<String> = []) -> Properties {
            guard let id, !visiting.contains(id), visiting.count < 64, let node = definitions[id] else { return defaults }
            if let cached = resolved[id] { return cached }
            var result = resolve(node.child("basedOn")?.value("val"), visiting: visiting.union([id]))
            result.merge(Properties(node.child("pPr")))
            resolved[id] = result
            return result
        }
        let runDefaults = RunProperties(styleRoot?.child("docDefaults")?.child("rPrDefault")?.child("rPr"))
        var resolvedRuns: [String: RunProperties] = [:]
        func resolveRuns(_ id: String?, visiting: Set<String> = []) -> RunProperties {
            guard let id, !visiting.contains(id), visiting.count < 64, let node = definitions[id] else { return runDefaults }
            if let cached = resolvedRuns[id] { return cached }
            var result = resolveRuns(node.child("basedOn")?.value("val"), visiting: visiting.union([id]))
            result.merge(RunProperties(node.child("rPr")))
            resolvedRuns[id] = result
            return result
        }
        let output = NSMutableAttributedString(attributedString: native)
        let source = native.string as NSString
        let nativeParagraphs = paragraphRanges(in: source)
        var next = 0
        for paragraph in body?.paragraphs() ?? [] {
            let direct = Properties(paragraph.child("pPr"))
            var properties = resolve(paragraph.child("pPr")?.child("pStyle")?.value("val") ?? defaultStyle)
            // Numbering contributes layout between the paragraph style and direct
            // formatting. Keep AppKit's actual list objects/markers intact.
            var list = properties
            list.merge(direct)
            if let numID = list.values["numPr.numId"], numID != "0", let numberRoot,
               let instance = numberRoot.childrenNamed("num").first(where: { $0.value("numId") == numID }),
               let abstractID = instance.child("abstractNumId")?.value("val"),
               let abstract = numberRoot.childrenNamed("abstractNum").first(where: { $0.value("abstractNumId") == abstractID }) {
                let level = list.values["numPr.ilvl"] ?? "0"
                let override = instance.childrenNamed("lvlOverride").first(where: { $0.value("ilvl") == level })?.child("lvl")
                let definition = override ?? abstract.childrenNamed("lvl").first(where: { $0.value("ilvl") == level })
                properties.merge(Properties(definition?.child("pPr")))
            }
            properties.merge(direct)
            let expected = normalized(paragraph.visibleText())
            // A table, field, or tracked change can add/remove native paragraphs.
            // Match visible text before applying anything; never zip by ordinal.
            var found: Int?
            for index in next..<min(next + 12, nativeParagraphs.count) {
                let actual = normalized(source.substring(with: nativeParagraphs[index]))
                let numbered = list.values["numPr.numId"].map { $0 != "0" } ?? false
                if actual == expected || (numbered && !expected.isEmpty && actual.hasSuffix("\t" + expected)) {
                    found = index
                    break
                }
                if expected.isEmpty { break }
            }
            guard let index = found else { continue }
            next = index + 1
            let range = nativeParagraphs[index]
            guard range.length > 0 else { continue }
            let existing = output.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle ?? .default
            guard let style = existing.mutableCopy() as? NSMutableParagraphStyle else { continue }
            properties.apply(to: style)
            output.addAttribute(.paragraphStyle, value: style, range: range)
            let paragraphRuns = resolveRuns(paragraph.child("pPr")?.child("pStyle")?.value("val") ?? defaultStyle)
            let paragraphText = (source.substring(with: range).replacingOccurrences(of: "\u{2028}", with: "\n")) as NSString
            let visibleText = paragraph.visibleText()
            let contentRange = paragraphText.range(of: visibleText, options: .literal)
            guard contentRange.location != NSNotFound else { continue }
            var runOffset = range.location + contentRange.location
            for run in paragraph.runs() {
                let length = (run.visibleText() as NSString).length
                guard runOffset + length <= NSMaxRange(range) else { break }
                var formatting = paragraphRuns
                if let id = run.child("rPr")?.child("rStyle")?.value("val") {
                    // Character styles inherit from their own chain; document
                    // defaults must not erase the paragraph style underneath.
                    var chain: [XMLElement] = []
                    var seen = Set<String>()
                    var nextID: String? = id
                    while let current = nextID, seen.insert(current).inserted, chain.count < 64, let node = definitions[current] {
                        chain.append(node)
                        nextID = node.child("basedOn")?.value("val")
                    }
                    for node in chain.reversed() { formatting.merge(RunProperties(node.child("rPr"))) }
                }
                formatting.merge(RunProperties(run.child("rPr")))
                let runRange = NSRange(location: runOffset, length: length)
                formatting.apply(to: output, range: runRange)
                var ancestor = run.parent as? XMLElement
                while let node = ancestor, node !== paragraph {
                    if node.isWordElement, node.localName == "hyperlink", let id = node.value("id"), let url = links[id], length > 0 {
                        output.addAttribute(.link, value: url, range: runRange)
                        break
                    }
                    ancestor = node.parent as? XMLElement
                }
                runOffset += length
            }
        }
        return output
    }

    private static func parse(_ data: Data) throws -> XMLElement {
        // No document type or entity expansion is needed in Word parts.
        let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
        guard document.dtd == nil, let root = document.rootElement() else { throw CocoaError(.fileReadCorruptFile) }
        return root
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2028}", with: "\n").trimmingCharacters(in: .newlines)
    }

    private static func paragraphRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var start = 0
        // Word line breaks remain U+2028 inside a paragraph. Table cell endings
        // are emitted as newline by AppKit, and retain their text block attributes.
        for offset in 0..<source.length where source.character(at: offset) == 10 || source.character(at: offset) == 0x2029 {
            ranges.append(NSRange(location: start, length: offset + 1 - start))
            start = offset + 1
        }
        if start < source.length { ranges.append(NSRange(location: start, length: source.length - start)) }
        return ranges
    }

    private struct RunProperties {
        var values: [String: String] = [:]
        init(_ node: XMLElement?) {
            for name in ["b", "i", "sz", "color", "u", "strike", "vertAlign"] {
                if let child = node?.child(name) { values[name] = child.value("val") ?? "1" }
            }
            let fonts = node?.child("rFonts")
            values["font"] = fonts?.value("ascii") ?? fonts?.value("hAnsi")
        }
        mutating func merge(_ other: RunProperties) { values.merge(other.values) { _, new in new } }
        func apply(to text: NSMutableAttributedString, range: NSRange) {
            guard range.length > 0, !values.isEmpty else { return }
            var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
            text.enumerateAttributes(in: range) { existing, run, _ in
                guard existing[.attachment] == nil else { return }
                var attributes: [NSAttributedString.Key: Any] = [:]
                let original = existing[.font] as? NSFont ?? NSFont.systemFont(ofSize: 12)
                var size = original.pointSize
                if let raw = values["sz"], let points = Double(raw), points.isFinite, points > 0, points <= 3_276 {
                    size = CGFloat(points / 2)
                }
                var font = values["font"].flatMap { NSFont(name: $0, size: size) } ?? NSFontManager.shared.convert(original, toSize: size)
                // Keep native traits unless Word explicitly supplies a value.
                for (key, trait) in [("b", NSFontTraitMask.boldFontMask), ("i", NSFontTraitMask.italicFontMask)] {
                    if let value = values[key] {
                        font = ["0", "false", "off"].contains(value)
                            ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                            : NSFontManager.shared.convert(font, toHaveTrait: trait)
                    } else if NSFontManager.shared.traits(of: original).contains(trait) {
                        font = NSFontManager.shared.convert(font, toHaveTrait: trait)
                    }
                }
                attributes[.font] = font
                if let hex = values["color"], hex.count == 6, let rgb = UInt32(hex, radix: 16) {
                    attributes[.foregroundColor] = NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
                }
                if let underline = values["u"] {
                    attributes[.underlineStyle] = underline == "none" ? 0 : (underline == "double" ? NSUnderlineStyle.double.rawValue : NSUnderlineStyle.single.rawValue)
                }
                if let strike = values["strike"] { attributes[.strikethroughStyle] = ["0", "false", "off"].contains(strike) ? 0 : NSUnderlineStyle.single.rawValue }
                if let vertical = values["vertAlign"] { attributes[.superscript] = vertical == "superscript" ? 1 : (vertical == "subscript" ? -1 : 0) }
                changes.append((run, attributes))
            }
            for (run, attributes) in changes { text.addAttributes(attributes, range: run) }
        }
    }

    private struct Properties {
        var values: [String: String] = [:]
        var tabs: [CGFloat: String] = [:]

        init(_ node: XMLElement?) {
            for child in node?.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                guard child.isWordElement else { continue }
                let name = child.localName ?? ""
                if name == "tabs" {
                    for tab in child.childrenNamed("tab") {
                        if let raw = tab.value("pos"), let position = Double(raw), position.isFinite {
                            tabs[CGFloat(position / 20)] = tab.value("val") ?? "left"
                        }
                    }
                } else if name == "numPr" {
                    for item in ["numId", "ilvl"] { values["numPr." + item] = child.child(item)?.value("val") }
                } else if ["ind", "spacing"].contains(name) {
                    for attribute in child.attributes ?? [] {
                        if let key = attribute.localName, let value = attribute.stringValue { values[name + "." + key] = value }
                    }
                } else if ["jc", "bidi", "outlineLvl"].contains(name) {
                    values[name] = child.value("val") ?? "1"
                }
            }
        }

        mutating func merge(_ other: Properties) {
            // A direct first-line indent cancels an inherited hanging indent, and
            // vice versa. Explicit zero values must also override the parent.
            if other.values["ind.firstLine"] != nil { values.removeValue(forKey: "ind.hanging") }
            if other.values["ind.hanging"] != nil { values.removeValue(forKey: "ind.firstLine") }
            values.merge(other.values) { _, new in new }
            tabs.merge(other.tabs) { _, new in new }
        }

        func apply(to style: NSMutableParagraphStyle) {
            func number(_ key: String) -> CGFloat? {
                guard let raw = values[key], let value = Double(raw), value.isFinite, abs(value) < 10_000_000 else { return nil }
                return CGFloat(value)
            }
            let rtl = values["bidi"].map { !["0", "false", "off"].contains($0) }
            if let rtl { style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight }
            let left = number("ind.start") ?? number("ind.left")
            let right = number("ind.end") ?? number("ind.right")
            if let left { style.headIndent = left / 20 }
            if let right { style.tailIndent = -right / 20 }
            if let hanging = number("ind.hanging") {
                style.firstLineHeadIndent = style.headIndent - hanging / 20
            } else if let first = number("ind.firstLine") {
                style.firstLineHeadIndent = style.headIndent + first / 20
            } else if left != nil { style.firstLineHeadIndent = style.headIndent }
            if let before = number("spacing.before") { style.paragraphSpacingBefore = max(0, before / 20) }
            if let after = number("spacing.after") { style.paragraphSpacing = max(0, after / 20) }
            if let line = number("spacing.line"), line > 0 {
                switch values["spacing.lineRule"] ?? "auto" {
                case "exact":
                    style.lineHeightMultiple = 0
                    style.minimumLineHeight = line / 20
                    style.maximumLineHeight = line / 20
                case "atLeast":
                    style.lineHeightMultiple = 0
                    style.minimumLineHeight = line / 20
                    style.maximumLineHeight = 0
                default:
                    style.minimumLineHeight = 0
                    style.maximumLineHeight = 0
                    style.lineHeightMultiple = line / 240
                }
            }
            if let alignment = values["jc"] {
                switch alignment {
                case "left": style.alignment = .left
                case "right": style.alignment = .right
                case "center": style.alignment = .center
                case "both", "distribute": style.alignment = .justified
                case "start": style.alignment = rtl == true ? .right : .left
                case "end": style.alignment = rtl == true ? .left : .right
                default: break
                }
            }
            if let level = number("outlineLvl"), level >= 0, level < 9 { style.headerLevel = Int(level) + 1 }
            if !tabs.isEmpty {
                var stops = style.tabStops.filter { tabs[$0.location] == nil }
                for (position, kind) in tabs where kind != "clear" && kind != "bar" {
                    let alignment: NSTextAlignment = kind == "right" ? .right : (kind == "center" ? .center : (kind == "decimal" ? .right : .left))
                    let options: [NSTextTab.OptionKey: Any] = kind == "decimal" ? [.columnTerminators: CharacterSet(charactersIn: ".,")] : [:]
                    stops.append(NSTextTab(textAlignment: alignment, location: position, options: options))
                }
                style.tabStops = stops.sorted { $0.location < $1.location }
            }
        }
    }
}

private extension XMLElement {
    var isWordElement: Bool {
        uri == "http://schemas.openxmlformats.org/wordprocessingml/2006/main" || uri == "http://purl.oclc.org/ooxml/wordprocessingml/main"
    }
    func childrenNamed(_ name: String) -> [XMLElement] {
        children?.compactMap { $0 as? XMLElement }.filter { $0.isWordElement && $0.localName == name } ?? []
    }
    func child(_ name: String) -> XMLElement? { childrenNamed(name).first }
    func value(_ name: String) -> String? { attributes?.first { $0.localName == name }?.stringValue }
    func paragraphs() -> [XMLElement] {
        if isWordElement, localName == "p" { return [self] }
        if isWordElement, ["del", "moveFrom"].contains(localName ?? "") { return [] }
        return children?.compactMap { $0 as? XMLElement }.flatMap { $0.paragraphs() } ?? []
    }
    func runs() -> [XMLElement] {
        if isWordElement, localName == "r" { return [self] }
        if isWordElement, ["del", "moveFrom", "pPr"].contains(localName ?? "") { return [] }
        return children?.compactMap { $0 as? XMLElement }.flatMap { $0.runs() } ?? []
    }
    func visibleText() -> String {
        if isWordElement {
            switch localName {
            case "t": return stringValue ?? ""
            case "tab": return "\t"
            case "br", "cr": return "\n"
            case "drawing", "pict", "object": return "\u{FFFC}"
            case "del", "moveFrom", "pPr", "rPr", "instrText": return ""
            default: break
            }
        }
        return children?.compactMap { $0 as? XMLElement }.map { $0.visibleText() }.joined() ?? ""
    }
}

/// Reads only the XML parts we need, without extracting paths or launching
/// an unsandboxed helper. Central-directory lengths bound all decompression.
enum WordPackageXML {
    static func replacingDocument(in archive: Data, with xml: Data) throws -> Data {
        // AppKit creates ordinary single-disk ZIP files. Keep every other part's
        // compressed bytes and central record, changing only document.xml.
        func number(_ data: Data, _ offset: Int, _ size: Int) throws -> Int {
            guard offset >= 0, offset + size <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            return (0..<size).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        func put(_ value: Int, _ size: Int, into data: inout Data) {
            for shift in 0..<size { data.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) }
        }
        guard archive.count >= 22 else { throw CocoaError(.fileReadCorruptFile) }
        var end: Int?
        for offset in stride(from: archive.count - 22, through: max(0, archive.count - 65_557), by: -1) {
            if try number(archive, offset, 4) == 0x06054b50, try offset + 22 + number(archive, offset + 20, 2) == archive.count { end = offset; break }
        }
        guard let end else { throw CocoaError(.fileReadCorruptFile) }
        let count = try number(archive, end + 10, 2)
        let originalDirectory = try number(archive, end + 16, 4)
        guard originalDirectory <= end else { throw CocoaError(.fileReadCorruptFile) }
        var output = Data(archive.prefix(originalDirectory))
        let localOffset = output.count
        let name = Data("word/document.xml".utf8)
        let checksum = Int(xml.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(xml.count)) })
        for (value, size) in [(0x04034b50, 4), (20, 2), (0, 2), (0, 2), (0, 2), (0, 2), (checksum, 4), (xml.count, 4), (xml.count, 4), (name.count, 2), (0, 2)] { put(value, size, into: &output) }
        output.append(name)
        output.append(xml)
        let directoryOffset = output.count
        var cursor = originalDirectory
        var replaced = false
        for _ in 0..<count {
            guard try number(archive, cursor, 4) == 0x02014b50 else { throw CocoaError(.fileReadCorruptFile) }
            let nameLength = try number(archive, cursor + 28, 2)
            let extra = try number(archive, cursor + 30, 2)
            let comment = try number(archive, cursor + 32, 2)
            let next = cursor + 46 + nameLength + extra + comment
            guard next <= end else { throw CocoaError(.fileReadCorruptFile) }
            var record = Data(archive[cursor..<next])
            if Data(record[46..<(46 + nameLength)]) == name {
                guard !replaced else { throw CocoaError(.fileReadCorruptFile) }
                replaced = true
                for (offset, value, size) in [(8, 0, 2), (10, 0, 2), (16, checksum, 4), (20, xml.count, 4), (24, xml.count, 4), (42, localOffset, 4)] {
                    var bytes = Data(); put(value, size, into: &bytes)
                    record.replaceSubrange(offset..<(offset + size), with: bytes)
                }
            }
            output.append(record)
            cursor = next
        }
        guard replaced else { throw CocoaError(.fileWriteUnknown) }
        let directorySize = output.count - directoryOffset
        for (value, size) in [(0x06054b50, 4), (0, 2), (0, 2), (count, 2), (count, 2), (directorySize, 4), (directoryOffset, 4), (0, 2)] { put(value, size, into: &output) }
        return output
    }

    static func read(from url: URL) throws -> [String: Data] {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 512 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
        return try read(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func read(_ data: Data) throws -> [String: Data] {
        func integer(_ offset: Int, _ size: Int) throws -> Int {
            guard offset >= 0, offset <= data.count, size <= data.count - offset else { throw CocoaError(.fileReadCorruptFile) }
            return (0..<size).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        guard data.count >= 22 else { throw CocoaError(.fileReadCorruptFile) }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try integer(offset, 4) == 0x06054b50, try offset + 22 + integer(offset + 20, 2) == data.count { end = offset; break }
        }
        guard let end, try integer(end + 4, 2) == 0, try integer(end + 6, 2) == 0 else { throw CocoaError(.fileReadCorruptFile) }
        let count = try integer(end + 10, 2)
        var cursor = try integer(end + 16, 4)
        guard count < 65_535 else { throw CocoaError(.fileReadUnsupportedScheme) }
        var result: [String: Data] = [:]
        for _ in 0..<count {
            guard try integer(cursor, 4) == 0x02014b50 else { throw CocoaError(.fileReadCorruptFile) }
            let flags = try integer(cursor + 8, 2)
            let method = try integer(cursor + 10, 2)
            let checksum = try integer(cursor + 16, 4)
            let compressed = try integer(cursor + 20, 4)
            let expanded = try integer(cursor + 24, 4)
            let nameLength = try integer(cursor + 28, 2)
            let extra = try integer(cursor + 30, 2)
            let comment = try integer(cursor + 32, 2)
            let local = try integer(cursor + 42, 4)
            let next = cursor + 46 + nameLength + extra + comment
            guard next <= end else { throw CocoaError(.fileReadCorruptFile) }
            let name = String(data: data[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8) ?? ""
            cursor = next
            guard ["word/document.xml", "word/styles.xml", "word/numbering.xml", "word/_rels/document.xml.rels"].contains(name) else { continue }
            guard result[name] == nil, flags & 1 == 0, [0, 8].contains(method), expanded <= 64 * 1_024 * 1_024,
                  try integer(local, 4) == 0x04034b50 else { throw CocoaError(.fileReadCorruptFile) }
            let start = try local + 30 + integer(local + 26, 2) + integer(local + 28, 2)
            guard start <= data.count, compressed <= data.count - start else { throw CocoaError(.fileReadCorruptFile) }
            let packed = Data(data[start..<(start + compressed)])
            let unpacked: Data
            if method == 0 {
                guard compressed == expanded else { throw CocoaError(.fileReadCorruptFile) }
                unpacked = packed
            } else {
                var output = Data(count: max(1, expanded))
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw CocoaError(.fileReadCorruptFile) }
                defer { inflateEnd(&stream) }
                let capacity = output.count
                let status = output.withUnsafeMutableBytes { destination in
                    packed.withUnsafeBytes { source in
                        stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                        stream.avail_in = uInt(packed.count)
                        stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                        stream.avail_out = uInt(capacity)
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == expanded, stream.total_in == compressed else { throw CocoaError(.fileReadCorruptFile) }
                unpacked = output.prefix(expanded)
            }
            let actualCRC = unpacked.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(unpacked.count)) }
            guard actualCRC == checksum else { throw CocoaError(.fileReadCorruptFile) }
            result[name] = unpacked
        }
        return result
    }
}
