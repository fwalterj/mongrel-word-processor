import AppKit
import CoreText
import UniformTypeIdentifiers

enum ManagedFontLibrary {
    static let supportedContentTypes: [UTType] = [
        UTType(filenameExtension: "ttf"),
        UTType(filenameExtension: "otf")
    ].compactMap { $0 }

    static func registerInstalledFonts() {
        guard let directory = try? managedFontsDirectory(createIfNeeded: false),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return }

        for url in files where supportedContentTypes.contains(where: { $0 == UTType(filenameExtension: url.pathExtension) }) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    @MainActor
    static func installFontFiles() throws -> Int {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = supportedContentTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose licensed TrueType or OpenType font files. Mongrel keeps a private copy for this app."

        guard panel.runModal() == .OK else { return 0 }
        let destinationDirectory = try managedFontsDirectory(createIfNeeded: true)
        var installedCount = 0

        for sourceURL in panel.urls {
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                CTFontManagerUnregisterFontsForURL(destinationURL as CFURL, .process, nil)
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

            var registrationError: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(
                destinationURL as CFURL,
                .process,
                &registrationError
            )
            if !registered, let error = registrationError?.takeRetainedValue() {
                try? FileManager.default.removeItem(at: destinationURL)
                throw error
            }
            installedCount += 1
        }

        return installedCount
    }

    private static func managedFontsDirectory(createIfNeeded: Bool) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        )
        let directory = applicationSupport
            .appendingPathComponent("MongrelWordProcessor", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)

        if createIfNeeded {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}
