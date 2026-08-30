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

struct ScreenplayScene: Identifiable, Equatable {
    let number: Int
    let heading: String
    let location: Int

    var id: Int { location }
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
import PDFKit
import UniformTypeIdentifiers
import OSLog

struct ScreenplayPageLayout {
    static let pageSize = NSSize(width: 612, height: 792)
    static let contentWidth: CGFloat = 432
    static let horizontalInset: CGFloat = 90
    static let verticalInset: CGFloat = 72
    static let contentHeight = pageSize.height - (verticalInset * 2)
    static let pageBreakHeight = verticalInset * 2
    static let estimatedLinesPerPage: Double = 55

    static func exclusionPaths(maximumPageCount: Int = 300) -> [NSBezierPath] {
        guard maximumPageCount > 1 else { return [] }
        return (1..<maximumPageCount).map { pageIndex in
            let breakOrigin = (CGFloat(pageIndex) * pageSize.height) - pageBreakHeight
            return NSBezierPath(rect: NSRect(
                x: -1,
                y: breakOrigin,
                width: contentWidth + 2,
                height: pageBreakHeight
            ))
        }
    }

    static func pageCount(forLaidOutContentHeight height: CGFloat) -> Int {
        max(1, Int(ceil((max(height, 0) + pageBreakHeight) / pageSize.height)))
    }
}

extension UTType {
    static let mongrelScreenplay = UTType(
        exportedAs: "com.mongrel.screenplay",
        conformingTo: .data
    )

    static let wordDocument = UTType(filenameExtension: "docx")!
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

enum ScreenplayViewStyle: String, CaseIterable, Identifiable {
    case page
    case fitWidth
    case clean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .page: return "Page"
        case .fitWidth: return "Fit Width"
        case .clean: return "Clean"
        }
    }

    var systemImage: String {
        switch self {
        case .page: return "doc"
        case .fitWidth: return "arrow.left.and.right"
        case .clean: return "rectangle.inset.filled"
        }
    }

    var usesAutomaticZoom: Bool {
        self != .page
    }

