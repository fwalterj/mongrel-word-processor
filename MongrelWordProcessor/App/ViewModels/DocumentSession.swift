import Foundation
// MARK: – Recent document model

struct RecentDoc: Identifiable, Codable {
    let id: UUID
    let title: String
    let path: String
    let openedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case path
        case openedAt
    }

    init(title: String, path: String, openedAt: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.path = path
        self.openedAt = openedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        path = try container.decode(String.self, forKey: .path)
        openedAt = try container.decodeIfPresent(Date.self, forKey: .openedAt) ?? Date()
    }
}

extension RecentDoc {
    /// Human-readable relative timestamp, e.g. "2 hours ago"
    var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: openedAt, relativeTo: Date())
    }
}

import AppKit
import UniformTypeIdentifiers
import OSLog

struct ScreenplayPageLayout {
    static let pageSize = NSSize(width: 612, height: 792)
    static let contentWidth: CGFloat = 432
    static let horizontalInset: CGFloat = 90
    static let verticalInset: CGFloat = 72
    static let estimatedLinesPerPage: Double = 55
}

extension NSAttributedString.Key {
    static let screenplayElement = NSAttributedString.Key("com.mongrel.wordprocessor.screenplayElement")
}

enum AuthoringMode: String, CaseIterable {
    case prose
    case code
    case screenplay

    var title: String {
        switch self {
        case .prose: return "Prose"
        case .code: return "Code"
        case .screenplay: return "Screenplay"
        }
    }
}

enum ScreenplayElement: String, CaseIterable {
    case sceneHeading
    case action
    case character
    case parenthetical
    case dialogue
    case transition
    case shot
    case insert
    case titleCard
    case timeJump

    var title: String {
        switch self {
        case .sceneHeading: return "Scene Heading"
        case .action: return "Action"
        case .character: return "Character"
        case .parenthetical: return "Parenthetical"
        case .dialogue: return "Dialogue"
        case .transition: return "Transition"
        case .shot: return "Shot"
        case .insert: return "Insert"
        case .titleCard: return "Title Card"
        case .timeJump: return "Time Jump"
        }
    }

    var shortTitle: String {
        switch self {
        case .sceneHeading: return "Scene"
        case .action: return "Action"
        case .character: return "Character"
        case .parenthetical: return "Paren"
        case .dialogue: return "Dialogue"
        case .transition: return "Transition"
        case .shot: return "Shot"
        case .insert: return "Insert"
        case .titleCard: return "Title Card"
        case .timeJump: return "Time Jump"
        }
    }

    var toolbarLabel: String {
        switch self {
        case .sceneHeading: return "SCENE"
        case .action: return "ACTION"
        case .character: return "CHAR"
        case .parenthetical: return "PAREN"
        case .dialogue: return "DIALOG"
        case .transition: return "TRANS"
        case .shot: return "SHOT"
        case .insert: return "INSERT"
        case .titleCard: return "TITLE"
        case .timeJump: return "JUMP"
        }
    }

    var nextOnReturn: ScreenplayElement {
        switch self {
        case .sceneHeading: return .action
        case .action: return .action
        case .character: return .dialogue
        case .parenthetical: return .dialogue
        case .dialogue: return .character
        case .transition: return .sceneHeading
        case .shot: return .action
        case .insert: return .action
        case .titleCard: return .action
        case .timeJump: return .sceneHeading
        }
    }

    func cycled(step: Int) -> ScreenplayElement {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return self }
        let nextIndex = (index + step + all.count) % all.count
        return all[nextIndex]
    }
}

enum CodeLanguage: String, CaseIterable {
    case swift
    case javascript
    case python
    case json

    var title: String {
        switch self {
        case .swift: return "Swift"
        case .javascript: return "JavaScript"
        case .python: return "Python"
        case .json: return "JSON"
        }
    }
}

enum CodeTheme: String, CaseIterable {
    case cobalt
    case frost
    case amber

    var title: String {
        switch self {
        case .cobalt: return "Cobalt"
        case .frost: return "Frost"
        case .amber: return "Amber"
        }
    }
}

