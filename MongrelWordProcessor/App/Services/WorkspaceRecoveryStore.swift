import AppKit
import Foundation

struct WorkspaceRecoveryManifest: Codable {
    static let currentVersion = 1
    static let maximumTabCount = 4_096

    let formatVersion: Int
    let savedAt: Date
    let activeTabID: UUID?
    let tabs: [WorkspaceRecoveryTab]

    init(activeTabID: UUID?, tabs: [WorkspaceRecoveryTab]) {
        formatVersion = Self.currentVersion
        savedAt = Date()
        self.activeTabID = activeTabID
        self.tabs = tabs
    }
}

struct WorkspaceRecoveryTab: Codable {
    let id: UUID
    let title: String
    let filePath: String?
    let bookmarkData: Data?
    let fileModificationDate: Date?
    let fileSize: Int?
    let fileNumber: UInt64?
    let systemNumber: UInt64?
    let currentTypeIdentifier: String
    let modeName: String
    let codeLanguageName: String
    let screenplayElementName: String
    let isDirty: Bool
    let selectionLocation: Int
    let selectionLength: Int
    let visibleOriginX: Double
    let visibleOriginY: Double
    let archive: MongrelDocumentArchive

    var authoringMode: AuthoringMode {
        AuthoringMode(rawValue: modeName) ?? .prose
    }

    var codeLanguage: CodeLanguage {
        CodeLanguage(rawValue: codeLanguageName) ?? .swift
    }

    var screenplayElement: ScreenplayElement {
        ScreenplayElement(rawValue: screenplayElementName) ?? .action
    }

    var editorLocation: EditorLocationSnapshot {
        EditorLocationSnapshot(
            selection: NSRange(
                location: max(0, selectionLocation),
                length: max(0, selectionLength)
            ),
            visibleOrigin: NSPoint(
                x: max(0, visibleOriginX),
                y: max(0, visibleOriginY)
            )
        )
    }

    init(tab: DocumentWorkspaceTab, state: DocumentWorkspaceTabState, cachedArchive: MongrelDocumentArchive? = nil) throws {
        id = tab.id
        title = state.title
        filePath = state.currentURL?.path
        if let url = state.currentURL {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            bookmarkData = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } else {
            bookmarkData = nil
        }
        fileModificationDate = state.diskVersion?.modificationDate
        fileSize = state.diskVersion?.fileSize
        fileNumber = state.diskVersion?.fileNumber
        systemNumber = state.diskVersion?.systemNumber
        currentTypeIdentifier = state.currentType.identifier
        modeName = state.authoringMode.rawValue
        codeLanguageName = state.codeLanguage.rawValue
        screenplayElementName = state.screenplayElement.rawValue
        isDirty = state.hasUnsavedChanges
        selectionLocation = state.editorLocation.selection.location
        selectionLength = state.editorLocation.selection.length
        visibleOriginX = Double(state.editorLocation.visibleOrigin.x)
        visibleOriginY = Double(state.editorLocation.visibleOrigin.y)
        archive = try cachedArchive ?? MongrelDocumentArchive(
            attributedText: state.attributedText,
            authoringMode: state.authoringMode,
            codeLanguage: state.authoringMode == .code ? state.codeLanguage : nil,
            pageLayout: state.pageLayout,
            documentTitle: state.title,
            screenplaySettings: state.screenplaySettings
        )
    }

    func resolveURL() -> URL? {
        if let bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withoutUI, .withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        return filePath.map { URL(fileURLWithPath: $0) }
    }

    func matchesDiskVersion(at url: URL) -> Bool {
        guard let current = DocumentDiskVersion.capture(at: url) else { return false }
        if let fileModificationDate,
           current.modificationDate != fileModificationDate {
            return false
        }
        if let fileSize, current.fileSize != fileSize {
            return false
        }
        if let fileNumber, current.fileNumber != fileNumber {
            return false
        }
        if let systemNumber, current.systemNumber != systemNumber {
            return false
        }
        return fileModificationDate != nil
            || fileSize != nil
            || fileNumber != nil
            || systemNumber != nil
    }
}

enum WorkspaceRecoveryError: Error {
    case duplicateDocument
    case missingTabState
    case oversizedManifest
    case unsupportedManifest
}

final class WordProcessorWorkspaceRecoveryStore {
    private static let maximumManifestSize = 256 * 1_024 * 1_024

    private let directory: URL
    private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            self.directory = applicationSupport
                .appendingPathComponent("MongrelWordProcessor", isDirectory: true)
        }
    }

    private var manifestURL: URL {
        directory.appendingPathComponent("WorkspaceRecovery.json")
    }

    func load() throws -> Data? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let resourceValues = try manifestURL.resourceValues(forKeys: [.fileSizeKey])
        guard (resourceValues.fileSize ?? 0) <= Self.maximumManifestSize else {
            throw WorkspaceRecoveryError.oversizedManifest
        }
        return try Data(contentsOf: manifestURL, options: .mappedIfSafe)
    }

    func save(_ data: Data) throws {
        guard data.count <= Self.maximumManifestSize else {
            throw WorkspaceRecoveryError.oversizedManifest
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: manifestURL, options: [.atomic, .completeFileProtection])
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        try fileManager.removeItem(at: manifestURL)
    }

    func quarantine() throws {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let destination = directory.appendingPathComponent(
            "WorkspaceRecovery-corrupt-\(timestamp)-\(UUID().uuidString).json"
        )
        try fileManager.moveItem(at: manifestURL, to: destination)
    }
}


struct WorkspaceRecoveryWrite: @unchecked Sendable {
    let manifest: WorkspaceRecoveryManifest
    let store: WordProcessorWorkspaceRecoveryStore
    let logger: WordProcessorAuditLogger

    func perform() {
        do {
            try store.save(JSONEncoder().encode(manifest))
            logger.info("workspace_recovery_saved", metadata: ["tabs": manifest.tabs.count])
        } catch {
            logger.error("workspace_recovery_save_failed", error: error)
        }
    }
}

/// A slow disk must not leave a queue retaining every intermediate workspace.
/// Keep the running write plus the newest pending snapshot, then drain on flush.
final class CoalescingWorkspaceRecoveryWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mongrel.wordprocessor.recovery", qos: .utility)
    private let lock = NSLock()
    private var latest: (@Sendable () -> Void)?
    private var isDraining = false

    func enqueue(_ operation: @escaping @Sendable () -> Void) {
        lock.lock()
        latest = operation
        let needsDrain = !isDraining
        isDraining = true
        lock.unlock()
        if needsDrain { queue.async { self.drain() } }
    }

    func flush() {
        queue.sync {}
    }

    private func drain() {
        while true {
            lock.lock()
            let operation = latest
            latest = nil
            if operation == nil { isDraining = false }
            lock.unlock()
            guard let operation else { return }
            operation()
        }
    }
}
