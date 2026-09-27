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

    var productionNumber: String? = nil
    var displayNumber: String { productionNumber ?? String(number) }
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
    static let mongrelDocument = UTType(
        exportedAs: "com.mongrel.document",
        conformingTo: .data
    )

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
        case .code: return "Coding"
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
    case typescript
    case python
    case json
    case html
    case css
    case shell
    case markdown
    case yaml
    case sql

    var title: String {
        switch self {
        case .swift: return "Swift"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .python: return "Python"
        case .json: return "JSON"
        case .html: return "HTML"
        case .css: return "CSS"
        case .shell: return "Shell"
        case .markdown: return "Markdown"
        case .yaml: return "YAML"
        case .sql: return "SQL"
        }
    }

    var preferredFilenameExtension: String {
        switch self {
        case .swift: return "swift"
        case .javascript: return "js"
        case .typescript: return "ts"
        case .python: return "py"
        case .json: return "json"
        case .html: return "html"
        case .css: return "css"
        case .shell: return "sh"
        case .markdown: return "md"
        case .yaml: return "yaml"
        case .sql: return "sql"
        }
    }

    var filenameExtensions: Set<String> {
        switch self {
        case .swift: return ["swift"]
        case .javascript: return ["js", "jsx", "mjs", "cjs"]
        case .typescript: return ["ts", "tsx", "mts", "cts"]
        case .python: return ["py", "pyw"]
        case .json: return ["json", "jsonc"]
        case .html: return ["html", "htm"]
        case .css: return ["css", "scss", "sass", "less"]
        case .shell: return ["sh", "bash", "zsh", "fish"]
        case .markdown: return ["md", "markdown", "mdown"]
        case .yaml: return ["yaml", "yml"]
        case .sql: return ["sql"]
        }
    }

    var contentType: UTType {
        UTType(filenameExtension: preferredFilenameExtension, conformingTo: .sourceCode) ?? .sourceCode
    }

    var lineCommentPrefix: String? {
        switch self {
        case .swift, .javascript, .typescript: return "//"
        case .python, .shell, .yaml: return "#"
        case .sql: return "--"
        case .json, .html, .css, .markdown: return nil
        }
    }

    static func detected(from url: URL) -> CodeLanguage? {
        let ext = url.pathExtension.lowercased()
        return allCases.first { $0.filenameExtensions.contains(ext) }
    }

    static func detected(fromShebang text: String) -> CodeLanguage? {
        guard let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              firstLine.hasPrefix("#!") else { return nil }
        let value = firstLine.lowercased()
        if value.contains("python") { return .python }
        if value.contains("node") || value.contains("deno") { return .javascript }
        if value.contains("swift") { return .swift }
        if value.contains("bash") || value.contains("zsh") || value.contains("fish") || value.contains("/sh") {
            return .shell
        }
        return nil
    }
}

enum CodeTheme: String, CaseIterable {
    case studio
    case paper
    case midnight
    case cobalt
    case frost
    case amber

    var title: String {
        switch self {
        case .studio: return "Studio"
        case .paper: return "Paper"
        case .midnight: return "Midnight"
        case .cobalt: return "Cobalt"
        case .frost: return "Frost"
        case .amber: return "Amber Terminal"
        }
    }
}

enum CodeFont: String, CaseIterable {
    case systemMono
    case menlo
    case monaco

    var title: String {
        switch self {
        case .systemMono: return "SF Mono"
        case .menlo: return "Menlo"
        case .monaco: return "Monaco"
        }
    }
}

