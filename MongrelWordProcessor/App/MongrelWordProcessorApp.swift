import SwiftUI

@main
struct MongrelWordProcessorApp: App {
    @StateObject private var session = DocumentSession()

    var body: some Scene {
        WindowGroup {
            WordProcessorContentView()
                .environmentObject(session)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 860)
        .commands {
            WordProcessorCommands(session: session)
        }
    }
}

private struct WordProcessorCommands: Commands {
    @ObservedObject var session: DocumentSession

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") {
                session.newDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Open...") {
                session.openDocument()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Reopen Last Document") {
                session.reopenLastDocument()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(!session.hasRestorableLastDocument)

            Button("Close Document") {
                session.closeDocument()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(!session.canCloseDocument)

            Button("Save") {
                session.saveDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!session.canSaveDocument)

            Button("Save As...") {
                session.saveDocumentAs()
            }
            .keyboardShortcut("S", modifiers: [.command, .shift])
        }

        CommandMenu("Export") {
            Button("Export PDF") {
                session.exportAsPDF()
            }

            Button("Export Plain Text") {
                session.exportAsPlainText()
            }

            Button("Export RTF") {
                session.exportAsRTF()
            }
        }
    }
}
