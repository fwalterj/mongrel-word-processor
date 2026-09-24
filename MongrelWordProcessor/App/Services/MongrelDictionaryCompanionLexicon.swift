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

final class MongrelDictionaryCompanionLexicon: @unchecked Sendable {
    static let didFinishLoadingNotification = Notification.Name(
        "MongrelDictionaryCompanionLexiconDidFinishLoading"
    )
    private static let correctionAlphabet = Array("abcdefghijklmnopqrstuvwxyz'-")

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

    private struct Storage {
        let headwords: Set<String>
        let sortedHeadwords: [String]
    }

    private enum LoadState {
        case pending(URL?)
        case loading
        case loaded(Storage)
    }

    private let loadCondition = NSCondition()
    private var loadState: LoadState
    let status: MongrelDictionaryCompanionStatus

    init() {
        let packageURL = Self.resolvePackageURL()
        let dictionaryURL = packageURL?.appendingPathComponent("spellcheck_dictionary.txt")
        let manifestURL = packageURL?.appendingPathComponent("manifest.json")

        let manifest = Self.loadManifest(from: manifestURL)
        let sourceDescription = packageURL?.path ?? "Unavailable"
        let isAvailable = dictionaryURL.map { FileManager.default.isReadableFile(atPath: $0.path) } ?? false

        self.loadState = .pending(dictionaryURL)
        self.status = MongrelDictionaryCompanionStatus(
            isAvailable: isAvailable,
            sourceDescription: sourceDescription,
            headwordCount: manifest?.counts.headwords ?? 0,
            structuredEntryCount: manifest?.counts.structuredEntries ?? 0
        )

        if isAvailable {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.preload()
            }
        }
    }

    init(headwords: [String], sourceDescription: String = "Injected lexicon") {
        let normalizedHeadwords = headwords
            .map(Self.normalizedLookupKey)
            .filter { !$0.isEmpty }
        let uniqueHeadwords = Array(Set(normalizedHeadwords)).sorted()

        self.loadState = .loaded(Storage(
            headwords: Set(uniqueHeadwords),
            sortedHeadwords: uniqueHeadwords
        ))
        self.status = MongrelDictionaryCompanionStatus(
            isAvailable: !uniqueHeadwords.isEmpty,
            sourceDescription: sourceDescription,
            headwordCount: uniqueHeadwords.count,
            structuredEntryCount: 0
        )
    }

    func contains(_ word: String) -> Bool {
        storage().headwords.contains(Self.normalizedLookupKey(word))
    }

    func suggestions(for word: String, limit: Int = 6) -> [String] {
        guard limit > 0 else { return [] }
        guard let storage = loadedStorage() else { return [] }
        let normalized = Self.normalizedLookupKey(word)
        guard normalized.count >= 2, !storage.headwords.contains(normalized) else { return [] }

        let prefix = String(normalized.prefix(min(3, normalized.count)))
        let prefixCandidates = prefixMatches(
            prefix: prefix,
            limit: max(limit * 4, 24),
            sortedHeadwords: storage.sortedHeadwords
        )
            .filter { $0 != normalized }
        let corrections = singleEditCorrections(for: normalized, headwords: storage.headwords)
        let correctionSet = Set(corrections)
        let candidates = Set(prefixCandidates).union(correctionSet)

        return candidates
            .sorted { lhs, rhs in
                let lhsRank = suggestionRank(lhs, term: normalized, corrections: correctionSet)
                let rhsRank = suggestionRank(rhs, term: normalized, corrections: correctionSet)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.count != rhs.count { return lhs.count < rhs.count }
                return lhs < rhs
            }
            .prefix(limit)
            .map { $0 }
    }

    func tokenizedCompanionWords(in text: String) -> [String] {
        guard let headwords = loadedStorage()?.headwords else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{M}][\p{L}\p{M}'’\-]*"#, options: []) else {
            return []
        }

        var matches: [String] = []
        for match in regex.matches(in: text, options: [], range: fullRange) {
            let token = nsText.substring(with: match.range)
            if headwords.contains(Self.normalizedLookupKey(token)) {
                matches.append(token)
            }
        }
        return matches
    }

    private func prefixMatches(prefix: String, limit: Int, sortedHeadwords: [String]) -> [String] {
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

    private func preload() {
        _ = storage()
    }

    private func storage() -> Storage {
        loadCondition.lock()

        while true {
            switch loadState {
            case .loaded(let storage):
                loadCondition.unlock()
                return storage
            case .loading:
                loadCondition.wait()
            case .pending(let url):
                loadState = .loading
                loadCondition.unlock()

                let loadedHeadwords = Self.loadHeadwords(from: url)
                let storage = Storage(
                    headwords: Set(loadedHeadwords),
                    sortedHeadwords: loadedHeadwords
                )

                loadCondition.lock()
                loadState = .loaded(storage)
                loadCondition.broadcast()
                loadCondition.unlock()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    NotificationCenter.default.post(
                        name: Self.didFinishLoadingNotification,
                        object: self
                    )
                }
                return storage
            }
        }
    }

    private func loadedStorage() -> Storage? {
        loadCondition.lock()
        defer { loadCondition.unlock() }
        guard case .loaded(let storage) = loadState else { return nil }
        return storage
    }

    private func suggestionRank(_ candidate: String, term: String, corrections: Set<String>) -> Int {
        if candidate.hasPrefix(term) { return 0 }
        if corrections.contains(candidate) { return 1 }
        return 2
    }

    private func singleEditCorrections(for term: String, headwords: Set<String>) -> [String] {
        let characters = Array(term)
        var matches = Set<String>()

        func include(_ candidate: [Character]) {
            let value = String(candidate)
            if value != term, headwords.contains(value) {
                matches.insert(value)
            }
        }

        for index in characters.indices {
            var copy = characters
            copy.remove(at: index)
            include(copy)
        }

        if characters.count > 1 {
            for index in 0..<(characters.count - 1) where characters[index] != characters[index + 1] {
                var copy = characters
                copy.swapAt(index, index + 1)
                include(copy)
            }
        }

        for index in characters.indices {
            for replacement in Self.correctionAlphabet where replacement != characters[index] {
                var copy = characters
                copy[index] = replacement
                include(copy)
            }
        }

        for index in 0...characters.count {
            for insertion in Self.correctionAlphabet {
                var copy = characters
                copy.insert(insertion, at: index)
                include(copy)
            }
        }

        return matches.sorted()
    }

    private static func resolvePackageURL() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("MongrelDictionaryCompanionPackage"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        // Xcode flattens folder references added as resources in generated projects.
        if let bundledDictionary = Bundle.main.url(
            forResource: "spellcheck_dictionary",
            withExtension: "txt"
        ) {
            return bundledDictionary.deletingLastPathComponent()
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