@MainActor
final class DocumentSession: ObservableObject {
    @Published var title: String = "Untitled" {
        didSet {
            guard !isApplyingProgrammaticState else { return }
            if title != oldValue {
                hasUnsavedChanges = true
            }
        }
    }
    @Published var attributedText: NSAttributedString = NSAttributedString(string: "")
    @Published private(set) var currentURL: URL?
    @Published private(set) var hasUnsavedChanges: Bool = false
    @Published private(set) var hasRestorableLastDocument: Bool = false
    @Published private(set) var wordCount: Int = 0
    @Published private(set) var charCount: Int = 0
    @Published private(set) var screenplayPageCount: Int = 1
    @Published private(set) var screenplaySceneCount: Int = 0
    @Published private(set) var recentDocuments: [RecentDoc] = []
    @Published var authoringMode: AuthoringMode = .prose {
        didSet {
            updateMetrics()
        }
    }
    @Published var codeLanguage: CodeLanguage = .swift
    @Published var codeTheme: CodeTheme = .cobalt
    @Published var codeUseTabs: Bool = false
    @Published var codeTabWidth: Int = 4
    @Published var codeLineWrap: Bool = false
    @Published var screenplayElement: ScreenplayElement = .action

    let formattingBridge = FormattingBridge()
    let companionLexicon = MongrelDictionaryCompanionLexicon()


    var canSaveDocument: Bool {
        hasUnsavedChanges
    }

    var canCloseDocument: Bool {
        currentURL != nil || hasUnsavedChanges || attributedText.length > 0 || title != "Untitled"
    }

    var companionSpellcheckSummary: String {
        companionLexicon.status.summary
    }

    var companionSpellcheckDetail: String {
        if companionLexicon.status.isAvailable {
            return "\(companionLexicon.status.headwordCount) headwords"
        }
        return "System spellcheck only"
    }

    private var currentType: UTType = .plainText
    private var isApplyingProgrammaticState = false
    private let persistenceStore = WordProcessorPersistenceStore()
    private let auditLogger = WordProcessorAuditLogger()
    private let recentDocsKey = "wordprocessor.recentDocs"

    init() {
        hasRestorableLastDocument = persistenceStore.hasLastDocumentBookmark
        auditLogger.info("session_initialized", metadata: ["hasRestorableLastDocument": hasRestorableLastDocument])
        auditLogger.info(
            "companion_lexicon_initialized",
            metadata: [
                "available": companionLexicon.status.isAvailable,
                "headwords": companionLexicon.status.headwordCount,
                "source": companionLexicon.status.sourceDescription
            ]
        )
        loadRecentDocuments()
    }

    func newDocument() {
        guard confirmCanAbandonChanges() else { return }
        applyProgrammaticState {
            title = "Untitled"
            attributedText = NSAttributedString(string: "")
            currentURL = nil
            currentType = .plainText
            hasUnsavedChanges = false
        }
        auditLogger.info("new_document")
    }

    func closeDocument() {
        guard canCloseDocument else { return }
        guard confirmCanAbandonChanges() else { return }
        applyProgrammaticState {
            title = "Untitled"
            attributedText = NSAttributedString(string: "")
            currentURL = nil
            currentType = .plainText
            hasUnsavedChanges = false
        }
        auditLogger.info("close_document")
    }

    func markDirty() {
        hasUnsavedChanges = true
        updateMetrics()
    }

    func updateRenderedScreenplayPageCount(_ count: Int) {
        screenplayPageCount = max(1, count)
    }

    func openDocument() {
        guard confirmCanAbandonChanges() else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .rtf]

        guard panel.runModal() == .OK, let url = panel.url else {
            auditLogger.info("open_document_cancelled")
            return
        }

