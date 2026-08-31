import AppKit
import Foundation
import UniformTypeIdentifiers

enum PageBandAlignment: String, Codable, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }

    var textAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

enum PageBandLocation: String, CaseIterable, Identifiable {
    case header
    case footer

    var id: String { rawValue }
}

struct DocumentPageImage: Codable, Equatable {
    let data: Data
    let contentTypeIdentifier: String
    let filename: String

    var image: NSImage? { NSImage(data: data) }

    var isSupported: Bool {
        guard !data.isEmpty,
              data.count <= DocumentImageSupport.maximumFileSize,
              image != nil,
              let contentType = UTType(contentTypeIdentifier) else { return false }
        return DocumentImageSupport.contentTypes.contains {
            contentType == $0 || contentType.conforms(to: $0)
        }
    }
}

struct DocumentPageBand: Codable, Equatable {
    var isEnabled = false
    var text = ""
    var alignment: PageBandAlignment = .leading
    var includesPageNumber = false
    var image: DocumentPageImage?

    var hasRenderableContent: Bool {
        isEnabled && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || includesPageNumber || image != nil)
    }
}

struct DocumentPageLayout: Codable, Equatable {
    var header = DocumentPageBand(text: "{title}")
    var footer = DocumentPageBand(alignment: .center, includesPageNumber: true)
    var showsOnFirstPage = true

    var hasRenderableContent: Bool {
        header.hasRenderableContent || footer.hasRenderableContent
    }

    static let empty = DocumentPageLayout()

    var sanitized: DocumentPageLayout {
        var copy = self
        if copy.header.image?.isSupported != true {
            copy.header.image = nil
        }
        if copy.footer.image?.isSupported != true {
            copy.footer.image = nil
        }
        return copy
    }

    func resolvedText(
        for band: DocumentPageBand,
        title: String,
        pageNumber: Int,
        pageCount: Int,
        date: Date = Date()
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        var value = band.text
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{page}", with: "\(pageNumber)")
            .replacingOccurrences(of: "{pages}", with: "\(pageCount)")
            .replacingOccurrences(of: "{date}", with: formatter.string(from: date))

        if band.includesPageNumber && !band.text.contains("{page}") {
            let pageLabel = "\(pageNumber) of \(pageCount)"
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.isEmpty ? pageLabel : "\(value)  |  \(pageLabel)"
        }
        return value
    }
}

enum DocumentImageSupport {
    static let contentTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .pdf]
    static let maximumFileSize = 20 * 1_024 * 1_024

    static func loadPageImage(from url: URL) throws -> DocumentPageImage {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard !data.isEmpty, data.count <= maximumFileSize else {
            throw CocoaError(.fileReadTooLarge)
        }
        guard NSImage(data: data) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let contentType = UTType(filenameExtension: url.pathExtension) ?? .data
        guard contentTypes.contains(where: { contentType.conforms(to: $0) || contentType == $0 }) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return DocumentPageImage(
            data: data,
            contentTypeIdentifier: contentType.identifier,
            filename: url.lastPathComponent
        )
    }
}
