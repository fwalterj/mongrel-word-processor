import Foundation

struct DocumentInsightScene: Identifiable, Equatable {
    let id: Int
    let title: String
    let share: Double
}

struct DocumentInsightCharacter: Identifiable, Equatable {
    let name: String
    let cueCount: Int

    var id: String { name }
}

struct DocumentInsightSnapshot: Equatable {
    let readingMinutes: Int
    let sentenceCount: Int
    let paragraphWordCounts: [Int]
    let averageWordsPerSentence: Double
    let dialogueShare: Double
    let scenes: [DocumentInsightScene]
    let characters: [DocumentInsightCharacter]

    static let empty = DocumentInsightSnapshot(
        readingMinutes: 0,
        sentenceCount: 0,
        paragraphWordCounts: [],
        averageWordsPerSentence: 0,
        dialogueShare: 0,
        scenes: [],
        characters: []
    )
}

enum DocumentInsightsAnalyzer {
    static func analyze(
        _ attributedText: NSAttributedString,
        scenes: [ScreenplayScene],
        mode: AuthoringMode
    ) -> DocumentInsightSnapshot {
        let text = attributedText.string
        guard !text.isEmpty else { return .empty }

        let words = text.split(whereSeparator: \.isWhitespace).count
        let paragraphCounts = text
            .components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).count }
            .filter { $0 > 0 }
        let sentenceCount = countSentences(in: text)
        let sceneInsights = makeScenes(scenes, documentLength: attributedText.length)
        let screenplayBreakdown = mode == .screenplay
            ? screenplayMetrics(in: attributedText)
            : (dialogueWords: 0, characters: [])

        return DocumentInsightSnapshot(
            readingMinutes: words == 0 ? 0 : max(1, Int(ceil(Double(words) / 225))),
            sentenceCount: sentenceCount,
            paragraphWordCounts: sample(paragraphCounts, limit: 72),
            averageWordsPerSentence: sentenceCount == 0 ? 0 : Double(words) / Double(sentenceCount),
            dialogueShare: words == 0 ? 0 : Double(screenplayBreakdown.dialogueWords) / Double(words),
            scenes: sceneInsights,
            characters: screenplayBreakdown.characters
        )
    }

    private static func countSentences(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    private static func makeScenes(_ scenes: [ScreenplayScene], documentLength: Int) -> [DocumentInsightScene] {
        guard !scenes.isEmpty, documentLength > 0 else { return [] }
        return scenes.enumerated().map { index, scene in
            let end = index + 1 < scenes.count ? scenes[index + 1].location : documentLength
            let length = max(1, end - scene.location)
            return DocumentInsightScene(
                id: scene.number,
                title: scene.heading,
                share: Double(length) / Double(documentLength)
            )
        }
    }

    private static func screenplayMetrics(
        in text: NSAttributedString
    ) -> (dialogueWords: Int, characters: [DocumentInsightCharacter]) {
        let source = text.string as NSString
        var dialogueWords = 0
        var characterCounts: [String: Int] = [:]
        var location = 0

        while location < source.length {
            let range = source.paragraphRange(for: NSRange(location: location, length: 0))
            let value = source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawElement = text.attribute(.screenplayElement, at: range.location, effectiveRange: nil) as? String
            let element = rawElement.flatMap(ScreenplayElement.init(rawValue:))

            if element == .dialogue {
                dialogueWords += value.split(whereSeparator: \.isWhitespace).count
            } else if element == .character, !value.isEmpty {
                characterCounts[ScreenplayCatalog.canonicalCharacterName(value), default: 0] += 1
            }
            location = NSMaxRange(range)
        }

        let unsortedCharacters: [DocumentInsightCharacter] = characterCounts.map { entry in
            DocumentInsightCharacter(name: entry.key, cueCount: entry.value)
        }
        let sortedCharacters = unsortedCharacters.sorted { lhs, rhs in
            if lhs.cueCount == rhs.cueCount {
                return lhs.name < rhs.name
            }
            return lhs.cueCount > rhs.cueCount
        }

        return (dialogueWords, sortedCharacters)
    }

    private static func sample(_ values: [Int], limit: Int) -> [Int] {
        guard values.count > limit else { return values }
        let bucketSize = Double(values.count) / Double(limit)
        return (0..<limit).map { bucket in
            let start = Int(Double(bucket) * bucketSize)
            let end = min(values.count, max(start + 1, Int(Double(bucket + 1) * bucketSize)))
            return Int((Double(values[start..<end].reduce(0, +)) / Double(end - start)).rounded())
        }
    }
}