    var showsPaperChrome: Bool {
        self != .clean
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
    static let editableDocumentTypes: [UTType] = [.mongrelScreenplay, .rtf, .wordDocument, .plainText]
    static let openableDocumentTypes = editableDocumentTypes

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
    @Published private(set) var screenplayScenes: [ScreenplayScene] = []
    @Published private(set) var documentInsights: DocumentInsightSnapshot = .empty
    @Published private(set) var languageToolIssues: [LanguageToolIssue] = []
    @Published private(set) var languageToolState: LanguageToolCheckState = .idle
    @Published private(set) var recentDocuments: [RecentDoc] = []
    @Published var authoringMode: AuthoringMode = .prose {
        didSet {
            guard authoringMode != oldValue else { return }
            if currentURL == nil {
                currentType = defaultDocumentType(for: authoringMode)
            }
            if !isApplyingProgrammaticState {
                hasUnsavedChanges = true
            }
            updateMetrics()
        }
    }
    @Published var codeLanguage: CodeLanguage = .swift
    @Published var codeTheme: CodeTheme = .cobalt
    @Published var codeUseTabs: Bool = false
    @Published var codeTabWidth: Int = 4
    @Published var codeLineWrap: Bool = false
    @Published var screenplayElement: ScreenplayElement = .action
    @Published private(set) var editorZoom: CGFloat = 1
    @Published var screenplayViewStyle: ScreenplayViewStyle = .fitWidth {
        didSet {
            guard screenplayViewStyle != oldValue else { return }
            defaults.set(screenplayViewStyle.rawValue, forKey: screenplayViewStyleKey)
        }
    }
    @Published var typewriterMode: Bool = false {
        didSet {
            guard typewriterMode != oldValue else { return }
            defaults.set(typewriterMode, forKey: typewriterModeKey)
        }
    }

    let formattingBridge = FormattingBridge()
    let companionLexicon: MongrelDictionaryCompanionLexicon


    /// A new, empty document is still saveable: Save should present Save As.
    var canSaveDocument: Bool { true }

    var canCloseDocument: Bool {
        currentURL != nil || hasUnsavedChanges || attributedText.length > 0 || title != "Untitled"
    }

    var documentStatusLabel: String {
        if hasUnsavedChanges { return "Unsaved" }
        return currentURL == nil ? "New" : "Saved"
    }

    var editorZoomPercentage: Int {
        Int((editorZoom * 100).rounded())
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

    private var currentType: UTType = .rtf
    private var isApplyingProgrammaticState = false
    private let persistenceStore: WordProcessorPersistenceStore
    private let auditLogger = WordProcessorAuditLogger()
    private let defaults: UserDefaults
    private let recentDocsKey = "wordprocessor.recentDocs"
    private let editorZoomKey = "wordprocessor.editorZoom"
    private let screenplayViewStyleKey = "wordprocessor.screenplayViewStyle"
    private let typewriterModeKey = "wordprocessor.typewriterMode"

    init(
        defaults: UserDefaults = .standard,
        companionLexicon: MongrelDictionaryCompanionLexicon = MongrelDictionaryCompanionLexicon()
    ) {
        self.defaults = defaults
        self.persistenceStore = WordProcessorPersistenceStore(defaults: defaults)
        self.companionLexicon = companionLexicon
        let storedZoom = defaults.double(forKey: editorZoomKey)
        self.editorZoom = storedZoom == 0 ? 1 : min(max(CGFloat(storedZoom), 0.6), 2)
        self.screenplayViewStyle = ScreenplayViewStyle(
            rawValue: defaults.string(forKey: screenplayViewStyleKey) ?? ""
        ) ?? .fitWidth
        self.typewriterMode = defaults.bool(forKey: typewriterModeKey)
        ManagedFontLibrary.registerInstalledFonts()
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
            authoringMode = .prose
            currentType = .rtf
            hasUnsavedChanges = false
        }
        updateMetrics()
        auditLogger.info("new_document")
    }

    func newScreenplay() {
        guard confirmCanAbandonChanges() else { return }
        applyProgrammaticState {
            title = "Untitled Screenplay"
            attributedText = NSAttributedString(string: "")
            currentURL = nil
            currentType = .mongrelScreenplay
            authoringMode = .screenplay
            screenplayElement = .sceneHeading
            hasUnsavedChanges = false
        }
        updateMetrics()
        auditLogger.info("new_screenplay")
    }

    func closeDocument() {
        guard canCloseDocument else { return }
        guard confirmCanAbandonChanges() else { return }
        applyProgrammaticState {
            title = "Untitled"
            attributedText = NSAttributedString(string: "")
            currentURL = nil
            currentType = defaultDocumentType(for: authoringMode)
            hasUnsavedChanges = false
        }
        updateMetrics()
        auditLogger.info("close_document")
    }

    func markDirty() {
        hasUnsavedChanges = true
        updateMetrics()
    }

    func updateRenderedScreenplayPageCount(_ count: Int) {
        let normalizedCount = max(1, count)
        guard screenplayPageCount != normalizedCount else { return }
        screenplayPageCount = normalizedCount
    }

    func adjustEditorZoom(by delta: CGFloat) {
        if authoringMode == .screenplay {
            screenplayViewStyle = .page
        }
        setEditorZoom(editorZoom + delta)
    }

    func resetEditorZoom() {
        if authoringMode == .screenplay {
            screenplayViewStyle = .page
        }
        setEditorZoom(1)
    }

    func setEditorZoom(_ zoom: CGFloat) {
        let clamped = min(max(zoom, 0.6), 2)
        guard abs(clamped - editorZoom) > 0.001 else { return }
        editorZoom = clamped
        defaults.set(Double(clamped), forKey: editorZoomKey)
    }

    func openDocument() {
        guard confirmCanAbandonChanges() else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.openableDocumentTypes

        guard panel.runModal() == .OK, let url = panel.url else {
            auditLogger.info("open_document_cancelled")
            return
        }

        auditLogger.info("open_document_selected", metadata: ["file": url.lastPathComponent])
        openDocument(at: url)
    }

    func openExternalDocument(at url: URL) {
        guard confirmCanAbandonChanges() else { return }
        openDocument(at: url)
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
            openDocument(at: url)
        } catch {
            presentError("Could Not Reopen Last Document", details: "The saved file reference is no longer valid.")
            persistenceStore.setLastDocumentBookmarkData(nil)
            hasRestorableLastDocument = false
            auditLogger.error("reopen_last_failed", error: error)
        }
    }

