import Foundation

struct MongrelDictionaryCompanionStatus {
    let isAvailable: Bool
    let sourceDescription: String
    let headwordCount: Int
    let structuredEntryCount: Int

    var summary: String {
        guard isAvailable else { return "System spellcheck" }
        return "Mongrel lexicon \(headwordCount)"
    }
}

final class MongrelDictionaryCompanionLexicon {
    private struct Manifest: Decodable {
        struct Counts: Decodable {
            let referenceNotes: Int
            let structuredEntries: Int
            let headwords: Int
        }

        let generatedAtUTC: String
        let packageName: String
        let counts: Counts
    }

    private let headwords: Set<String>
    private let sortedHeadwords: [String]
    let status: MongrelDictionaryCompanionStatus

    init() {
        let packageURL = Self.resolvePackageURL()
        let dictionaryURL = packageURL?.appendingPathComponent("spellcheck_dictionary.txt")
        let manifestURL = packageURL?.appendingPathComponent("manifest.json")

        let loadedHeadwords = Self.loadHeadwords(from: dictionaryURL)
        let manifest = Self.loadManifest(from: manifestURL)
        let sourceDescription = packageURL?.path ?? "Unavailable"

        self.headwords = Set(loadedHeadwords)
        self.sortedHeadwords = loadedHeadwords
        self.status = MongrelDictionaryCompanionStatus(
            isAvailable: !loadedHeadwords.isEmpty,
            sourceDescription: sourceDescription,
            headwordCount: loadedHeadwords.count,
            structuredEntryCount: manifest?.counts.structuredEntries ?? 0
        )
    }

    func contains(_ word: String) -> Bool {
        headwords.contains(Self.normalizedLookupKey(word))
    }

    func suggestions(for word: String, limit: Int = 6) -> [String] {
        let normalized = Self.normalizedLookupKey(word)
        guard normalized.count >= 2, !headwords.contains(normalized) else { return [] }

        let prefix = String(normalized.prefix(min(3, normalized.count)))
        var candidates = prefixMatches(prefix: prefix, limit: max(limit * 3, 18))
            .filter { $0 != normalized }

        if candidates.count < limit {
            let fuzzyMatches = sortedHeadwords.filter { candidate in
                candidate != normalized && isNearby(candidate, normalized)
            }
            candidates.append(contentsOf: fuzzyMatches)
        }

        return Array(NSOrderedSet(array: candidates)) // preserve order while deduping
            .compactMap { $0 as? String }
            .prefix(limit)
            .map { $0 }
    }

    func tokenizedCompanionWords(in text: String) -> [String] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{M}][\p{L}\p{M}'’\-]*"#, options: []) else {
            return []
        }

        var matches: [String] = []
        for match in regex.matches(in: text, options: [], range: fullRange) {
            let token = nsText.substring(with: match.range)
            if contains(token) {
                matches.append(token)
            }
        }
        return matches
    }

    private func prefixMatches(prefix: String, limit: Int) -> [String] {
        guard !prefix.isEmpty, !sortedHeadwords.isEmpty else { return [] }

        var low = 0
        var high = sortedHeadwords.count
        while low < high {
            let mid = (low + high) / 2
            if sortedHeadwords[mid] < prefix {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var results: [String] = []
        var index = low
        while index < sortedHeadwords.count, sortedHeadwords[index].hasPrefix(prefix), results.count < limit {
            results.append(sortedHeadwords[index])
            index += 1
        }
        return results
    }

    private func isNearby(_ candidate: String, _ term: String) -> Bool {
        if abs(candidate.count - term.count) > 2 {
            return false
        }
        if candidate.hasPrefix(term) || term.hasPrefix(candidate) {
            return true
        }
        return deletionSignatures(for: candidate).contains(term) || deletionSignatures(for: term).contains(candidate)
    }

    private func deletionSignatures(for term: String) -> [String] {
        guard term.count >= 2 else { return [] }
        let characters = Array(term)
        var signatures = Set<String>()

        for index in characters.indices {
            var copy = characters
            copy.remove(at: index)
            let value = String(copy).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                signatures.insert(value)
            }
        }

        return Array(signatures)
    }

    private static func resolvePackageURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("MongrelDictionaryCompanionPackage"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sibling = projectRoot
            .appendingPathComponent("../mongrel-dictionary/MongrelDictionary/App/Data/CompanionExports/MongrelDictionaryCompanionPackage")
            .standardizedFileURL
        if FileManager.default.fileExists(atPath: sibling.path) {
            return sibling
        }

        return nil
    }

    private static func loadHeadwords(from url: URL?) -> [String] {
        guard let url,
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        let headwords = contents
            .split(whereSeparator: \.isNewline)
            .map { normalizedLookupKey(String($0)) }
            .filter { !$0.isEmpty }

        return Array(NSOrderedSet(array: headwords))
            .compactMap { $0 as? String }
            .sorted()
    }

    private static func loadManifest(from url: URL?) -> Manifest? {
        guard let url,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    private static func normalizedLookupKey(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201B}", with: "'")
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2012}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()

        return normalized
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }
}