        auditLogger.info("open_document_selected", metadata: ["file": url.lastPathComponent])
        loadDocument(from: url)
    }

    func reopenLastDocument() {
        guard confirmCanAbandonChanges() else { return }
        guard let bookmarkData = persistenceStore.lastDocumentBookmarkData() else {
            presentError("No Previous Document", details: "There is no previously opened file to restore.")
            hasRestorableLastDocument = false
            auditLogger.warning("reopen_last_unavailable")
            return
        }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale,
               let refreshed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                persistenceStore.setLastDocumentBookmarkData(refreshed)
            }

            auditLogger.info("reopen_last_resolved", metadata: ["file": url.lastPathComponent, "isStale": isStale])
            loadDocument(from: url)
        } catch {
            presentError("Could Not Reopen Last Document", details: "The saved file reference is no longer valid.")
            persistenceStore.setLastDocumentBookmarkData(nil)
            hasRestorableLastDocument = false
            auditLogger.error("reopen_last_failed", error: error)
        }
    }

    private func loadDocument(from url: URL) {
        do {
            let loaded = try loadAttributedString(from: url)
            applyProgrammaticState {
                attributedText = loaded.text
                title = url.deletingPathExtension().lastPathComponent
                currentURL = url
                currentType = loaded.type
                hasUnsavedChanges = false
            }
            updateMetrics()
            trackRecent(url)

            if let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                persistenceStore.setLastDocumentBookmarkData(bookmarkData)
            }

            hasRestorableLastDocument = persistenceStore.hasLastDocumentBookmark
            auditLogger.info("load_document_success", metadata: ["file": url.lastPathComponent, "type": loaded.type.identifier])
        } catch {
            presentError("Could not open file", details: error.localizedDescription)
            auditLogger.error("load_document_failed", error: error, metadata: ["file": url.lastPathComponent])
        }
    }

    func saveDocument() {
        guard canSaveDocument else { return }
        if let currentURL {
            writeDocument(to: currentURL, type: currentType)
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .rtf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename(for: currentType)

        guard panel.runModal() == .OK, let url = panel.url else {
            auditLogger.info("save_document_as_cancelled")
            return
        }

        let ext = url.pathExtension.lowercased()
        let type: UTType
        if ext == "rtf" {
            type = .rtf
        } else if ext.isEmpty {
            // User removed the extension — honour whatever format is currently active.
            type = currentType
        } else {
            type = .plainText
        }
        writeDocument(to: url, type: type)
    }

    func exportAsPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename(for: .pdf)

        guard panel.runModal() == .OK, let url = panel.url else {
            auditLogger.info("export_document_cancelled", metadata: ["type": "pdf"])
            return
        }

        guard let data = makePDFData() else {
            presentError("Could not export PDF", details: "The document could not be rendered.")
            auditLogger.error(
                "export_document_failed",
                error: CocoaError(.fileWriteUnknown),
                metadata: ["type": "pdf", "file": url.lastPathComponent, "reason": "render_failed"]
            )
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            auditLogger.info("export_document", metadata: ["type": "pdf", "file": url.lastPathComponent])
        } catch {
            presentError("Could not export PDF", details: error.localizedDescription)
            auditLogger.error("export_document_failed", error: error, metadata: ["type": "pdf", "file": url.lastPathComponent])
        }
    }

    func exportAsPlainText() {
        export(type: .plainText)
    }

    func exportAsRTF() {
        export(type: .rtf)
    }

    private func export(type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename(for: type)

        guard panel.runModal() == .OK, let url = panel.url else {
            auditLogger.info("export_document_cancelled", metadata: ["type": type.identifier])
            return
        }
        if writeDocument(to: url, type: type, shouldTrackAsCurrent: false) {
            auditLogger.info("export_document", metadata: ["type": type.identifier, "file": url.lastPathComponent])
        }
    }

    private func suggestedFilename(for type: UTType) -> String {
        let safeTitle = sanitizedFilenameStem(from: title)
        let ext = type.preferredFilenameExtension ?? "txt"
        return "\(safeTitle).\(ext)"
    }

    private func sanitizedFilenameStem(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }

        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        let cleaned = trimmed.unicodeScalars
            .filter { allowed.contains($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")

        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    private func loadAttributedString(from url: URL) throws -> (text: NSAttributedString, type: UTType) {
        if url.pathExtension.lowercased() == "rtf" {
            let text = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return (text, .rtf)
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        return (NSAttributedString(string: text), .plainText)
    }

    @discardableResult
    private func writeDocument(to url: URL, type: UTType, shouldTrackAsCurrent: Bool = true) -> Bool {
        do {
            if type == .rtf {
                let range = NSRange(location: 0, length: attributedText.length)
                let data = try attributedText.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                try data.write(to: url, options: .atomic)
            } else {
                let text = attributedText.string
                try text.write(to: url, atomically: true, encoding: .utf8)
            }

            if shouldTrackAsCurrent {
                applyProgrammaticState {
                    currentURL = url
                    currentType = type
                    title = url.deletingPathExtension().lastPathComponent
                    hasUnsavedChanges = false
                }
                if let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    persistenceStore.setLastDocumentBookmarkData(bookmarkData)
                }
                hasRestorableLastDocument = persistenceStore.hasLastDocumentBookmark
                trackRecent(url)
            }

            auditLogger.info("save_document_success", metadata: ["type": type.identifier, "file": url.lastPathComponent, "trackCurrent": shouldTrackAsCurrent])
            return true
        } catch {
            presentError("Could not save file", details: error.localizedDescription)
            auditLogger.error("save_document_failed", error: error, metadata: ["type": type.identifier, "file": url.lastPathComponent])
            return false
        }
    }

    private func makePDFData() -> Data? {
        let contentSize = ScreenplayPageLayout.pageSize
        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let isScreenplay = authoringMode == .screenplay
        let contentWidth = isScreenplay
            ? ScreenplayPageLayout.contentWidth
            : contentSize.width - 72
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        if isScreenplay {
            textView.minSize = contentSize
            textView.maxSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.textContainerInset = NSSize(
                width: ScreenplayPageLayout.horizontalInset,
                height: ScreenplayPageLayout.verticalInset
            )
        } else {
            textView.textContainerInset = NSSize(width: 36, height: 36)
        }

        return textView.dataWithPDF(inside: textView.bounds)
    }

    private func confirmCanAbandonChanges() -> Bool {
        guard hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Do you want to save before continuing?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDocument()
            return !hasUnsavedChanges
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func applyProgrammaticState(_ updates: () -> Void) {
        isApplyingProgrammaticState = true
        updates()
        isApplyingProgrammaticState = false
    }

    private func presentError(_ message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }
}

// MARK: – Recent documents + metrics

extension DocumentSession {

    private func updateMetrics() {
        let text = attributedText.string
        let words = text.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
        wordCount = words.count
        charCount = text.filter { !$0.isWhitespace && !$0.isNewline }.count
        screenplayPageCount = estimateScreenplayPageCount()
        screenplaySceneCount = estimateScreenplaySceneCount()
    }

    private func estimateScreenplayPageCount() -> Int {
        guard authoringMode == .screenplay || containsScreenplayAttributes else { return 1 }

        let text = attributedText.string as NSString
        guard text.length > 0 else { return 1 }

        var totalEstimatedLines: Double = 0
        var index = 0

        while index < text.length {
            let paragraphRange = text.paragraphRange(for: NSRange(location: index, length: 0))
            let paragraphText = text.substring(with: paragraphRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let element = screenplayElement(at: paragraphRange.location)
            let charsPerLine = estimatedCharactersPerLine(for: element)
            let paragraphLines = max(1.0, ceil(Double(max(paragraphText.count, 1)) / charsPerLine))
            let spacerLines = estimatedSpacerLines(after: element)
            totalEstimatedLines += paragraphLines + spacerLines
            index = NSMaxRange(paragraphRange)
        }

        return max(1, Int(ceil(totalEstimatedLines / ScreenplayPageLayout.estimatedLinesPerPage)))
    }

    private func estimateScreenplaySceneCount() -> Int {
        let text = attributedText.string as NSString
        guard text.length > 0 else { return 0 }

        var count = 0
        var index = 0
        while index < text.length {
            let paragraphRange = text.paragraphRange(for: NSRange(location: index, length: 0))
            let paragraph = text.substring(with: paragraphRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty && paragraphCountsAsScene(at: paragraphRange.location, text: paragraph) {
                count += 1
            }
            index = NSMaxRange(paragraphRange)
        }
        return count
    }

    private var containsScreenplayAttributes: Bool {
        var found = false
        attributedText.enumerateAttribute(.screenplayElement, in: NSRange(location: 0, length: attributedText.length)) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private func screenplayElement(at location: Int) -> ScreenplayElement {
        guard attributedText.length > 0, location < attributedText.length,
              let tagged = attributedText.attribute(.screenplayElement, at: location, effectiveRange: nil) as? String,
              let element = ScreenplayElement(rawValue: tagged) else {
            return .action
        }
        return element
    }

    private func estimatedCharactersPerLine(for element: ScreenplayElement) -> Double {
        switch element {
        case .sceneHeading: return 48
        case .action: return 60
        case .character: return 22
        case .parenthetical: return 32
        case .dialogue: return 36
        case .transition: return 18
        case .shot: return 40
        case .insert: return 34
        case .titleCard: return 30
        case .timeJump: return 26
        }
    }

    private func estimatedSpacerLines(after element: ScreenplayElement) -> Double {
        switch element {
        case .sceneHeading, .transition: return 0.75
        case .character, .parenthetical: return 0.2
        case .action, .dialogue: return 0.4
        case .shot, .insert, .titleCard, .timeJump: return 0.55
        }
    }

    private func paragraphCountsAsScene(at location: Int, text: String) -> Bool {
        if screenplayElement(at: location) == .sceneHeading {
            return true
        }

        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalized.isEmpty else { return false }

        let sceneHeadingPrefixes = [
            "INT.", "EXT.", "INT/EXT.", "INT./EXT.", "EXT./INT.", "I/E.", "EST."
        ]
        return sceneHeadingPrefixes.contains { normalized.hasPrefix($0) }
    }

    private func loadRecentDocuments() {
        guard let data = UserDefaults.standard.data(forKey: recentDocsKey),
              let docs = try? JSONDecoder().decode([RecentDoc].self, from: data) else { return }
        recentDocuments = docs
    }

    private func trackRecent(_ url: URL) {
        let doc = RecentDoc(title: url.deletingPathExtension().lastPathComponent, path: url.path, openedAt: Date())
        var updated = recentDocuments.filter { $0.path != url.path }
        updated.insert(doc, at: 0)
        recentDocuments = Array(updated.prefix(6))
        persistRecentDocuments()
    }

    func openRecentDocument(_ doc: RecentDoc) {
        guard confirmCanAbandonChanges() else { return }
        guard FileManager.default.fileExists(atPath: doc.path) else {
            recentDocuments.removeAll { $0.id == doc.id }
            persistRecentDocuments()
            presentError("File Not Found", details: "'\(doc.title)' could not be found at its saved location.")
            return
        }
        loadDocument(from: URL(fileURLWithPath: doc.path))
    }

    private func persistRecentDocuments() {
        guard let data = try? JSONEncoder().encode(recentDocuments) else { return }
        UserDefaults.standard.set(data, forKey: recentDocsKey)
    }
}

final class WordProcessorPersistenceStore {
    private let lastBookmarkKey = "wordprocessor.lastDocumentBookmark"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasLastDocumentBookmark: Bool {
        defaults.data(forKey: lastBookmarkKey) != nil
    }

    func lastDocumentBookmarkData() -> Data? {
        defaults.data(forKey: lastBookmarkKey)
    }

    func setLastDocumentBookmarkData(_ data: Data?) {
        if let data {
            defaults.set(data, forKey: lastBookmarkKey)
        } else {
            defaults.removeObject(forKey: lastBookmarkKey)
        }
    }
}

final class WordProcessorAuditLogger {
    private let logger = Logger(subsystem: "com.mongrel.wordprocessor", category: "workflow")

    func info(_ event: String, metadata: [String: Any] = [:]) {
        logger.log("\(self.format(event: event, metadata: metadata), privacy: .public)")
    }

    func warning(_ event: String, metadata: [String: Any] = [:]) {
        logger.warning("\(self.format(event: event, metadata: metadata), privacy: .public)")
    }

    func error(_ event: String, error: Error, metadata: [String: Any] = [:]) {
        var merged = metadata
        merged["error"] = error.localizedDescription
        logger.error("\(self.format(event: event, metadata: merged), privacy: .public)")
    }

    private func format(event: String, metadata: [String: Any]) -> String {
        guard !metadata.isEmpty else { return event }
        let rendered = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        return "\(event) \(rendered)"
    }
}
