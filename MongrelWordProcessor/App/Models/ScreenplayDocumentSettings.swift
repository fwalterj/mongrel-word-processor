import AppKit

/// Production identity and reading preferences travel with the document, not the app.
struct ScreenplayDocumentSettings: Codable, Equatable {
    var format: ScreenplayProductionFormat = .feature
    var draft: ScreenplayDraftStage = .working
    var voice: ScreenplayPageVoice = .classic
    var showsSceneCount = true
    var showsSceneNumbers = false
    var sceneRecords: [ScreenplayProductionScene] = []
}

enum ScreenplayProductionFormat: String, Codable, CaseIterable, Identifiable {
    case scene, short, feature, singleCamera, multiCamera
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scene: return "Scene / sketch"
        case .short: return "Short film"
        case .feature: return "Feature film"
        case .singleCamera: return "Single-camera TV"
        case .multiCamera: return "Multi-camera TV"
        }
    }
}

enum ScreenplayDraftStage: String, Codable, CaseIterable, Identifiable {
    case working, reader, production
    var id: String { rawValue }
    var title: String {
        switch self {
        case .working: return "Working draft"
        case .reader: return "Reader / spec draft"
        case .production: return "Production draft"
        }
    }
}

enum ScreenplayPageVoice: String, Codable, CaseIterable, Identifiable {
    case classic, minimal, narrative, literary, propulsive, suspense, dialogue
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .minimal: return "Minimal"
        case .narrative: return "Narrative"
        case .literary: return "Literary"
        case .propulsive: return "Momentum"
        case .suspense: return "Suspense"
        case .dialogue: return "Performance"
        }
    }
    var description: String {
        switch self {
        case .classic: return "Quiet formatting. Write at your own pace."
        case .minimal: return "Lean action. Behavior and actors carry the scene."
        case .narrative: return "Room for images, impressions, and a voice on the page."
        case .literary: return "Long passages and authorial asides have room to breathe."
        case .propulsive: return "Short visual beats. Notice where the eye slows down."
        case .suspense: return "Space for anticipation. Let an observation stand alone."
        case .dialogue: return "Spoken exchanges carry the rhythm. Action stays quiet."
        }
    }
    var actionLineTarget: Int {
        switch self {
        case .classic: return 4
        case .minimal, .propulsive, .suspense: return 2
        case .narrative: return 6
        case .literary: return 10
        case .dialogue: return 3
        }
    }
}

struct ScreenplayProductionScene: Codable, Equatable, Identifiable {
    let id: String
    let number: String
    var heading: String
    var isOmitted: Bool
}

extension NSAttributedString.Key {
    static let screenplayManualElement = NSAttributedString.Key("com.mongrel.wordprocessor.manualElement")
    static let screenplaySceneIdentity = NSAttributedString.Key("com.mongrel.wordprocessor.sceneIdentity")
}

/// Persist custom attributes separately because RTF does not retain application keys.
struct ScreenplaySceneIdentityRange: Codable {
    let location: Int
    let length: Int
    let identity: String

    static func collect(from text: NSAttributedString, key: NSAttributedString.Key = .screenplaySceneIdentity) -> [Self] {
        var ranges: [Self] = []
        text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let identity = value as? String {
                ranges.append(Self(location: range.location, length: range.length, identity: identity))
            }
        }
        return ranges
    }

    static func restore(_ ranges: [Self]?, to text: NSMutableAttributedString, key: NSAttributedString.Key = .screenplaySceneIdentity) {
        for range in ranges ?? [] {
            guard range.location >= 0, range.length > 0, range.location <= text.length,
                  range.length <= text.length - range.location else { continue }
            text.addAttribute(key, value: range.identity,
                              range: NSRange(location: range.location, length: range.length))
        }
    }
}

struct ScreenplayCatalog: Equatable {
    var characters: [String] = []
    var locations: [String] = []
    var headings: [String] = []
    var actionBlocks: [ScreenplayActionBlock] = []

    static func analyze(_ text: NSAttributedString) -> Self {
        let source = text.string as NSString
        var result = Self()
        var names = Set<String>()
        var places = Set<String>()
        var headings = Set<String>()
        var location = 0
        while location < source.length {
            let range = source.paragraphRange(for: NSRange(location: location, length: 0))
            let value = source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let tag = elementTag(in: text, at: location)
            if tag == .character, !value.isEmpty {
                let name = canonicalCharacterName(value)
                if !name.isEmpty { names.insert(name) }
            } else if tag == .sceneHeading || (tag == nil && isSceneHeading(value)) {
                let heading = value.uppercased()
                if !heading.isEmpty { headings.insert(heading) }
                let place = locationName(heading)
                if !place.isEmpty { places.insert(place) }
            } else if (tag == nil || tag == .action), !value.isEmpty {
                result.actionBlocks.append(ScreenplayActionBlock(location: location, text: value,
                    estimatedLines: max(1, Int(ceil(Double(value.count) / 60)))))
            }
            location = NSMaxRange(range)
        }
        result.characters = names.sorted()
        result.locations = places.sorted()
        result.headings = headings.sorted()
        return result
    }

