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

struct DocumentRGBColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    private enum CodingKeys: String, CodingKey {
        case red
        case green
        case blue
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            red: try container.decode(Double.self, forKey: .red),
            green: try container.decode(Double.self, forKey: .green),
            blue: try container.decode(Double.self, forKey: .blue)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

struct DocumentPageColorPair: Equatable {
    let background: DocumentRGBColor
    let text: DocumentRGBColor

    var contrastRatio: Double {
        let lighter = max(background.relativeLuminance, text.relativeLuminance)
        let darker = min(background.relativeLuminance, text.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

enum DocumentPagePalette: String, Codable, CaseIterable, Identifiable {
    case warmPaper
    case cleanWhite
    case sepia
    case midnight
    case slate
    case forest
    case contrast
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warmPaper: return "Warm Paper"
        case .cleanWhite: return "Clean White"
        case .sepia: return "Sepia"
        case .midnight: return "Midnight"
        case .slate: return "Slate"
        case .forest: return "Forest"
        case .contrast: return "Contrast"
        case .custom: return "Custom"
        }
    }

    func colors(customBackground: DocumentRGBColor, customText: DocumentRGBColor) -> DocumentPageColorPair {
        switch self {
        case .warmPaper:
            return DocumentPageColorPair(background: .init(hex: 0xF8F2E3), text: .init(hex: 0x181612))
        case .cleanWhite:
            return DocumentPageColorPair(background: .init(hex: 0xFAFAF9), text: .init(hex: 0x16181B))
        case .sepia:
            return DocumentPageColorPair(background: .init(hex: 0xEBDAB5), text: .init(hex: 0x3A2618))
        case .midnight:
            return DocumentPageColorPair(background: .init(hex: 0x081120), text: .init(hex: 0xEAF2FF))
        case .slate:
            return DocumentPageColorPair(background: .init(hex: 0x1C242B), text: .init(hex: 0xF0F6F8))
        case .forest:
            return DocumentPageColorPair(background: .init(hex: 0x0F2B20), text: .init(hex: 0xF1EDD3))
        case .contrast:
            return DocumentPageColorPair(background: .init(hex: 0x000000), text: .init(hex: 0xFFFFFF))
        case .custom:
            return DocumentPageColorPair(background: customBackground, text: customText)
        }
    }
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
    var palette: DocumentPagePalette = .warmPaper
    var customPageBackground = DocumentRGBColor(hex: 0x121820)
    var customPageText = DocumentRGBColor(hex: 0xF2F5F7)

    private enum CodingKeys: String, CodingKey {
        case header
        case footer
        case showsOnFirstPage
        case palette
        case customPageBackground
        case customPageText
    }

    init(
        header: DocumentPageBand = DocumentPageBand(text: "{title}"),
        footer: DocumentPageBand = DocumentPageBand(alignment: .center, includesPageNumber: true),
        showsOnFirstPage: Bool = true,
        palette: DocumentPagePalette = .warmPaper,
        customPageBackground: DocumentRGBColor = DocumentRGBColor(hex: 0x121820),
        customPageText: DocumentRGBColor = DocumentRGBColor(hex: 0xF2F5F7)
    ) {
        self.header = header
        self.footer = footer
        self.showsOnFirstPage = showsOnFirstPage
        self.palette = palette
        self.customPageBackground = customPageBackground
        self.customPageText = customPageText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        header = try container.decodeIfPresent(DocumentPageBand.self, forKey: .header)
            ?? DocumentPageBand(text: "{title}")
        footer = try container.decodeIfPresent(DocumentPageBand.self, forKey: .footer)
            ?? DocumentPageBand(alignment: .center, includesPageNumber: true)
        showsOnFirstPage = try container.decodeIfPresent(Bool.self, forKey: .showsOnFirstPage) ?? true
        let paletteName = try container.decodeIfPresent(String.self, forKey: .palette)
        palette = paletteName.flatMap(DocumentPagePalette.init(rawValue:)) ?? .warmPaper
        customPageBackground = try container.decodeIfPresent(DocumentRGBColor.self, forKey: .customPageBackground)
            ?? DocumentRGBColor(hex: 0x121820)
        customPageText = try container.decodeIfPresent(DocumentRGBColor.self, forKey: .customPageText)
            ?? DocumentRGBColor(hex: 0xF2F5F7)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(header, forKey: .header)
        try container.encode(footer, forKey: .footer)
        try container.encode(showsOnFirstPage, forKey: .showsOnFirstPage)
        try container.encode(palette.rawValue, forKey: .palette)
        try container.encode(customPageBackground, forKey: .customPageBackground)
        try container.encode(customPageText, forKey: .customPageText)
    }

    var pageColors: DocumentPageColorPair {
        palette.colors(customBackground: customPageBackground, customText: customPageText)
    }

    var hasRenderableContent: Bool {
        header.hasRenderableContent || footer.hasRenderableContent
    }

    var hasNativeOnlyFeatures: Bool {
        hasRenderableContent || palette != .warmPaper
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