    /// Opens a concrete URL without presenting a panel. This is also used for
    /// Finder-open events and keeps the actual file lifecycle testable.
    @discardableResult
    func openDocument(at url: URL) -> Bool {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let loaded = try loadAttributedString(from: url)
            applyProgrammaticState {
                attributedText = loaded.text
                title = url.deletingPathExtension().lastPathComponent
                currentURL = url
                currentType = loaded.type
                authoringMode = loaded.mode
                hasUnsavedChanges = false
            }
            updateMetrics()
            trackRecent(url)

            if let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                persistenceStore.setLastDocumentBookmarkData(bookmarkData)
            }

            hasRestorableLastDocument = persistenceStore.hasLastDocumentBookmark
            auditLogger.info("load_document_success", metadata: ["file": url.lastPathComponent, "type": loaded.type.identifier])
            return true
        } catch {
            presentError("Could not open file", details: error.localizedDescription)
            auditLogger.error("load_document_failed", error: error, metadata: ["file": url.lastPathComponent])
            return false
        }
    }

    func saveDocument() {
        if let currentURL {
            writeDocument(to: currentURL, type: currentType)
        } else {
            saveDocumentAs()
        }
    }

    func saveDocumentAs(preferredType: UTType? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = preferredType.map { [$0] } ?? Self.editableDocumentTypes
        panel.canCreateDirectories = true
        let initialType = preferredType ?? currentType
        panel.nameFieldStringValue = suggestedFilename(for: initialType)

        guard panel.runModal() == .OK, let url = panel.url else {
            auditLogger.info("save_document_as_cancelled")
            return
        }

        let type = url.pathExtension.isEmpty ? initialType : documentType(for: url)
        saveDocument(to: url, type: type)
    }

    func saveDocumentCopyAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = Self.editableDocumentTypes
        panel.canCreateDirectories = true
        let baseName = sanitizedFilenameStem(from: title)
        let ext = currentType == .mongrelScreenplay
            ? "mgscreenplay"
            : (currentType.preferredFilenameExtension ?? "txt")
        panel.nameFieldStringValue = "\(baseName)-copy.\(ext)"

        guard panel.runModal() == .OK, let url = panel.url else {
            auditLogger.info("save_document_copy_cancelled")
            return
        }

        let type = documentType(for: url)
        if writeDocument(to: url, type: type, shouldTrackAsCurrent: false) {
            auditLogger.info("save_document_copy_success", metadata: ["file": url.lastPathComponent])
        }
    }

    /// Saves to a concrete URL without presenting a panel.
    @discardableResult
    func saveDocument(to url: URL, type: UTType? = nil) -> Bool {
        let resolvedType = type ?? documentType(for: url)
        return writeDocument(to: url, type: resolvedType)
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

    func exportAsWordDocument() {
        export(type: .wordDocument)
    }

    func showFontPanel() {
        formattingBridge.showFontPanel()
    }

    func installFontFiles() {
        do {
            let count = try ManagedFontLibrary.installFontFiles()
            guard count > 0 else { return }
            formattingBridge.showFontPanel()
            auditLogger.info("font_install_success", metadata: ["count": count])
        } catch {
            presentError("Could not install font", details: error.localizedDescription)
            auditLogger.error("font_install_failed", error: error)
        }
    }

    func checkWithLocalLanguageTool() {
        let checkedText = attributedText.string
        guard !checkedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            languageToolIssues = []
            languageToolState = .complete(0)
            return
        }

        languageToolState = .checking
        Task { [weak self] in
            guard let self else { return }
            do {
                let issues = try await LocalLanguageToolClient.check(checkedText)
                guard attributedText.string == checkedText else {
                    languageToolIssues = []
                    languageToolState = .idle
                    auditLogger.info("language_tool_check_discarded_stale_result")
                    return
                }
                languageToolIssues = issues
                languageToolState = .complete(issues.count)
                auditLogger.info("language_tool_check_success", metadata: ["issues": issues.count])
            } catch {
                languageToolIssues = []
                languageToolState = .unavailable(error.localizedDescription)
                auditLogger.warning("language_tool_check_unavailable", metadata: ["error": error.localizedDescription])
            }
        }
    }

    func focusLanguageToolIssue(_ issue: LanguageToolIssue) {
        formattingBridge.focusRange(NSRange(location: issue.offset, length: issue.length))
    }

    func applyLanguageToolReplacement(_ replacement: String, for issue: LanguageToolIssue) {
        let range = NSRange(location: issue.offset, length: issue.length)
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= attributedText.length else { return }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        updated.replaceCharacters(in: range, with: replacement)
        attributedText = updated
        languageToolIssues = []
        languageToolState = .idle
        markDirty()
    }

    func printDocument() {
        guard let data = makePDFData(), let document = PDFDocument(data: data) else {
            presentError("Could not print document", details: "The document could not be rendered for printing.")
            return
        }

        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        guard let operation = document.printOperation(
            for: printInfo,
            scalingMode: .pageScaleToFit,
            autoRotate: true
        ) else {
            presentError("Could not print document", details: "macOS could not create a print operation.")
            return
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
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
        let ext = type == .mongrelScreenplay ? "mgscreenplay" : (type.preferredFilenameExtension ?? "txt")
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

    private func documentType(for url: URL) -> UTType {
        switch url.pathExtension.lowercased() {
        case "mgscreenplay": return .mongrelScreenplay
        case "rtf": return .rtf
        case "docx": return .wordDocument
        case "txt", "text": return .plainText
        default: return currentType
        }
    }

    private func defaultDocumentType(for mode: AuthoringMode) -> UTType {
        switch mode {
        case .screenplay: return .mongrelScreenplay
        case .code: return .plainText
        case .prose: return .rtf
        }
    }

    private func loadAttributedString(from url: URL) throws -> (text: NSAttributedString, type: UTType, mode: AuthoringMode) {
        if url.pathExtension.lowercased() == "mgscreenplay" {
            let archive = try JSONDecoder().decode(
                MongrelScreenplayArchive.self,
                from: Data(contentsOf: url)
            )
            return (try archive.makeAttributedString(), .mongrelScreenplay, .screenplay)
        }

        if url.pathExtension.lowercased() == "rtf" {
            let text = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return (text, .rtf, .prose)
        }

        if url.pathExtension.lowercased() == "docx" {
            let text = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil
            )
            return (text, .wordDocument, .prose)
        }

        let text = try String(contentsOf: url, encoding: .utf8)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.35
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        return (attributed, .plainText, .prose)
    }

    @discardableResult
    private func writeDocument(to url: URL, type: UTType, shouldTrackAsCurrent: Bool = true) -> Bool {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if type == .mongrelScreenplay {
                let data = try JSONEncoder().encode(MongrelScreenplayArchive(attributedText: attributedText))
                try data.write(to: url, options: .atomic)
            } else if type == .rtf || type == .wordDocument {
                let range = NSRange(location: 0, length: attributedText.length)
                let documentType: NSAttributedString.DocumentType = type == .wordDocument
                    ? .officeOpenXML
                    : .rtf
                let data = try attributedText.data(
                    from: range,
                    documentAttributes: [.documentType: documentType]
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

    func makePDFData() -> Data? {
        let margins = authoringMode == .screenplay
            ? NSSize(width: ScreenplayPageLayout.horizontalInset, height: ScreenplayPageLayout.verticalInset)
            : NSSize(width: 36, height: 36)
        return PaginatedDocumentPDFRenderer.render(
            attributedText,
            margins: margins,
            showsPageNumbers: authoringMode == .screenplay
        )
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
        screenplayScenes = collectScreenplayScenes()
        screenplaySceneCount = screenplayScenes.count
        documentInsights = DocumentInsightsAnalyzer.analyze(
            attributedText,
            scenes: screenplayScenes,
            mode: authoringMode
        )
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

    private func collectScreenplayScenes() -> [ScreenplayScene] {
        let text = attributedText.string as NSString
        guard text.length > 0 else { return [] }

        var scenes: [ScreenplayScene] = []
        var index = 0
        while index < text.length {
            let paragraphRange = text.paragraphRange(for: NSRange(location: index, length: 0))
            let paragraph = text.substring(with: paragraphRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty && paragraphCountsAsScene(at: paragraphRange.location, text: paragraph) {
                scenes.append(ScreenplayScene(
                    number: scenes.count + 1,
                    heading: paragraph,
                    location: paragraphRange.location
                ))
            }
            index = NSMaxRange(paragraphRange)
        }
        return scenes
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
        guard let data = defaults.data(forKey: recentDocsKey),
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
        openDocument(at: URL(fileURLWithPath: doc.path))
    }

    func clearRecentDocuments() {
        recentDocuments = []
        persistRecentDocuments()
        auditLogger.info("clear_recent_documents")
    }

    private func persistRecentDocuments() {
        guard let data = try? JSONEncoder().encode(recentDocuments) else { return }
        defaults.set(data, forKey: recentDocsKey)
    }
}

private struct MongrelScreenplayArchive: Codable {
    struct ElementRange: Codable {
        let location: Int
        let length: Int
        let element: String
    }

    let formatVersion: Int
    let richTextData: Data
    let elementRanges: [ElementRange]

    init(attributedText: NSAttributedString) throws {
        formatVersion = 1
        richTextData = try attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )

        var ranges: [ElementRange] = []
        attributedText.enumerateAttribute(
            .screenplayElement,
            in: NSRange(location: 0, length: attributedText.length)
        ) { value, range, _ in
            guard let element = value as? String,
                  ScreenplayElement(rawValue: element) != nil else { return }
            ranges.append(ElementRange(location: range.location, length: range.length, element: element))
        }
        elementRanges = ranges
    }

    func makeAttributedString() throws -> NSAttributedString {
        guard formatVersion == 1 else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let restored = try NSMutableAttributedString(
            data: richTextData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        for elementRange in elementRanges {
            guard ScreenplayElement(rawValue: elementRange.element) != nil,
                  elementRange.location >= 0,
                  elementRange.length >= 0,
                  elementRange.location + elementRange.length <= restored.length else { continue }
            restored.addAttribute(
                .screenplayElement,
                value: elementRange.element,
                range: NSRange(location: elementRange.location, length: elementRange.length)
            )
        }
        return restored
    }
}

@MainActor
private enum PaginatedDocumentPDFRenderer {
    static func render(
        _ attributedText: NSAttributedString,
        margins: NSSize,
        showsPageNumbers: Bool
    ) -> Data? {
        let pageSize = ScreenplayPageLayout.pageSize
        let contentSize = NSSize(
            width: pageSize.width - (margins.width * 2),
            height: pageSize.height - (margins.height * 2)
        )
        guard contentSize.width > 0, contentSize.height > 0 else { return nil }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var pages: [ScreenplayPDFPageView] = []
        var laidOutGlyphs = 0

        repeat {
            let container = NSTextContainer(containerSize: contentSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(for: container)
            pages.append(ScreenplayPDFPageView(
                frame: NSRect(origin: .zero, size: pageSize),
                layoutManager: layoutManager,
                textContainer: container,
                margins: margins,
                pageNumber: showsPageNumbers ? pages.count + 1 : nil
            ))

            let nextGlyphLocation = NSMaxRange(glyphRange)
            guard nextGlyphLocation > laidOutGlyphs else { break }
            laidOutGlyphs = nextGlyphLocation
        } while laidOutGlyphs < layoutManager.numberOfGlyphs

        let document = PDFDocument()
        for (index, pageView) in pages.enumerated() {
            let pageData = pageView.dataWithPDF(inside: pageView.bounds)
            guard let page = PDFDocument(data: pageData)?.page(at: 0) else { return nil }
            document.insert(page, at: index)
        }
        return document.dataRepresentation()
    }
}

@MainActor
private final class ScreenplayPDFPageView: NSView {
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let margins: NSSize
    private let pageNumber: Int?

    init(
        frame: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        margins: NSSize,
        pageNumber: Int?
    ) {
        self.layoutManager = layoutManager
        self.textContainer = textContainer
        self.margins = margins
        self.pageNumber = pageNumber
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let origin = NSPoint(x: margins.width, y: margins.height)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)

        guard let pageNumber else { return }
        let pageLabel = "\(pageNumber)."
        pageLabel.draw(
            at: NSPoint(x: bounds.maxX - margins.width + 12, y: 18),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.darkGray
            ]
        )
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