    static let scenePrefixes = ["INT./EXT.", "EXT./INT.", "INT/EXT.", "EXT/INT.", "INT.", "EXT.", "I/E.", "EST."]

    static func elementTag(in text: NSAttributedString, at location: Int) -> ScreenplayElement? {
        guard location >= 0, location < text.length else { return nil }
        for key in [NSAttributedString.Key.screenplayManualElement, .screenplayElement] {
            if let raw = text.attribute(key, at: location, effectiveRange: nil) as? String,
               let element = ScreenplayElement(rawValue: raw) { return element }
        }
        return nil
    }

    static func isSceneHeading(_ text: String) -> Bool {
        let upper = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return scenePrefixes.contains { upper == $0 || upper.hasPrefix($0 + " ") || upper.hasPrefix($0 + "\t") }
    }

    static func canonicalCharacterName(_ cue: String) -> String {
        var name = cue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let suffixes = [" (O.S.)", " (V.O.)", " (O.C.)", " (CONT'D)", " (CONT’D)", " (CONTINUED)", " ^"]
        while let suffix = suffixes.first(where: { name.hasSuffix($0) }) {
            name.removeLast(suffix.count)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name
    }

    static func locationName(_ heading: String) -> String {
        var location = heading
        if let prefix = scenePrefixes.first(where: { location.hasPrefix($0) }) {
            location.removeFirst(prefix.count)
        }
        // Only strip a time suffix. Keep compound locations such as HOUSE - KITCHEN.
        let times = ["DAY", "NIGHT", "MORNING", "AFTERNOON", "EVENING", "DAWN", "DUSK", "LATER", "CONTINUOUS", "SAME TIME", "MOMENTS LATER", "SUNSET", "SUNRISE"]
        for separator in [" - ", " – ", " — "] {
            if let split = location.range(of: separator, options: .backwards) {
                let suffix = String(location[split.upperBound...]).trimmingCharacters(in: .whitespaces)
                if times.contains(suffix) { location = String(location[..<split.lowerBound]); break }
            }
        }
        return location.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ScreenplayActionBlock: Equatable, Identifiable {
    let location: Int
    let text: String
    let estimatedLines: Int
    var id: Int { location }
}

/// Reserved numbers survive deletion. Inserting or moving a scene never renumbers an existing one.
enum ScreenplayProductionNumbering {
    static func suffix(_ index: Int) -> String {
        var value = index
        var result = ""
        repeat {
            result = String(UnicodeScalar(65 + value % 26)!) + result
            value = value / 26 - 1
        } while value >= 0
        return result
    }

    static func nextNumber(after previous: String?, reserved: Set<String>, initial: Bool) -> String {
        let base = previous.map { String($0.prefix(while: \.isNumber)) } ?? "0"
        let numeric = Int(base) ?? 0
        if initial { return String(numeric + 1) }
        var index = 0
        while reserved.contains(base + suffix(index)) { index += 1 }
        return base + suffix(index)
    }
}

struct NativePreservedCharacter: Codable {
    let location: Int
    let codeUnit: UInt16
}

/// RTF can normalize control characters and drop bare object markers from PDF
/// extracts. Escape those with same-length placeholders so semantic ranges and
/// the original text both survive a native round trip.
enum NativeRichTextCodec {
    static func encode(_ text: NSAttributedString, type: NSAttributedString.DocumentType) throws -> (Data, [NativePreservedCharacter]) {
        let safe = NSMutableAttributedString(attributedString: text)
        let source = text.string as NSString
        var preserved: [NativePreservedCharacter] = []
        for location in 0..<source.length {
            let unit = source.character(at: location)
            let isControl = unit < 32 && unit != 10 && unit != 9
            let isSeparator = unit == 0x2028 || unit == 0x2029
            let isBareObject = unit == 0xFFFC && text.attribute(.attachment, at: location, effectiveRange: nil) == nil
            if isControl || isSeparator || isBareObject || unit >= 0xFFFD {
                safe.replaceCharacters(in: NSRange(location: location, length: 1), with: "\u{E000}")
                preserved.append(NativePreservedCharacter(location: location, codeUnit: unit))
            }
        }
        return (try safe.data(from: NSRange(location: 0, length: safe.length), documentAttributes: [.documentType: type]), preserved)
    }

    static func restorePlaceholders(_ characters: [NativePreservedCharacter]?, in text: NSMutableAttributedString) {
        for character in characters ?? [] {
            guard character.location >= 0, character.location < text.length,
                  let scalar = UnicodeScalar(UInt32(character.codeUnit)),
                  (text.string as NSString).character(at: character.location) == 0xE000 else { continue }
            text.replaceCharacters(in: NSRange(location: character.location, length: 1), with: String(scalar))
        }
    }
}
