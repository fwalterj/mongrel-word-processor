import AppKit
import Combine
import SwiftUI
import SharedFoundation

@main
struct MongrelWordProcessorApp: App {
    @StateObject private var session = DocumentSession()

    var body: some Scene {
        WindowGroup {
            WordProcessorContentView()
                .environmentObject(session)
                .mongrelAppearance()
                .frame(minWidth: 980, minHeight: 680)
                .onOpenURL { url in
                    session.openExternalDocument(at: url)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    session.flushWorkspaceRecovery()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    session.flushWorkspaceRecovery()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 860)
        .commands {
            WordProcessorCommands(session: session)
        }

        Settings {
            MongrelAppearanceSettingsView()
        }
    }
}

private struct WordProcessorCommands: Commands {
    @ObservedObject var session: DocumentSession
    @FocusedValue(\.wordProcessorFocusMode) private var focusMode

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Document") {
                session.newDocument()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Screenplay") {
                session.newScreenplay()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Source File") {
                session.newCodeDocument()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

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

            Menu("Save As Type") {
                Button("Mongrel Document (.mongreldoc)") {
                    session.saveDocumentAs(preferredType: .mongrelDocument)
                }

                Button("Rich Text (.rtf)") {
                    session.saveDocumentAs(preferredType: .rtf)
                }

                Button("Rich Text with Attachments (.rtfd)") {
                    session.saveDocumentAs(preferredType: .rtfd)
                }

                Button("Microsoft Word (.docx)") {
                    session.saveDocumentAs(preferredType: .wordDocument)
                }

                Button("Plain Text (.txt)") {
                    session.saveDocumentAs(preferredType: .plainText)
                }

                Button("\(session.codeLanguage.title) Source (.\(session.codeLanguage.preferredFilenameExtension))") {
                    session.saveDocumentAs(preferredType: session.codeLanguage.contentType)
                }
                .disabled(session.authoringMode != .code)

                Button("Mongrel Screenplay (.mgscreenplay)") {
                    session.saveDocumentAs(preferredType: .mongrelScreenplay)
                }
                .disabled(session.authoringMode != .screenplay)
            }

            Button("Save a Copy...") {
                session.saveDocumentCopyAs()
            }

            Divider()

            Button("Clear Recent Documents") {
                session.clearRecentDocuments()
            }
            .disabled(session.recentDocuments.isEmpty)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                session.printDocument()
            }
            .keyboardShortcut("p", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button(focusMode?.wrappedValue == true ? "Exit Focus Mode" : "Enter Focus Mode") {
                focusMode?.wrappedValue.toggle()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(focusMode == nil)
        }

        CommandMenu("Workspace") {
            Button("Next Tab") {
                session.selectAdjacentTab(offset: 1)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled(session.workspaceTabs.count < 2)

            Button("Previous Tab") {
                session.selectAdjacentTab(offset: -1)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled(session.workspaceTabs.count < 2)

            Button("Reopen Closed Tab") {
                session.reopenClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(!session.canReopenClosedTab)

            Button("Duplicate Current Tab") {
                if let activeTabID = session.activeTabID {
                    session.duplicateTab(activeTabID)
                }
            }

            Divider()

            Toggle("Autosave Named Tabs on Switch", isOn: $session.autosaveOnTabSwitch)
        }

        CommandMenu("Writing") {
            Button("Auto Format Screenplay") {
                session.formattingBridge.autoFormatEntireScreenplay()
            }
            .disabled(session.authoringMode != .screenplay)

            Divider()

            Button("Check Spelling and Grammar") {
                session.formattingBridge.checkSpelling()
            }

            Button("Show Fonts") {
                session.showFontPanel()
            }

            Button("Install Font Files...") {
                session.installFontFiles()
            }

            Button("Insert Image...") {
                session.formattingBridge.insertImageAttachment()
            }
            .disabled(session.authoringMode == .code)

            Divider()

            Button(session.typewriterMode ? "Disable Typewriter Scrolling" : "Enable Typewriter Scrolling") {
                session.typewriterMode.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])

            Divider()

            Button("Zoom In") {
                session.adjustEditorZoom(by: 0.1)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(session.editorZoom >= 2)

            Button("Zoom Out") {
                session.adjustEditorZoom(by: -0.1)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(session.editorZoom <= 0.6)

            Button("Actual Size") {
                session.resetEditorZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Screenplay") {
            Button("Paste and Parse Screenplay") {
                session.formattingBridge.pasteAndParseScreenplay()
            }
            .disabled(session.authoringMode != .screenplay)

            Divider()

            Button("Previous Scene") {
                session.selectAdjacentScene(offset: -1)
            }
            .keyboardShortcut(.upArrow, modifiers: .control)
            .disabled(session.authoringMode != .screenplay || session.screenplayScenes.isEmpty)

            Button("Next Scene") {
                session.selectAdjacentScene(offset: 1)
            }
            .keyboardShortcut(.downArrow, modifiers: .control)
            .disabled(session.authoringMode != .screenplay || session.screenplayScenes.isEmpty)

            Divider()

            Menu("Set Element") {
                screenplayElementButton(.sceneHeading, shortcut: "1")
                screenplayElementButton(.action, shortcut: "2")
                screenplayElementButton(.character, shortcut: "3")
                screenplayElementButton(.dialogue, shortcut: "4")
                screenplayElementButton(.parenthetical, shortcut: "5")
                screenplayElementButton(.transition, shortcut: "6")
                screenplayElementButton(.shot, shortcut: "7")
                screenplayElementButton(.insert, shortcut: "8")
                screenplayElementButton(.titleCard, shortcut: "9")
                screenplayElementButton(.timeJump, shortcut: "0")
            }
            .disabled(session.authoringMode != .screenplay)
        }

        CommandMenu("Coding") {
            Button("Toggle Line Comment") {
                session.toggleCodeComment()
            }
            .keyboardShortcut("/", modifiers: .command)
            .disabled(session.authoringMode != .code || session.codeLanguage.lineCommentPrefix == nil)

            Button("Duplicate Line or Selection") {
                session.duplicateCodeLines()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(session.authoringMode != .code)
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

            Button("Export RTFD with Attachments") {
                session.exportAsRTFD()
            }

            Button("Export Microsoft Word") {
                session.exportAsWordDocument()
            }
        }
    }

    private func screenplayElementButton(_ element: ScreenplayElement, shortcut: KeyEquivalent) -> some View {
        Button(element.title) {
            session.screenplayElement = element
            session.formattingBridge.applyScreenplayElement(element)
        }
        .keyboardShortcut(shortcut, modifiers: .control)
    }
}