struct DocumentWorkspaceTab: Identifiable, Equatable {
    let id: UUID
    var title: String
    var mode: AuthoringMode
    var isDirty: Bool
    var url: URL?

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var systemImage: String {
        switch mode {
        case .prose: return "doc.text"
        case .screenplay: return "film"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct DocumentWorkspaceTabState {
    var title: String
    var attributedText: NSAttributedString
    var currentURL: URL?
    var currentType: UTType
    var authoringMode: AuthoringMode
    var codeLanguage: CodeLanguage
    var screenplayElement: ScreenplayElement
    var pageLayout: DocumentPageLayout
    var hasUnsavedChanges: Bool
    var editorLocation: EditorLocationSnapshot
    var diskVersion: DocumentDiskVersion? = nil
    var screenplaySettings: ScreenplayDocumentSettings = .init()
}

struct DocumentDiskVersion: Equatable {
    let modificationDate: Date?
    let fileSize: Int?
    let fileNumber: UInt64?
    let systemNumber: UInt64?

    static func capture(at url: URL, fileManager: FileManager = .default) -> DocumentDiskVersion? {
        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        return DocumentDiskVersion(
            modificationDate: attributes[.modificationDate] as? Date,
            fileSize: (attributes[.size] as? NSNumber)?.intValue,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
            systemNumber: (attributes[.systemNumber] as? NSNumber)?.uint64Value
        )
    }
}

@MainActor
final class DocumentSession: ObservableObject {
    static let editableDocumentTypes: [UTType] = [
        .mongrelDocument,
        .mongrelScreenplay,
        .sourceCode,
        .rtfd,
        .rtf,
        .wordDocument,
        .plainText
    ]
    static let openableDocumentTypes = editableDocumentTypes

    @Published var title: String = "Untitled" {
        didSet {
            guard !isApplyingProgrammaticState else { return }
            if title != oldValue {
                hasUnsavedChanges = true
                refreshActiveTabMetadata()
                scheduleWorkspaceRecovery()
            }
        }
    }
    @Published var attributedText: NSAttributedString = NSAttributedString(string: "")
    @Published private(set) var currentURL: URL? {
        didSet { refreshActiveTabMetadata() }
    }
    @Published private(set) var hasUnsavedChanges: Bool = false {
        didSet {
            refreshActiveTabMetadata()
            if hasUnsavedChanges != oldValue, !isApplyingProgrammaticState {
                scheduleWorkspaceRecovery()
            }
        }
    }
    @Published private(set) var workspaceTabs: [DocumentWorkspaceTab] = []
    @Published private(set) var activeTabID: UUID?
    @Published private(set) var canReopenClosedTab: Bool = false
    @Published var autosaveOnTabSwitch: Bool = false {
        didSet {
            guard autosaveOnTabSwitch != oldValue else { return }
            defaults.set(autosaveOnTabSwitch, forKey: autosaveOnTabSwitchKey)
        }
    }
    @Published private(set) var hasRestorableLastDocument: Bool = false
    @Published private(set) var wordCount: Int = 0
    @Published private(set) var charCount: Int = 0
    @Published private(set) var screenplayPageCount: Int = 1
    @Published private(set) var screenplaySceneCount: Int = 0
    @Published private(set) var screenplayScenes: [ScreenplayScene] = []
    @Published private(set) var activeScreenplaySceneID: Int?
    private var screenplayCursorLocation = 0
    @Published private(set) var screenplayCatalog = ScreenplayCatalog()
    @Published var screenplaySettings = ScreenplayDocumentSettings() {
        didSet {
            guard screenplaySettings != oldValue, !isApplyingProgrammaticState else { return }
            if screenplaySettings.draft != oldValue.draft {
                screenplaySettings.showsSceneNumbers = screenplaySettings.draft == .production
            }
            hasUnsavedChanges = true
            updateMetrics()
            scheduleWorkspaceRecovery()
        }
    }
    @Published private(set) var documentInsights: DocumentInsightSnapshot = .empty
    @Published private(set) var languageToolIssues: [LanguageToolIssue] = []
    @Published private(set) var languageToolState: LanguageToolCheckState = .idle
    @Published private(set) var recentDocuments: [RecentDoc] = []
    @Published var pageLayout: DocumentPageLayout = .empty {
        didSet {
            guard pageLayout != oldValue, !isApplyingProgrammaticState else { return }
            hasUnsavedChanges = true
            scheduleWorkspaceRecovery()
        }
    }
    @Published var authoringMode: AuthoringMode = .prose {
        didSet {
            guard authoringMode != oldValue else { return }
            if currentURL == nil {
                currentType = defaultDocumentType(for: authoringMode)
            }
            if !isApplyingProgrammaticState {
                hasUnsavedChanges = true
                scheduleWorkspaceRecovery()
            }
            if !isSwitchingTabs { updateMetrics() }
            refreshActiveTabMetadata()
        }
    }
    @Published var codeLanguage: CodeLanguage = .swift {
        didSet {
            guard codeLanguage != oldValue else { return }
            defaults.set(codeLanguage.rawValue, forKey: codeLanguageKey)
            if currentURL == nil, authoringMode == .code {
                currentType = codeLanguage.contentType
            }
            if !isApplyingProgrammaticState {
                scheduleWorkspaceRecovery()
            }
        }
    }
    @Published var codeTheme: CodeTheme = .studio {
        didSet {
            guard codeTheme != oldValue else { return }
            defaults.set(codeTheme.rawValue, forKey: codeThemeKey)
        }
    }
    @Published var codeFont: CodeFont = .systemMono {
        didSet {
            guard codeFont != oldValue else { return }
            defaults.set(codeFont.rawValue, forKey: codeFontKey)
        }
    }
    @Published var codeFontSize: CGFloat = 14 {
        didSet {
            guard codeFontSize != oldValue else { return }
            let normalized = min(max(codeFontSize.rounded(), 11), 24)
            if codeFontSize != normalized {
                codeFontSize = normalized
                return
            }
            defaults.set(Double(codeFontSize), forKey: codeFontSizeKey)
        }
    }
    @Published var codeUseTabs: Bool = false {
        didSet {
            guard codeUseTabs != oldValue else { return }
            defaults.set(codeUseTabs, forKey: codeUseTabsKey)
        }
    }
    @Published var codeTabWidth: Int = 4 {
        didSet {
            guard codeTabWidth != oldValue else { return }
            let normalized = [2, 4, 8].contains(codeTabWidth) ? codeTabWidth : 4
            if codeTabWidth != normalized {
                codeTabWidth = normalized
                return
            }
            defaults.set(codeTabWidth, forKey: codeTabWidthKey)
        }
    }
    @Published var codeLineWrap: Bool = false {
        didSet {
            guard codeLineWrap != oldValue else { return }
            defaults.set(codeLineWrap, forKey: codeLineWrapKey)
        }
    }
    @Published private(set) var codeCursorLine: Int = 1
    @Published private(set) var codeCursorColumn: Int = 1
    @Published private(set) var codeSelectionLength: Int = 0
    @Published var screenplayElement: ScreenplayElement = .action {
        didSet {
            guard screenplayElement != oldValue, !isApplyingProgrammaticState else { return }
            scheduleWorkspaceRecovery()
        }
    }
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
        workspaceTabs.count > 1
            || currentURL != nil
            || hasUnsavedChanges
            || attributedText.length > 0
            || title != "Untitled"
    }

    var documentStatusLabel: String {
        if hasUnsavedChanges { return "Unsaved" }
        return currentURL == nil ? "New" : "Saved"
    }

    var editorZoomPercentage: Int {
        Int((editorZoom * 100).rounded())
    }

    private var cachedLineIndexText: NSAttributedString?
    private var cachedLineIndex = TextLineIndex("")
    private var codeLineIndex: TextLineIndex {
        if cachedLineIndexText !== attributedText {
            cachedLineIndex = TextLineIndex(attributedText.string)
            cachedLineIndexText = attributedText
        }
        return cachedLineIndex
    }

    var codeLineCount: Int { codeLineIndex.count }

    var codeIndentationSummary: String {
        codeUseTabs ? "Tabs · \(codeTabWidth) columns" : "Spaces · \(codeTabWidth)"
    }

    var codeLineEndingSummary: String { codeLineIndex.lineEnding }

    var codeStorageSummary: String {
        if currentType == .mongrelDocument { return "MONGREL" }
        if currentType == .rtf { return "RTF" }
        if currentType == .rtfd { return "RTFD" }
        if currentType == .wordDocument { return "DOCX" }
        return "UTF-8 SAVE"
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

    private var currentType: UTType = .mongrelDocument
    private var currentDiskVersion: DocumentDiskVersion?
    private var isApplyingProgrammaticState = false
    private var isSwitchingTabs = false
    private var workspaceTabStates: [UUID: DocumentWorkspaceTabState] = [:]
    private var closedWorkspaceTabs: [(DocumentWorkspaceTab, DocumentWorkspaceTabState)] = []
    private let persistenceStore: WordProcessorPersistenceStore
    private let workspaceRecoveryStore: WordProcessorWorkspaceRecoveryStore
    private let auditLogger = WordProcessorAuditLogger()
    private let defaults: UserDefaults
    private let errorPresenter: (String, String) -> Void
    private var workspaceRecoveryWorkItem: DispatchWorkItem?
    private var metricsWorkItem: DispatchWorkItem?
    private var lastMetricsText: NSAttributedString?
    private var lastMetricsMode: AuthoringMode?
    private var lastMetricsDraft: ScreenplayDraftStage?
    private let recoveryWriter = CoalescingWorkspaceRecoveryWriter()
    private var recoveryArchiveCache: [UUID: MongrelDocumentArchive] = [:]
    private let recentDocsKey = "wordprocessor.recentDocs"
    private let editorZoomKey = "wordprocessor.editorZoom"
    private let screenplayViewStyleKey = "wordprocessor.screenplayViewStyle"
    private let typewriterModeKey = "wordprocessor.typewriterMode"
    private let codeLanguageKey = "wordprocessor.codeLanguage"
    private let codeThemeKey = "wordprocessor.codeTheme"
    private let codeFontKey = "wordprocessor.codeFont"
    private let codeFontSizeKey = "wordprocessor.codeFontSize"
    private let codeUseTabsKey = "wordprocessor.codeUseTabs"
    private let codeTabWidthKey = "wordprocessor.codeTabWidth"
    private let codeLineWrapKey = "wordprocessor.codeLineWrap"
    private let autosaveOnTabSwitchKey = "wordprocessor.autosaveOnTabSwitch"
    private var languageToolRequestID: UUID?

    init(
        defaults: UserDefaults = .standard,
        companionLexicon: MongrelDictionaryCompanionLexicon = MongrelDictionaryCompanionLexicon(),
        workspaceRecoveryDirectory: URL? = nil,
        errorPresenter: ((String, String) -> Void)? = nil
    ) {
        self.defaults = defaults
        self.persistenceStore = WordProcessorPersistenceStore(defaults: defaults)
        self.workspaceRecoveryStore = WordProcessorWorkspaceRecoveryStore(directory: workspaceRecoveryDirectory)
        self.companionLexicon = companionLexicon
        self.errorPresenter = errorPresenter ?? { message, details in
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = message
            alert.informativeText = details
            alert.runModal()
        }
        self.codeLanguage = CodeLanguage(rawValue: defaults.string(forKey: codeLanguageKey) ?? "") ?? .swift
        self.codeTheme = CodeTheme(rawValue: defaults.string(forKey: codeThemeKey) ?? "") ?? .studio
        self.codeFont = CodeFont(rawValue: defaults.string(forKey: codeFontKey) ?? "") ?? .systemMono
        let storedCodeFontSize = defaults.double(forKey: codeFontSizeKey)
        self.codeFontSize = storedCodeFontSize == 0 ? 14 : min(max(CGFloat(storedCodeFontSize.rounded()), 11), 24)
        self.codeUseTabs = defaults.bool(forKey: codeUseTabsKey)
        let storedTabWidth = defaults.integer(forKey: codeTabWidthKey)
        self.codeTabWidth = [2, 4, 8].contains(storedTabWidth) ? storedTabWidth : 4
        self.codeLineWrap = defaults.bool(forKey: codeLineWrapKey)
        self.autosaveOnTabSwitch = defaults.bool(forKey: autosaveOnTabSwitchKey)
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
        if !restoreWorkspaceIfAvailable() {
            bootstrapWorkspace()
        }
    }

    func newDocument() {
        openNewWorkspaceTab(mode: .prose)
        auditLogger.info("new_document")
    }

    func newScreenplay() {
        openNewWorkspaceTab(mode: .screenplay)
        auditLogger.info("new_screenplay")
    }

    func newCodeDocument() {
        openNewWorkspaceTab(mode: .code)
        auditLogger.info("new_code_document", metadata: ["language": codeLanguage.rawValue])
    }

    func closeDocument() {
        guard let activeTabID else { return }
        closeTab(activeTabID)
    }

    func switchToTab(_ id: UUID) {
        activateWorkspaceTab(id, autosaveCurrent: true)
    }

    func selectAdjacentTab(offset: Int) {
        guard workspaceTabs.count > 1,
              let activeTabID,
              let currentIndex = workspaceTabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let count = workspaceTabs.count
        let nextIndex = (currentIndex + offset % count + count) % count
        switchToTab(workspaceTabs[nextIndex].id)
    }

    func selectAdjacentScene(offset: Int) {
        guard authoringMode == .screenplay,
              offset != 0,
              !screenplayScenes.isEmpty else { return }

        let caretLocation = formattingBridge.captureEditorLocation().selection.location
        let target: ScreenplayScene?
        if offset > 0 {
            target = screenplayScenes.first(where: { $0.location > caretLocation })
                ?? screenplayScenes.first
        } else {
            target = screenplayScenes.last(where: { $0.location < caretLocation })
                ?? screenplayScenes.last
        }

        guard let target else { return }
        formattingBridge.focusScreenplayLocation(target.location)
        screenplayElement = .sceneHeading
    }

    func screenplayScenes(matching query: String) -> [ScreenplayScene] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return screenplayScenes }

        let productionQuery = trimmedQuery.replacingOccurrences(of: "#", with: "").uppercased()
        if screenplaySettings.draft == .production,
           screenplayScenes.contains(where: { $0.productionNumber == productionQuery }) {
            return screenplayScenes.filter { $0.productionNumber == productionQuery }
        }
        let numberQuery = trimmedQuery.hasPrefix("#")
            ? String(trimmedQuery.dropFirst())
            : trimmedQuery
        if let sceneNumber = Int(numberQuery), sceneNumber > 0 {
            return screenplayScenes.filter { $0.number == sceneNumber }
        }

        let terms = trimmedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        return screenplayScenes.filter { scene in
            terms.allSatisfy { scene.heading.localizedStandardContains($0) }
        }
    }

    func closeTab(_ id: UUID) {
        guard let initialIndex = workspaceTabs.firstIndex(where: { $0.id == id }) else { return }
        let previouslyActiveTabID = activeTabID

        if activeTabID != id {
            guard workspaceTabs[initialIndex].isDirty else {
                archiveAndRemoveTab(id, fallbackIndex: initialIndex)
                return
            }
            activateWorkspaceTab(id, autosaveCurrent: true)
        }

        guard activeTabID == id, confirmCanAbandonChanges() else {
            if let previouslyActiveTabID, previouslyActiveTabID != id {
                activateWorkspaceTab(previouslyActiveTabID, autosaveCurrent: false)
            }
            return
        }

        archiveAndRemoveTab(id, fallbackIndex: initialIndex)
    }

    func reopenClosedTab() {
        guard let (tab, archivedState) = closedWorkspaceTabs.popLast() else { return }
        canReopenClosedTab = !closedWorkspaceTabs.isEmpty
        var state = archivedState

        if let url = state.currentURL,
           let existingTab = workspaceTabs.first(where: { urlsReferToSameDocument($0.url, url) }) {
            if state.hasUnsavedChanges {
                state.title = recoveredTitle(for: state.title)
                state.currentURL = nil
                state.diskVersion = nil
            } else {
                switchToTab(existingTab.id)
                return
            }
        }

        state = reconciledCleanNamedState(state)
        autosaveCurrentTabIfNeeded()
        syncActiveTabState()
        let id = workspaceTabs.contains(where: { $0.id == tab.id }) ? UUID() : tab.id
        workspaceTabs.append(workspaceTab(from: state, id: id))
        workspaceTabStates[id] = state
        activateWorkspaceTab(id, autosaveCurrent: false)
    }

    func duplicateTab(_ id: UUID) {
        if activeTabID == id {
            syncActiveTabState()
        }
        guard var state = workspaceTabStates[id] else { return }
        state.title = "\(state.title) Copy"
        state.attributedText = state.attributedText.copy() as? NSAttributedString ?? state.attributedText
        state.currentURL = nil
        state.diskVersion = nil
        state.hasUnsavedChanges = true
        state.editorLocation = EditorLocationSnapshot()
        installNewWorkspaceTab(state: state, reuseActiveTab: false)
        auditLogger.info("duplicate_workspace_tab", metadata: ["mode": state.authoringMode.rawValue])
    }

    func revealDocumentInFinder(forTab id: UUID) {
        guard let url = workspaceTabStates[id]?.currentURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyDocumentPath(forTab id: UUID) {
        guard let path = workspaceTabStates[id]?.currentURL?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    func markDirty(deferMetrics: Bool = false) {
        lastMetricsText = nil
        hasUnsavedChanges = true
        invalidateLanguageToolResults()
        metricsWorkItem?.cancel()
        if deferMetrics {
            let tabID = activeTabID
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.activeTabID == tabID else { return }
                self.updateMetrics()
            }
            metricsWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        } else {
            updateMetrics()
        }
        scheduleWorkspaceRecovery()
    }

    func flushWorkspaceRecovery() {
        workspaceRecoveryWorkItem?.cancel()
        workspaceRecoveryWorkItem = nil
        persistWorkspaceRecovery()
        // Closing/losing focus is a durability boundary: drain earlier writes in order.
        recoveryWriter.flush()
    }

    func updateScreenplayCursor(location: Int) {
        screenplayCursorLocation = min(max(0, location), attributedText.length)
        var low = 0
        var high = screenplayScenes.count
        while low < high {
            let middle = low + (high - low) / 2
            if screenplayScenes[middle].location <= screenplayCursorLocation { low = middle + 1 }
            else { high = middle }
        }
        let active = authoringMode == .screenplay && low > 0 ? screenplayScenes[low - 1].id : nil
        if activeScreenplaySceneID != active { activeScreenplaySceneID = active }
    }

    func updateRenderedScreenplayPageCount(_ count: Int) {
        let normalizedCount = max(1, count)
        guard screenplayPageCount != normalizedCount else { return }
        screenplayPageCount = normalizedCount
    }

    func updateCodeCursor(line: Int, column: Int, selectionLength: Int) {
        let normalizedLine = max(1, line)
        let normalizedColumn = max(1, column)
        let normalizedSelection = max(0, selectionLength)
        guard codeCursorLine != normalizedLine
                || codeCursorColumn != normalizedColumn
                || codeSelectionLength != normalizedSelection else { return }
        codeCursorLine = normalizedLine
        codeCursorColumn = normalizedColumn
        codeSelectionLength = normalizedSelection
    }

    func toggleCodeComment() {
        guard authoringMode == .code, let prefix = codeLanguage.lineCommentPrefix else { return }
        formattingBridge.toggleLineComment(prefix: prefix)
    }

    func duplicateCodeLines() {
        guard authoringMode == .code else { return }
        formattingBridge.duplicateSelectedLines()
    }

    func adjustEditorZoom(by delta: CGFloat) {
        guard delta.isFinite else { return }
        var current = editorZoom
        if authoringMode == .screenplay {
            if screenplayViewStyle.usesAutomaticZoom {
                current = formattingBridge.textView?.enclosingScrollView?.magnification ?? editorZoom
            }
            screenplayViewStyle = .page
        }
        setEditorZoom(current + delta)
    }

    func resetEditorZoom() {
        if authoringMode == .screenplay {
            screenplayViewStyle = .page
        }
        setEditorZoom(1)
    }

    func setEditorZoom(_ zoom: CGFloat) {
        guard zoom.isFinite else { return }
        formattingBridge.focusEditor(revealSelection: false)
        let clamped = min(max(zoom, 0.6), 2)
        guard abs(clamped - editorZoom) > 0.001 else { return }
        editorZoom = clamped
        defaults.set(Double(clamped), forKey: editorZoomKey)
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = Self.openableDocumentTypes

        guard panel.runModal() == .OK, !panel.urls.isEmpty else {
            auditLogger.info("open_document_cancelled")
            return
        }

        auditLogger.info("open_document_selected", metadata: ["count": panel.urls.count])
        for url in panel.urls {
            openDocument(at: url)
        }
    }

    func openExternalDocument(at url: URL) {
        openDocument(at: url)
    }

    func reopenLastDocument() {
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
        if let existingTab = workspaceTabs.first(where: { urlsReferToSameDocument($0.url, url) }) {
            if existingTab.id == activeTabID {
                syncActiveTabState()
                if var state = workspaceTabStates[existingTab.id] {
                    state = reconciledCleanNamedState(state)
                    workspaceTabStates[existingTab.id] = state
                    loadWorkspaceState(state)
                    refreshActiveTabMetadata()
                    scheduleWorkspaceRecovery()
                }
            } else {
                switchToTab(existingTab.id)
            }
            trackRecent(url)
            return true
        }

        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let loaded = try loadAttributedString(from: url)
            let state = DocumentWorkspaceTabState(
                title: resolvedDocumentTitle(
                    loaded.documentTitle,
                    fallback: url.deletingPathExtension().lastPathComponent
                ),
                attributedText: loaded.text,
                currentURL: url,
                currentType: loaded.type,
                authoringMode: loaded.mode,
                codeLanguage: loaded.codeLanguage ?? codeLanguage,
                screenplayElement: loaded.mode == .screenplay ? .action : screenplayElement,
                pageLayout: loaded.pageLayout,
                hasUnsavedChanges: false,
                editorLocation: EditorLocationSnapshot(),
                diskVersion: DocumentDiskVersion.capture(at: url),
                screenplaySettings: loaded.screenplaySettings
            )
            installNewWorkspaceTab(state: state, reuseActiveTab: isCurrentTabPristine)
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
        if pageLayout.hasNativeOnlyFeatures || authoringMode == .screenplay,
           currentURL != nil,
           currentType != .mongrelDocument,
           currentType != .mongrelScreenplay {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = authoringMode == .screenplay ? "Preserve screenplay structure?" : "Preserve page layout?"
            alert.informativeText = "RTF, RTFD, Word, and plain text do not retain Mongrel screenplay elements, draft settings, production scene identities, or page layout. Save a native Mongrel file to preserve this document."
            alert.addButton(withTitle: "Save as Mongrel Document")
            alert.addButton(withTitle: "Save Without Mongrel Metadata")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                saveDocumentAs(preferredType: authoringMode == .screenplay ? .mongrelScreenplay : .mongrelDocument)
            case .alertSecondButtonReturn:
                if let currentURL {
                    writeDocument(to: currentURL, type: currentType)
                }
            default:
                break
            }
            return
        }

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
        let initialType = preferredType ?? (authoringMode == .screenplay ? .mongrelScreenplay : currentType)
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
        let ext = suggestedFilename(for: currentType).split(separator: ".").last.map(String.init) ?? "txt"
        panel.nameFieldStringValue = "\(baseName)-copy.\(ext)"

        guard panel.runModal() == .OK, let url = panel.url else {
            auditLogger.info("save_document_copy_cancelled")
            return
        }

        let type = documentType(for: url)
        if saveDocumentCopy(to: url, type: type) {
            auditLogger.info("save_document_copy_success", metadata: ["file": url.lastPathComponent])
        }
    }

    /// Writes an untracked copy while protecting the backing file of the active tab.
    @discardableResult
    func saveDocumentCopy(to url: URL, type: UTType? = nil) -> Bool {
        let resolvedType = type ?? documentType(for: url)
        return writeDocument(to: url, type: resolvedType, shouldTrackAsCurrent: false)
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

    func exportAsRTFD() {
        export(type: .rtfd)
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

    func choosePageBandImage(for location: PageBandLocation) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentImageSupport.contentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose PNG, JPEG, HEIC, TIFF, GIF, or PDF artwork up to 20 MB."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let image = try DocumentImageSupport.loadPageImage(from: url)
            switch location {
            case .header:
                pageLayout.header.image = image
                pageLayout.header.isEnabled = true
            case .footer:
                pageLayout.footer.image = image
                pageLayout.footer.isEnabled = true
            }
            auditLogger.info("page_band_image_added", metadata: [
                "location": location.rawValue,
                "type": image.contentTypeIdentifier,
                "bytes": image.data.count
            ])
        } catch {
            presentError(
                "Could not attach image",
                details: "Choose a valid PNG, JPEG, HEIC, TIFF, GIF, or PDF file no larger than 20 MB."
            )
            auditLogger.error("page_band_image_failed", error: error, metadata: ["location": location.rawValue])
        }
    }

    func removePageBandImage(for location: PageBandLocation) {
        switch location {
        case .header: pageLayout.header.image = nil
        case .footer: pageLayout.footer.image = nil
        }
    }

    func applyPagePalette(_ palette: DocumentPagePalette) {
        pageLayout.palette = palette
        recolorDocumentTextForPagePalette(shouldMarkDirty: true)
    }

    func updateCustomPageColors(background: DocumentRGBColor, text: DocumentRGBColor) {
        pageLayout.customPageBackground = background
        pageLayout.customPageText = text
        pageLayout.palette = .custom
        recolorDocumentTextForPagePalette(shouldMarkDirty: true)
    }

    private func recolorDocumentTextForPagePalette(shouldMarkDirty: Bool) {
        guard authoringMode != .code else { return }
        formattingBridge.documentTextColor = pageLayout.pageColors.text.nsColor
        guard attributedText.length > 0 else {
            if shouldMarkDirty { hasUnsavedChanges = true }
            return
        }

        let recolored = NSMutableAttributedString(attributedString: attributedText)
        recolored.addAttribute(
            .foregroundColor,
            value: pageLayout.pageColors.text.nsColor,
            range: NSRange(location: 0, length: recolored.length)
        )
        attributedText = recolored
        if shouldMarkDirty {
            markDirty()
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
        languageToolIssues = []
        let requestID = UUID()
        languageToolRequestID = requestID
        Task { [weak self] in
            guard let self else { return }
            do {
                let issues = try await LocalLanguageToolClient.check(checkedText)
                guard languageToolRequestID == requestID else { return }
                guard attributedText.string == checkedText else {
                    invalidateLanguageToolResults()
                    auditLogger.info("language_tool_check_discarded_stale_result")
                    return
                }
                languageToolRequestID = nil
                languageToolIssues = issues
                languageToolState = .complete(issues.count)
                auditLogger.info("language_tool_check_success", metadata: ["issues": issues.count])
            } catch {
                guard languageToolRequestID == requestID else { return }
                languageToolRequestID = nil
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
        guard languageToolIssues.contains(issue) else { return }
        let range = NSRange(location: issue.offset, length: issue.length)
        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= attributedText.length else { return }
        let updated = NSMutableAttributedString(attributedString: attributedText)
        updated.replaceCharacters(in: range, with: replacement)
        attributedText = updated
        languageToolIssues = []
        languageToolState = .idle
        markDirty()
    }

    private func invalidateLanguageToolResults() {
        languageToolRequestID = nil
        if !languageToolIssues.isEmpty {
            languageToolIssues = []
        }
        if languageToolState != .idle {
            languageToolState = .idle
        }
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
        let ext: String
        if type == .mongrelDocument {
            ext = "mongreldoc"
        } else if type == .mongrelScreenplay {
            ext = "mgscreenplay"
        } else if type.conforms(to: .sourceCode) {
            ext = codeLanguage.preferredFilenameExtension
        } else {
            ext = type.preferredFilenameExtension ?? "txt"
        }
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

    private func resolvedDocumentTitle(_ storedTitle: String?, fallback: String) -> String {
        let trimmed = storedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let placeholders = ["untitled", "untitled screenplay", "untitled source"]
        guard !trimmed.isEmpty, !placeholders.contains(trimmed.lowercased()) else {
            return fallback
        }
        return String(trimmed.prefix(240))
    }

    private func documentType(for url: URL) -> UTType {
        switch url.pathExtension.lowercased() {
        case "mongreldoc": return .mongrelDocument
        case "mgscreenplay": return .mongrelScreenplay
        case "rtfd": return .rtfd
        case "rtf": return .rtf
        case "docx": return .wordDocument
        case "txt", "text": return .plainText
        default:
            return CodeLanguage.detected(from: url)?.contentType
                ?? UTType(filenameExtension: url.pathExtension)
                ?? currentType
        }
    }

    private func defaultDocumentType(for mode: AuthoringMode) -> UTType {
        switch mode {
        case .screenplay: return .mongrelScreenplay
        case .code: return codeLanguage.contentType
        case .prose: return .mongrelDocument
        }
    }

    private func loadAttributedString(from url: URL) throws -> (
        text: NSAttributedString,
        type: UTType,
        mode: AuthoringMode,
        codeLanguage: CodeLanguage?,
        pageLayout: DocumentPageLayout,
        documentTitle: String?,
        screenplaySettings: ScreenplayDocumentSettings
    ) {
        if url.pathExtension.lowercased() == "mongreldoc" {
            let archive = try JSONDecoder().decode(
                MongrelDocumentArchive.self,
                from: Data(contentsOf: url)
            )
            return (
                try archive.makeAttributedString(),
                .mongrelDocument,
                archive.authoringMode,
                archive.codeLanguage,
                archive.pageLayout.sanitized,
                archive.documentTitle,
                archive.screenplaySettings ?? .init()
            )
        }

        if url.pathExtension.lowercased() == "mgscreenplay" {
            let archive = try JSONDecoder().decode(
                MongrelScreenplayArchive.self,
                from: Data(contentsOf: url)
            )
            return (
                try archive.makeAttributedString(),
                .mongrelScreenplay,
                .screenplay,
                nil,
                (archive.pageLayout ?? .empty).sanitized,
                archive.documentTitle,
                archive.screenplaySettings ?? .init()
            )
        }

        if url.pathExtension.lowercased() == "rtf" {
            let text = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return (text, .rtf, .prose, nil, .empty, nil, .init())
        }

        if url.pathExtension.lowercased() == "rtfd" {
            let text = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            )
            return (text, .rtfd, .prose, nil, .empty, nil, .init())
        }

        if url.pathExtension.lowercased() == "docx" {
            let text = try WordDocumentCodec.read(from: url)
            return (text, .wordDocument, .prose, nil, .empty, nil, .init())
        }

        let imported = try NSAttributedString(
            url: url,
            options: [.documentType: NSAttributedString.DocumentType.plain],
            documentAttributes: nil
        )
        let text = imported.string
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
        let detectedLanguage = CodeLanguage.detected(from: url) ?? CodeLanguage.detected(fromShebang: text)
        return (
            attributed,
            detectedLanguage?.contentType ?? .plainText,
            detectedLanguage == nil ? .prose : .code,
            detectedLanguage,
            .empty,
            nil,
            .init()
        )
    }

    @discardableResult
    private func writeDocument(to url: URL, type: UTType, shouldTrackAsCurrent: Bool = true) -> Bool {
        updateMetrics()
        if !shouldTrackAsCurrent, urlsReferToSameDocument(currentURL, url) {
            presentError(
                "Choose a Different Filename",
                details: "A copy or export cannot replace the file backing the active tab. Choose another name or use Save."
            )
            auditLogger.warning(
                "save_document_copy_conflict",
                metadata: ["type": type.identifier, "file": url.lastPathComponent]
            )
            return false
        }

        if let owner = workspaceTabs.first(where: { urlsReferToSameDocument($0.url, url) }),
           owner.id != activeTabID {
            presentError(
                "File Is Already Open",
                details: "\(url.lastPathComponent) belongs to another workspace tab. Close that tab or choose a different filename."
            )
            auditLogger.warning(
                "save_document_conflict",
                metadata: ["type": type.identifier, "file": url.lastPathComponent]
            )
            return false
        }

        if shouldTrackAsCurrent,
           urlsReferToSameDocument(currentURL, url),
           let currentDiskVersion,
           DocumentDiskVersion.capture(at: url) != currentDiskVersion {
            presentError(
                "File Changed on Disk",
                details: "The file changed or disappeared after this tab opened. Use Save As to preserve this draft without erasing the other version."
            )
            auditLogger.warning(
                "save_document_external_change_conflict",
                metadata: ["type": type.identifier, "file": url.lastPathComponent]
            )
            return false
        }

        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if type == .mongrelDocument {
                let data = try JSONEncoder().encode(MongrelDocumentArchive(
                    attributedText: attributedText,
                    authoringMode: authoringMode,
                    codeLanguage: authoringMode == .code ? codeLanguage : nil,
                    pageLayout: pageLayout,
                    documentTitle: resolvedDocumentTitle(
                        title,
                        fallback: url.deletingPathExtension().lastPathComponent
                    ),
                    screenplaySettings: screenplaySettings
                ))
                try data.write(to: url, options: .atomic)
            } else if type == .mongrelScreenplay {
                let data = try JSONEncoder().encode(MongrelScreenplayArchive(
                    attributedText: attributedText,
                    pageLayout: pageLayout,
                    documentTitle: resolvedDocumentTitle(
                        title,
                        fallback: url.deletingPathExtension().lastPathComponent
                    ),
                    screenplaySettings: screenplaySettings
                ))
                try data.write(to: url, options: .atomic)
            } else if type == .rtfd {
                let range = NSRange(location: 0, length: attributedText.length)
                let wrapper = try attributedText.fileWrapper(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
                )
                try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
            } else if type == .rtf || type == .wordDocument {
                let range = NSRange(location: 0, length: attributedText.length)
                let documentType: NSAttributedString.DocumentType = type == .wordDocument
                    ? .officeOpenXML
                    : .rtf
                let data = try type == .wordDocument
                    ? WordDocumentCodec.data(from: attributedText)
                    : attributedText.data(from: range, documentAttributes: [.documentType: documentType])
                try data.write(to: url, options: .atomic)
            } else {
                let text = attributedText.string
                try text.write(to: url, atomically: true, encoding: .utf8)
            }

            if shouldTrackAsCurrent {
                let savedTitle = type == .mongrelDocument || type == .mongrelScreenplay
                    ? resolvedDocumentTitle(
                        title,
                        fallback: url.deletingPathExtension().lastPathComponent
                    )
                    : url.deletingPathExtension().lastPathComponent
                applyProgrammaticState {
                    currentURL = url
                    currentType = type
                    currentDiskVersion = DocumentDiskVersion.capture(at: url)
                    title = savedTitle
                    hasUnsavedChanges = false
                }
                if let bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    persistenceStore.setLastDocumentBookmarkData(bookmarkData)
                }
                hasRestorableLastDocument = persistenceStore.hasLastDocumentBookmark
                trackRecent(url)
                syncActiveTabState()
                scheduleWorkspaceRecovery()
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
        updateMetrics()
        let margins = authoringMode == .screenplay
            ? NSSize(width: ScreenplayPageLayout.horizontalInset, height: ScreenplayPageLayout.verticalInset)
            : NSSize(width: 36, height: 36)
        return PaginatedDocumentPDFRenderer.render(
            attributedText,
            margins: margins,
            fallbackPageNumbers: authoringMode == .screenplay,
            numberedScenes: authoringMode == .screenplay && screenplaySettings.showsSceneNumbers ? screenplayScenes : [],
            title: title,
            pageLayout: pageLayout
        )
    }

    private func bootstrapWorkspace() {
        guard workspaceTabs.isEmpty else { return }
        installNewWorkspaceTab(state: captureCurrentWorkspaceState(), reuseActiveTab: false)
    }

    private func openNewWorkspaceTab(mode: AuthoringMode) {
        installNewWorkspaceTab(
            state: makeBlankWorkspaceState(mode: mode),
            reuseActiveTab: isCurrentTabPristine
        )
    }

    private var isCurrentTabPristine: Bool {
        currentURL == nil && !hasUnsavedChanges && attributedText.length == 0
    }

    private func makeBlankWorkspaceState(mode: AuthoringMode) -> DocumentWorkspaceTabState {
        let title: String
        let type: UTType
        let element: ScreenplayElement
        switch mode {
        case .prose:
            title = "Untitled"
            type = .mongrelDocument
            element = .action
        case .screenplay:
            title = "Untitled Screenplay"
            type = .mongrelScreenplay
            element = .sceneHeading
        case .code:
            title = "Untitled Source"
            type = codeLanguage.contentType
            element = .action
        }
        return DocumentWorkspaceTabState(
            title: title,
            attributedText: NSAttributedString(string: ""),
            currentURL: nil,
            currentType: type,
            authoringMode: mode,
            codeLanguage: codeLanguage,
            screenplayElement: element,
            pageLayout: .empty,
            hasUnsavedChanges: false,
            editorLocation: EditorLocationSnapshot()
        )
    }

    private func installNewWorkspaceTab(
        state: DocumentWorkspaceTabState,
        reuseActiveTab: Bool
    ) {
        if reuseActiveTab, let activeTabID {
            workspaceTabStates[activeTabID] = state
            loadWorkspaceState(state)
            refreshActiveTabMetadata()
            scheduleWorkspaceRecovery()
            return
        }

        autosaveCurrentTabIfNeeded()
        syncActiveTabState()
        let id = UUID()
        workspaceTabStates[id] = state
        workspaceTabs.append(workspaceTab(from: state, id: id))
        activeTabID = id
        loadWorkspaceState(state)
        refreshActiveTabMetadata()
        scheduleWorkspaceRecovery()
    }

    private func activateWorkspaceTab(_ id: UUID, autosaveCurrent: Bool) {
        guard id != activeTabID,
              workspaceTabs.contains(where: { $0.id == id }),
              var state = workspaceTabStates[id] else { return }

        if autosaveCurrent {
            autosaveCurrentTabIfNeeded()
        }
        syncActiveTabState()
        state = reconciledCleanNamedState(state)
        workspaceTabStates[id] = state
        activeTabID = id
        loadWorkspaceState(state)
        refreshActiveTabMetadata()
        auditLogger.info("switch_workspace_tab", metadata: ["mode": state.authoringMode.rawValue])
        scheduleWorkspaceRecovery()
    }

    private func archiveAndRemoveTab(_ id: UUID, fallbackIndex: Int) {
        let wasActive = activeTabID == id
        if wasActive {
            syncActiveTabState()
        }

        if let tab = workspaceTabs.first(where: { $0.id == id }),
           let state = workspaceTabStates[id],
           !isPristineWorkspaceState(state) {
            closedWorkspaceTabs.append((tab, state))
            if closedWorkspaceTabs.count > 10 {
                closedWorkspaceTabs.removeFirst(closedWorkspaceTabs.count - 10)
            }
        }
        canReopenClosedTab = !closedWorkspaceTabs.isEmpty

        workspaceTabs.removeAll { $0.id == id }
        workspaceTabStates[id] = nil

        if wasActive {
            activeTabID = nil
            if workspaceTabs.isEmpty {
                installNewWorkspaceTab(state: makeBlankWorkspaceState(mode: .prose), reuseActiveTab: false)
            } else {
                let nextIndex = min(fallbackIndex, workspaceTabs.count - 1)
                activateWorkspaceTab(workspaceTabs[nextIndex].id, autosaveCurrent: false)
            }
        }
        auditLogger.info("close_document")
        scheduleWorkspaceRecovery()
    }

    private func isPristineWorkspaceState(_ state: DocumentWorkspaceTabState) -> Bool {
        state.currentURL == nil
            && !state.hasUnsavedChanges
            && state.attributedText.length == 0
            && state.pageLayout == .empty
    }

    private func urlsReferToSameDocument(_ lhs: URL?, _ rhs: URL) -> Bool {
        guard let lhs else { return false }
        return canonicalDocumentURL(lhs) == canonicalDocumentURL(rhs)
    }

    private func canonicalDocumentURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func reconciledCleanNamedState(_ state: DocumentWorkspaceTabState) -> DocumentWorkspaceTabState {
        guard !state.hasUnsavedChanges, let url = state.currentURL else { return state }
        guard let diskVersion = DocumentDiskVersion.capture(at: url) else {
            auditLogger.warning("workspace_tab_backing_file_unavailable", metadata: ["file": url.lastPathComponent])
            return detachedRecoveredState(from: state)
        }
        guard diskVersion != state.diskVersion else { return state }

        let didAccessSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let loaded = try loadAttributedString(from: url)
            auditLogger.info("workspace_tab_reloaded_external_change", metadata: ["file": url.lastPathComponent])
            return DocumentWorkspaceTabState(
                title: resolvedDocumentTitle(
                    loaded.documentTitle,
                    fallback: url.deletingPathExtension().lastPathComponent
                ),
                attributedText: loaded.text,
                currentURL: url,
                currentType: loaded.type,
                authoringMode: loaded.mode,
                codeLanguage: loaded.codeLanguage ?? state.codeLanguage,
                screenplayElement: loaded.mode == .screenplay ? state.screenplayElement : .action,
                pageLayout: loaded.pageLayout,
                hasUnsavedChanges: false,
                editorLocation: state.editorLocation,
                diskVersion: diskVersion,
                screenplaySettings: loaded.screenplaySettings
            )
        } catch {
            auditLogger.error(
                "workspace_tab_external_reload_failed",
                error: error,
                metadata: ["file": url.lastPathComponent]
            )
            return detachedRecoveredState(from: state)
        }
    }

    private func detachedRecoveredState(from state: DocumentWorkspaceTabState) -> DocumentWorkspaceTabState {
        var recovered = state
        recovered.title = recoveredTitle(for: state.title)
        recovered.currentURL = nil
        recovered.diskVersion = nil
        recovered.hasUnsavedChanges = true
        return recovered
    }

    private func recoveredTitle(for title: String) -> String {
        title.hasSuffix(" (Recovered)") ? title : "\(title) (Recovered)"
    }

    private func scheduleWorkspaceRecovery() {
        guard !isSwitchingTabs else { return }
        if let activeTabID { recoveryArchiveCache.removeValue(forKey: activeTabID) }
        workspaceRecoveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.workspaceRecoveryWorkItem = nil
            self?.persistWorkspaceRecovery()
        }
        workspaceRecoveryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func persistWorkspaceRecovery() {
        updateMetrics()
        syncActiveTabState()
        let openIDs = Set(workspaceTabs.map(\.id))
        recoveryArchiveCache = recoveryArchiveCache.filter { openIDs.contains($0.key) }

        if workspaceTabs.count == 1,
           let onlyTab = workspaceTabs.first,
           let onlyState = workspaceTabStates[onlyTab.id],
           isPristineWorkspaceState(onlyState) {
            do {
                // A queued save must finish before clearing a now-pristine workspace.
                recoveryWriter.flush()
                try workspaceRecoveryStore.clear()
            } catch {
                auditLogger.error("workspace_recovery_clear_failed", error: error)
            }
            return
        }

        do {
            let recoveredTabs = try workspaceTabs.map { tab -> WorkspaceRecoveryTab in
                guard let state = workspaceTabStates[tab.id] else {
                    throw WorkspaceRecoveryError.missingTabState
                }
                let recovered = try WorkspaceRecoveryTab(tab: tab, state: state, cachedArchive: recoveryArchiveCache[tab.id])
                recoveryArchiveCache[tab.id] = recovered.archive
                return recovered
            }
            let manifest = WorkspaceRecoveryManifest(
                activeTabID: activeTabID,
                tabs: recoveredTabs
            )
            let write = WorkspaceRecoveryWrite(manifest: manifest, store: workspaceRecoveryStore, logger: auditLogger)
            recoveryWriter.enqueue { write.perform() }
        } catch {
            auditLogger.error("workspace_recovery_save_failed", error: error)
        }
    }

    private func restoreWorkspaceIfAvailable() -> Bool {
        do {
            guard let data = try workspaceRecoveryStore.load() else { return false }
            let manifest = try JSONDecoder().decode(WorkspaceRecoveryManifest.self, from: data)
            guard manifest.formatVersion == WorkspaceRecoveryManifest.currentVersion,
                  !manifest.tabs.isEmpty,
                  manifest.tabs.count <= WorkspaceRecoveryManifest.maximumTabCount else {
                throw WorkspaceRecoveryError.unsupportedManifest
            }

            var restoredTabs: [DocumentWorkspaceTab] = []
            var restoredStates: [UUID: DocumentWorkspaceTabState] = [:]
            var restoredURLs = Set<URL>()

            for recoveredTab in manifest.tabs {
                let state = try makeWorkspaceState(from: recoveredTab)
                if let url = state.currentURL {
                    let canonicalURL = canonicalDocumentURL(url)
                    guard restoredURLs.insert(canonicalURL).inserted else {
                        throw WorkspaceRecoveryError.duplicateDocument
                    }
                }
                // A damaged manifest must not make two tabs share one mutable state.
                let id = restoredStates[recoveredTab.id] == nil ? recoveredTab.id : UUID()
                restoredTabs.append(workspaceTab(from: state, id: id))
                restoredStates[id] = state
            }

            workspaceTabs = restoredTabs
            workspaceTabStates = restoredStates
            let requestedActiveID = manifest.activeTabID
            activeTabID = requestedActiveID.flatMap { id in
                restoredTabs.contains(where: { $0.id == id }) ? id : nil
            } ?? restoredTabs[0].id
            if let activeTabID, let activeState = restoredStates[activeTabID] {
                loadWorkspaceState(activeState)
            }
            auditLogger.info("workspace_recovery_restored", metadata: ["tabs": restoredTabs.count])
            return true
        } catch {
            do {
                try workspaceRecoveryStore.quarantine()
            } catch {
                auditLogger.error("workspace_recovery_quarantine_failed", error: error)
            }
            auditLogger.error("workspace_recovery_restore_failed", error: error)
            return false
        }
    }

    private func makeWorkspaceState(from recoveredTab: WorkspaceRecoveryTab) throws -> DocumentWorkspaceTabState {
        let resolvedURL = recoveredTab.resolveURL()
        // Even checking existence and disk identity needs the resolved grant.
        // Keep it active for clean reloads and dirty-draft conflict checks alike.
        let didAccessSecurityScope = resolvedURL?.startAccessingSecurityScopedResource() ?? false
        defer { if didAccessSecurityScope { resolvedURL?.stopAccessingSecurityScopedResource() } }
        let fileExists = resolvedURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        var backingFileUnreadable = false

        if !recoveredTab.isDirty, let resolvedURL, fileExists {
            if let loaded = try? loadAttributedString(from: resolvedURL) {
                return DocumentWorkspaceTabState(
                    title: resolvedDocumentTitle(
                        loaded.documentTitle,
                        fallback: resolvedURL.deletingPathExtension().lastPathComponent
                    ),
                    attributedText: loaded.text,
                    currentURL: resolvedURL,
                    currentType: loaded.type,
                    authoringMode: loaded.mode,
                    codeLanguage: loaded.codeLanguage ?? recoveredTab.codeLanguage,
                    screenplayElement: recoveredTab.screenplayElement,
                    pageLayout: loaded.pageLayout,
                    hasUnsavedChanges: false,
                    editorLocation: recoveredTab.editorLocation,
                    diskVersion: DocumentDiskVersion.capture(at: resolvedURL),
                    screenplaySettings: loaded.screenplaySettings
                )
            }
            backingFileUnreadable = true
        }

        let namedFileUnavailable = recoveredTab.filePath != nil && (!fileExists || backingFileUnreadable)
        let diskVersionChanged = recoveredTab.isDirty
            && fileExists
            && resolvedURL.map { !recoveredTab.matchesDiskVersion(at: $0) } == true
        let recoveredTitle: String
        if namedFileUnavailable {
            recoveredTitle = "\(recoveredTab.title) (Recovered)"
        } else if diskVersionChanged {
            recoveredTitle = "\(recoveredTab.title) (Recovered Conflict)"
        } else {
            recoveredTitle = recoveredTab.title
        }
        return DocumentWorkspaceTabState(
            title: recoveredTitle,
            attributedText: try recoveredTab.archive.makeAttributedString(),
            currentURL: fileExists && !backingFileUnreadable && !diskVersionChanged ? resolvedURL : nil,
            currentType: UTType(recoveredTab.currentTypeIdentifier)
                ?? defaultDocumentType(for: recoveredTab.authoringMode),
            authoringMode: recoveredTab.authoringMode,
            codeLanguage: recoveredTab.codeLanguage,
            screenplayElement: recoveredTab.screenplayElement,
            pageLayout: recoveredTab.archive.pageLayout.sanitized,
            hasUnsavedChanges: recoveredTab.isDirty || namedFileUnavailable,
            editorLocation: recoveredTab.editorLocation,
            diskVersion: fileExists && !backingFileUnreadable && !diskVersionChanged
                ? resolvedURL.flatMap { DocumentDiskVersion.capture(at: $0) }
                : nil,
            screenplaySettings: recoveredTab.archive.screenplaySettings ?? .init()
        )
    }

    private func autosaveCurrentTabIfNeeded() {
        guard autosaveOnTabSwitch,
              hasUnsavedChanges,
              let currentURL else { return }
        let wouldDropNativeLayout = (pageLayout.hasNativeOnlyFeatures || authoringMode == .screenplay)
            && currentType != .mongrelDocument
            && currentType != .mongrelScreenplay
        guard !wouldDropNativeLayout else { return }
        _ = writeDocument(to: currentURL, type: currentType)
    }

    private func captureCurrentWorkspaceState() -> DocumentWorkspaceTabState {
        DocumentWorkspaceTabState(
            title: title,
            attributedText: attributedText.copy() as? NSAttributedString ?? attributedText,
            currentURL: currentURL,
            currentType: currentType,
            authoringMode: authoringMode,
            codeLanguage: codeLanguage,
            screenplayElement: screenplayElement,
            pageLayout: pageLayout,
            hasUnsavedChanges: hasUnsavedChanges,
            editorLocation: formattingBridge.captureEditorLocation(),
            diskVersion: currentDiskVersion,
            screenplaySettings: screenplaySettings
        )
    }

    private func syncActiveTabState() {
        guard let activeTabID else { return }
        let state = captureCurrentWorkspaceState()
        workspaceTabStates[activeTabID] = state
        if let index = workspaceTabs.firstIndex(where: { $0.id == activeTabID }) {
            workspaceTabs[index] = workspaceTab(from: state, id: activeTabID)
        }
    }

    private func loadWorkspaceState(_ state: DocumentWorkspaceTabState) {
        metricsWorkItem?.cancel()
        metricsWorkItem = nil
        isSwitchingTabs = true
        screenplayCursorLocation = state.editorLocation.selection.location
        applyProgrammaticState {
            title = state.title
            attributedText = state.attributedText.copy() as? NSAttributedString ?? state.attributedText
            currentURL = state.currentURL
            currentType = state.currentType
            currentDiskVersion = state.diskVersion
            authoringMode = state.authoringMode
            codeLanguage = state.codeLanguage
            screenplayElement = state.screenplayElement
            pageLayout = state.pageLayout
            screenplaySettings = state.screenplaySettings
            hasUnsavedChanges = state.hasUnsavedChanges
            codeCursorLine = 1
            codeCursorColumn = 1
            codeSelectionLength = 0
        }
        isSwitchingTabs = false
        invalidateLanguageToolResults()
        formattingBridge.documentTextColor = pageLayout.pageColors.text.nsColor
        updateMetrics()
        formattingBridge.restoreEditorLocation(state.editorLocation)
    }

    private func workspaceTab(from state: DocumentWorkspaceTabState, id: UUID) -> DocumentWorkspaceTab {
        DocumentWorkspaceTab(
            id: id,
            title: state.title,
            mode: state.authoringMode,
            isDirty: state.hasUnsavedChanges,
            url: state.currentURL
        )
    }

    private func refreshActiveTabMetadata() {
        guard !isSwitchingTabs,
              let activeTabID,
              let index = workspaceTabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let updated = DocumentWorkspaceTab(
            id: activeTabID,
            title: title,
            mode: authoringMode,
            isDirty: hasUnsavedChanges,
            url: currentURL
        )
        if workspaceTabs[index] != updated {
            workspaceTabs[index] = updated
        }
    }

    private func confirmCanAbandonChanges() -> Bool {
        guard hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save changes to “\(title)”?"
        alert.informativeText = "Save this document before closing its tab."
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
        errorPresenter(message, details)
    }
}

// MARK: – Recent documents + metrics

extension DocumentSession {

    private func updateMetrics() {
        metricsWorkItem?.cancel()
        metricsWorkItem = nil
        guard lastMetricsText !== attributedText || lastMetricsMode != authoringMode
                || lastMetricsDraft != screenplaySettings.draft else { return }
        let text = attributedText.string
        let words = text.split(whereSeparator: \.isWhitespace).filter { !$0.isEmpty }
        wordCount = words.count
        charCount = text.filter { !$0.isWhitespace && !$0.isNewline }.count
        let scenes = collectScreenplayScenes()
        screenplayScenes = reconcileProductionScenes(scenes)
        screenplaySceneCount = screenplayScenes.count
        updateScreenplayCursor(location: screenplayCursorLocation)
        if authoringMode != .screenplay || formattingBridge.textView == nil {
            screenplayPageCount = estimateScreenplayPageCount()
        }
        screenplayCatalog = authoringMode == .screenplay ? ScreenplayCatalog.analyze(attributedText) : .init()
        formattingBridge.documentCatalog = screenplayCatalog
        documentInsights = DocumentInsightsAnalyzer.analyze(
            attributedText,
            scenes: screenplayScenes,
            mode: authoringMode
        )
        lastMetricsText = attributedText
        lastMetricsMode = authoringMode
        lastMetricsDraft = screenplaySettings.draft
    }

    private func reconcileProductionScenes(_ scenes: [ScreenplayScene]) -> [ScreenplayScene] {
        guard authoringMode == .screenplay, screenplaySettings.draft == .production else { return scenes }
        var records = screenplaySettings.sceneRecords
        let initial = records.isEmpty
        var reserved = Set(records.map(\.number))
        var seen = Set<String>()
        var previous: String?
        let text = NSMutableAttributedString(attributedString: attributedText)
        var changed = false
        var result: [ScreenplayScene] = []
        for var scene in scenes {
            var identity = text.attribute(.screenplaySceneIdentity, at: scene.location, effectiveRange: nil) as? String
            if identity == nil || seen.contains(identity!) {
                identity = UUID().uuidString
                let range = (text.string as NSString).paragraphRange(for: NSRange(location: scene.location, length: 0))
                text.addAttribute(.screenplaySceneIdentity, value: identity!, range: range)
                changed = true
            }
            seen.insert(identity!)
            if let index = records.firstIndex(where: { $0.id == identity }) {
                records[index].heading = scene.heading
                records[index].isOmitted = false
                scene.productionNumber = records[index].number
            } else {
                let number = ScreenplayProductionNumbering.nextNumber(after: previous, reserved: reserved, initial: initial)
                records.append(ScreenplayProductionScene(id: identity!, number: number, heading: scene.heading, isOmitted: false))
                reserved.insert(number)
                scene.productionNumber = number
            }
            previous = scene.productionNumber
            result.append(scene)
        }
        for index in records.indices { records[index].isOmitted = !seen.contains(records[index].id) }
        if changed || records != screenplaySettings.sceneRecords {
            let wasApplying = isApplyingProgrammaticState
            isApplyingProgrammaticState = true
            screenplaySettings.sceneRecords = records
            if changed { attributedText = text }
            isApplyingProgrammaticState = wasApplying
        }
        return result
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
        if let element = ScreenplayCatalog.elementTag(in: attributedText, at: location) {
            return element == .sceneHeading
        }
        return ScreenplayCatalog.isSceneHeading(text)
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

struct MongrelDocumentArchive: Codable {
    struct ElementRange: Codable {
        let location: Int
        let length: Int
        let element: String
    }

    let formatVersion: Int
    let richTextData: Data
    let preservedCharacters: [NativePreservedCharacter]?
    let mode: String
    let codeLanguageName: String?
    let pageLayout: DocumentPageLayout
    let elementRanges: [ElementRange]
    let documentTitle: String?
    let screenplaySettings: ScreenplayDocumentSettings?
    let sceneIdentityRanges: [ScreenplaySceneIdentityRange]?
    let manualElementRanges: [ScreenplaySceneIdentityRange]?

    var authoringMode: AuthoringMode {
        AuthoringMode(rawValue: mode) ?? .prose
    }

    var codeLanguage: CodeLanguage? {
        codeLanguageName.flatMap(CodeLanguage.init(rawValue:))
    }

    init(
        attributedText: NSAttributedString,
        authoringMode: AuthoringMode,
        codeLanguage: CodeLanguage? = nil,
        pageLayout: DocumentPageLayout,
        documentTitle: String? = nil,
        screenplaySettings: ScreenplayDocumentSettings? = nil
    ) throws {
        formatVersion = 2
        let encoded = try NativeRichTextCodec.encode(attributedText, type: .rtfd)
        richTextData = encoded.0
        preservedCharacters = encoded.1
        mode = authoringMode.rawValue
        codeLanguageName = codeLanguage?.rawValue
        self.pageLayout = pageLayout
        self.documentTitle = documentTitle
        self.screenplaySettings = screenplaySettings
        self.sceneIdentityRanges = ScreenplaySceneIdentityRange.collect(from: attributedText)
        self.manualElementRanges = ScreenplaySceneIdentityRange.collect(from: attributedText, key: .screenplayManualElement)

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
        guard (1...2).contains(formatVersion) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let restored = try NSMutableAttributedString(
            data: richTextData,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        )
        NativeRichTextCodec.restorePlaceholders(preservedCharacters, in: restored)
        for elementRange in elementRanges {
            guard ScreenplayElement(rawValue: elementRange.element) != nil,
                  elementRange.location >= 0,
                  elementRange.length >= 0,
                  elementRange.location <= restored.length,
                  elementRange.length <= restored.length - elementRange.location else { continue }
            restored.addAttribute(
                .screenplayElement,
                value: elementRange.element,
                range: NSRange(location: elementRange.location, length: elementRange.length)
            )
        }
        ScreenplaySceneIdentityRange.restore(sceneIdentityRanges, to: restored)
        ScreenplaySceneIdentityRange.restore(manualElementRanges, to: restored, key: .screenplayManualElement)
        return restored
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
    let richTextFormat: String?
    let preservedCharacters: [NativePreservedCharacter]?
    let elementRanges: [ElementRange]
    let pageLayout: DocumentPageLayout?
    let documentTitle: String?
    let screenplaySettings: ScreenplayDocumentSettings?
    let sceneIdentityRanges: [ScreenplaySceneIdentityRange]?
    let manualElementRanges: [ScreenplaySceneIdentityRange]?

    init(
        attributedText: NSAttributedString,
        pageLayout: DocumentPageLayout = .empty,
        documentTitle: String? = nil,
        screenplaySettings: ScreenplayDocumentSettings? = nil
    ) throws {
        formatVersion = 2
        let encoded = try NativeRichTextCodec.encode(attributedText, type: .rtfd)
        richTextData = encoded.0
        preservedCharacters = encoded.1
        richTextFormat = "rtfd"

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
        self.pageLayout = pageLayout
        self.documentTitle = documentTitle
        self.screenplaySettings = screenplaySettings
        self.sceneIdentityRanges = ScreenplaySceneIdentityRange.collect(from: attributedText)
        self.manualElementRanges = ScreenplaySceneIdentityRange.collect(from: attributedText, key: .screenplayManualElement)
    }

    func makeAttributedString() throws -> NSAttributedString {
        guard (1...2).contains(formatVersion) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let restored = try NSMutableAttributedString(
            data: richTextData,
            options: [.documentType: richTextFormat == "rtfd" ? NSAttributedString.DocumentType.rtfd : .rtf],
            documentAttributes: nil
        )
        NativeRichTextCodec.restorePlaceholders(preservedCharacters, in: restored)
        for elementRange in elementRanges {
            guard ScreenplayElement(rawValue: elementRange.element) != nil,
                  elementRange.location >= 0,
                  elementRange.length >= 0,
                  elementRange.location <= restored.length,
                  elementRange.length <= restored.length - elementRange.location else { continue }
            restored.addAttribute(
                .screenplayElement,
                value: elementRange.element,
                range: NSRange(location: elementRange.location, length: elementRange.length)
            )
        }
        ScreenplaySceneIdentityRange.restore(sceneIdentityRanges, to: restored)
        ScreenplaySceneIdentityRange.restore(manualElementRanges, to: restored, key: .screenplayManualElement)
        return restored
    }
}

@MainActor
private enum PaginatedDocumentPDFRenderer {
    static func render(
        _ attributedText: NSAttributedString,
        margins: NSSize,
        fallbackPageNumbers: Bool,
        numberedScenes: [ScreenplayScene],
        title: String,
        pageLayout: DocumentPageLayout
    ) -> Data? {
        let pageSize = ScreenplayPageLayout.pageSize
        let topInset = max(margins.height, pageLayout.header.hasRenderableContent ? 64 : margins.height)
        let bottomInset = max(margins.height, pageLayout.footer.hasRenderableContent ? 64 : margins.height)
        let contentSize = NSSize(
            width: pageSize.width - (margins.width * 2),
            height: pageSize.height - topInset - bottomInset
        )
        guard contentSize.width > 0, contentSize.height > 0 else { return nil }

        let printableText = NSMutableAttributedString(attributedString: attributedText)
        if printableText.length > 0 {
            printableText.addAttribute(
                .foregroundColor,
                value: pageLayout.pageColors.text.nsColor,
                range: NSRange(location: 0, length: printableText.length)
            )
        }
        let textStorage = NSTextStorage(attributedString: printableText)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        var containers: [NSTextContainer] = []
        var laidOutGlyphs = 0

        repeat {
            let container = NSTextContainer(containerSize: contentSize)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(for: container)
            containers.append(container)

            let nextGlyphLocation = NSMaxRange(glyphRange)
            guard nextGlyphLocation > laidOutGlyphs else { break }
            laidOutGlyphs = nextGlyphLocation
        } while laidOutGlyphs < layoutManager.numberOfGlyphs

        let document = PDFDocument()
        for (index, container) in containers.enumerated() {
            let pageView = DocumentPDFPageView(
                frame: NSRect(origin: .zero, size: pageSize),
                layoutManager: layoutManager,
                textContainer: container,
                horizontalMargin: margins.width,
                contentTopInset: topInset,
                pageNumber: index + 1,
                pageCount: containers.count,
                fallbackPageNumbers: fallbackPageNumbers,
                numberedScenes: numberedScenes,
                title: title,
                pageLayout: pageLayout
            )
            let pageData = pageView.dataWithPDF(inside: pageView.bounds)
            guard let page = PDFDocument(data: pageData)?.page(at: 0) else { return nil }
            document.insert(page, at: index)
        }
        return document.dataRepresentation()
    }
}

@MainActor
private final class DocumentPDFPageView: NSView {
    private let layoutManager: NSLayoutManager
    private let textContainer: NSTextContainer
    private let horizontalMargin: CGFloat
    private let contentTopInset: CGFloat
    private let pageNumber: Int
    private let pageCount: Int
    private let fallbackPageNumbers: Bool
    private let numberedScenes: [ScreenplayScene]
    private let title: String
    private let pageLayout: DocumentPageLayout

    init(
        frame: NSRect,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        horizontalMargin: CGFloat,
        contentTopInset: CGFloat,
        pageNumber: Int,
        pageCount: Int,
        fallbackPageNumbers: Bool,
        numberedScenes: [ScreenplayScene],
        title: String,
        pageLayout: DocumentPageLayout
    ) {
        self.layoutManager = layoutManager
        self.textContainer = textContainer
        self.horizontalMargin = horizontalMargin
        self.contentTopInset = contentTopInset
        self.pageNumber = pageNumber
        self.pageCount = pageCount
        self.fallbackPageNumbers = fallbackPageNumbers
        self.numberedScenes = numberedScenes
        self.title = title
        self.pageLayout = pageLayout
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        pageLayout.pageColors.background.nsColor.setFill()
        bounds.fill()

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let origin = NSPoint(x: horizontalMargin, y: contentTopInset)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: pageLayout.pageColors.text.nsColor
        ]
        for scene in numberedScenes {
            let glyph = layoutManager.glyphIndexForCharacter(at: scene.location)
            guard NSLocationInRange(glyph, glyphRange) else { continue }
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = rect.minY + origin.y
            scene.displayNumber.draw(at: NSPoint(x: 40, y: y), withAttributes: numberAttributes)
            scene.displayNumber.draw(at: NSPoint(x: bounds.width - 64, y: y), withAttributes: numberAttributes)
        }

        let shouldDrawFurniture = pageNumber > 1 || pageLayout.showsOnFirstPage
        if shouldDrawFurniture {
            draw(pageLayout.header, at: .header)
            draw(pageLayout.footer, at: .footer)
        }

        if fallbackPageNumbers,
           !pageLayout.footer.hasRenderableContent,
           pageNumber > 1 || pageLayout.showsOnFirstPage {
            drawFallbackPageNumber()
        }
    }

    private func draw(_ band: DocumentPageBand, at location: PageBandLocation) {
        guard band.hasRenderableContent else { return }
        let bandHeight: CGFloat = 28
        let y = location == .header ? 18 : bounds.maxY - bandHeight - 18
        let fullRect = NSRect(
            x: horizontalMargin,
            y: y,
            width: bounds.width - (horizontalMargin * 2),
            height: bandHeight
        )

        var textRect = fullRect
        if let image = band.image?.image {
            let imageRect = fittedImageRect(for: image, in: fullRect, alignment: band.alignment)
            image.draw(
                in: imageRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            let reserved = imageRect.width + 8
            switch band.alignment {
            case .leading:
                textRect.origin.x += reserved
                textRect.size.width -= reserved
            case .trailing:
                textRect.size.width -= reserved
            case .center:
                textRect = NSRect(x: fullRect.minX, y: fullRect.maxY + 1, width: fullRect.width, height: 14)
            }
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = band.alignment.textAlignment
        paragraph.lineBreakMode = .byTruncatingTail
        let resolved = pageLayout.resolvedText(
            for: band,
            title: title,
            pageNumber: pageNumber,
            pageCount: pageCount
        )
        resolved.draw(
            with: textRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: pageLayout.pageColors.text.nsColor.withAlphaComponent(0.78),
                .paragraphStyle: paragraph
            ]
        )
    }

    private func fittedImageRect(
        for image: NSImage,
        in availableRect: NSRect,
        alignment: PageBandAlignment
    ) -> NSRect {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return .zero }
        let scale = min(availableRect.height / sourceSize.height, 84 / sourceSize.width, 1)
        let size = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let x: CGFloat
        switch alignment {
        case .leading: x = availableRect.minX
        case .center: x = availableRect.midX - (size.width / 2)
        case .trailing: x = availableRect.maxX - size.width
        }
        return NSRect(
            x: x,
            y: availableRect.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }

    private func drawFallbackPageNumber() {
        let pageLabel = "\(pageNumber)."
        pageLabel.draw(
            at: NSPoint(x: bounds.maxX - horizontalMargin + 12, y: 18),
            withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: pageLayout.pageColors.text.nsColor.withAlphaComponent(0.78)
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
