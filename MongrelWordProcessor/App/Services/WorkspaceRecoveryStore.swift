import AppKit
import Foundation

struct WorkspaceRecoveryManifest: Codable {
    static let currentVersion = 1
    static let maximumTabCount = 50

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

    init(tab: DocumentWorkspaceTab, state: DocumentWorkspaceTabState) throws {
        id = tab.id
        title = state.title
        filePath = state.currentURL?.path
        bookmarkData = try? state.currentURL?.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let resourceValues = try? state.currentURL?.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        fileModificationDate = resourceValues?.contentModificationDate
        fileSize = resourceValues?.fileSize
        currentTypeIdentifier = state.currentType.identifier
        modeName = state.authoringMode.rawValue
        codeLanguageName = state.codeLanguage.rawValue
        screenplayElementName = state.screenplayElement.rawValue
        isDirty = state.hasUnsavedChanges
        selectionLocation = state.editorLocation.selection.location
        selectionLength = state.editorLocation.selection.length
        visibleOriginX = Double(state.editorLocation.visibleOrigin.x)
        visibleOriginY = Double(state.editorLocation.visibleOrigin.y)
        archive = try MongrelDocumentArchive(
            attributedText: state.attributedText,
            authoringMode: state.authoringMode,
            codeLanguage: state.authoringMode == .code ? state.codeLanguage : nil,
            pageLayout: state.pageLayout
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
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ]) else { return false }
        if let fileModificationDate,
           values.contentModificationDate != fileModificationDate {
            return false
        }
        if let fileSize, values.fileSize != fileSize {
            return false
        }
        return fileModificationDate != nil || fileSize != nil
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
