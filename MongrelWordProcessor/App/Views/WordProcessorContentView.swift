import SwiftUI
import SharedFoundation

struct WordProcessorContentView: View {
    @EnvironmentObject private var session: DocumentSession
    @State private var showShortcutHelp: Bool = false
    @State private var showCommandPalette: Bool = false
    @State private var commandQuery: String = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
        .background(DesignTokens.glassDeep.ignoresSafeArea())
        .sheet(isPresented: $showCommandPalette) {
            WordProcessorCommandPaletteView(query: $commandQuery, onRunAction: runCommandPaletteAction)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Word Processor")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText)
                Text("Draft vault")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().overlay(DesignTokens.borderRim)

            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Documents")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.58))
                    .textCase(.uppercase)

                if session.recentDocuments.isEmpty {
                    Text("No recent files")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
                } else {
                    ForEach(session.recentDocuments) { recent in
                        Button {
                            session.openRecentDocument(recent)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recent.title)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                                    .foregroundStyle(DesignTokens.chromeText)
                                HStack(spacing: 4) {
                                    Text(URL(fileURLWithPath: recent.path).lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(recent.relativeDate)
                                }
                                .font(.system(size: 10))
                                .foregroundStyle(DesignTokens.chromeText.opacity(0.42))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(DesignTokens.glassCard.opacity(0.8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(DesignTokens.borderRim, lineWidth: 0.5)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Document Stats")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.58))
                    .textCase(.uppercase)

                statLine("Words", value: "\(session.wordCount)")
                statLine("Characters", value: "\(session.charCount)")
                statLine("Spellcheck", value: session.companionSpellcheckDetail)
                if session.authoringMode == .screenplay {
                    statLine("Pages", value: "\(session.screenplayPageCount)")
                    statLine("Scenes", value: "\(session.screenplaySceneCount)")
                }
                statLine("State", value: session.hasUnsavedChanges ? "Unsaved" : "Saved")
            }
            .padding(12)
            .glassChromeBackground(style: .card, cornerRadius: 0)
        }
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
        .glassChromeBackground(style: .deep, cornerRadius: 0)
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            topChrome
            Divider().overlay(DesignTokens.borderRim)
            formattingToolbar
            Divider().overlay(DesignTokens.borderRim)
            editorArea
            Divider().overlay(DesignTokens.borderRim)
            statusBar
        }
        .background(DesignTokens.glassDeep)
    }

    private var topChrome: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(DesignTokens.accent)

            TextField("Document title", text: $session.title)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.glassCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignTokens.borderRim, lineWidth: 1)
                )

            if session.hasUnsavedChanges {
                Text("Unsaved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignTokens.accent.opacity(0.12), in: Capsule())
            }

            Spacer()

            Button("New") {
                session.newDocument()
            }
            .buttonStyle(.plain)
            .controlSize(.small)

            Button("Open") {
                session.openDocument()
            }
            .buttonStyle(.plain)
            .controlSize(.small)

            Button("Close") {
                session.closeDocument()
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .disabled(!session.canCloseDocument)

            Button("Save") {
                session.saveDocument()
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .disabled(!session.canSaveDocument)

            Menu {
                ForEach(AuthoringMode.allCases, id: \.rawValue) { mode in
                    Button(mode.title) {
                        session.authoringMode = mode
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.split.2x2")
                    Text("Mode: \(session.authoringMode.title)")
                }
                .foregroundStyle(DesignTokens.chromeText.opacity(0.9))
            }
            .menuStyle(.borderlessButton)

            if session.authoringMode == .code {
                Menu {
                    ForEach(CodeLanguage.allCases, id: \.rawValue) { language in
                        Button(language.title) {
                            session.codeLanguage = language
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text(session.codeLanguage.title)
                    }
                    .foregroundStyle(DesignTokens.accent)
                }
                .menuStyle(.borderlessButton)

                Menu {
                    ForEach(CodeTheme.allCases, id: \.rawValue) { theme in
                        Button(theme.title) {
                            session.codeTheme = theme
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette")
                        Text(session.codeTheme.title)
                    }
                    .foregroundStyle(DesignTokens.accent)
                }
                .menuStyle(.borderlessButton)

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)

                Button(session.codeUseTabs ? "Tabs" : "Spaces") {
                    session.codeUseTabs.toggle()
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.85))

                Menu {
                    ForEach([2, 4, 8], id: \.self) { w in
                        Button("\(w)") { session.codeTabWidth = w }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "ruler")
                        Text("\(session.codeTabWidth)")
                    }
                    .foregroundStyle(DesignTokens.accent)
                }
                .menuStyle(.borderlessButton)

                Button(session.codeLineWrap ? "Wrap: On" : "Wrap: Off") {
                    session.codeLineWrap.toggle()
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.85))
            } else if session.authoringMode == .screenplay {
                Text("Letter layout")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.68))

                Menu {
                    ForEach(ScreenplayElement.allCases, id: \.rawValue) { element in
                        Button(element.title) {
                            session.screenplayElement = element
                            session.formattingBridge.applyScreenplayElement(element)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "film")
                        Text(session.screenplayElement.shortTitle)
                    }
                    .foregroundStyle(DesignTokens.accent)
                }
                .menuStyle(.borderlessButton)
            }

            Menu {
                Button("Export as PDF...") {
                    session.exportAsPDF()
                }
                Button("Export as RTF...") {
                    session.exportAsRTF()
                }
                Button("Export as Plain Text...") {
                    session.exportAsPlainText()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
                .foregroundStyle(DesignTokens.accent)
            }
            .menuStyle(.borderlessButton)

            Button {
                showCommandPalette = true
            } label: {
                Image(systemName: "command.square")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("k", modifiers: .command)

            Button {
                showShortcutHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showShortcutHelp, arrowEdge: .top) {
                shortcutHelp
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassChromeBackground(style: .elevated, cornerRadius: 0)
    }

    private var formattingToolbar: some View {
        HStack(spacing: 6) {
            if session.authoringMode == .screenplay {
                screenplayToolbar
            } else {
                proseAndCodeToolbar
            }

            Spacer()

            Button("Reopen Last") {
                session.reopenLastDocument()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.accent)
            .disabled(!session.hasRestorableLastDocument)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(DesignTokens.chromeText)
        .glassChromeBackground(style: .card, cornerRadius: 0)
    }

    private var proseAndCodeToolbar: some View {
        Group {
            formatButton("B", isActive: session.formattingBridge.isBold)        { session.formattingBridge.bold() }
            formatButton("I", isActive: session.formattingBridge.isItalic)      { session.formattingBridge.italic() }
            formatButton("U", isActive: session.formattingBridge.isUnderline)   { session.formattingBridge.underline() }
            formatButton("S", isActive: session.formattingBridge.isStrikethrough) { session.formattingBridge.strikethrough() }

            Divider().frame(height: 14)

            formatButton("H1") { session.formattingBridge.applyHeading(1) }
            formatButton("H2") { session.formattingBridge.applyHeading(2) }
            formatButton("H3") { session.formattingBridge.applyHeading(3) }

            Divider().frame(height: 14)

            iconButton("text.alignleft") { session.formattingBridge.alignLeft() }
            iconButton("text.aligncenter") { session.formattingBridge.alignCenter() }
            iconButton("text.alignright") { session.formattingBridge.alignRight() }

            Divider().frame(height: 14)

            iconButton("textformat.size.smaller") { session.formattingBridge.decreaseFontSize() }
            iconButton("textformat.size.larger") { session.formattingBridge.increaseFontSize() }
        }
    }

    private var screenplayToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(ScreenplayElement.allCases, id: \.rawValue) { element in
                    formatButton(
                        element.toolbarLabel,
                        isActive: session.screenplayElement == element
                    ) {
                        session.screenplayElement = element
                        session.formattingBridge.applyScreenplayElement(element)
                    }
                }

                Divider().frame(height: 14)

                Text("Tab cycles elements")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.62))
            }

            if !session.formattingBridge.screenplaySuggestions.isEmpty {
                screenplaySuggestionStrip
            }
        }
    }

    private var screenplaySuggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Suggestions")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.48))
                    .textCase(.uppercase)

                ForEach(session.formattingBridge.screenplaySuggestions.prefix(8)) { suggestion in
                    Button {
                        session.formattingBridge.applySuggestion(suggestion)
                    } label: {
                        Text(suggestion.label)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignTokens.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(DesignTokens.glassHotSpot.opacity(0.28))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(DesignTokens.borderRim, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var editorArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.authoringMode == .screenplay {
                screenplayEditorCanvas
            } else {
                coreEditor
                    .background(selectedEditorBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DesignTokens.borderRim, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [DesignTokens.glassDeep, DesignTokens.glassBase],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var screenplayPageSummary: String {
        "\(session.screenplayPageCount) page\(session.screenplayPageCount == 1 ? "" : "s")"
    }

    private var screenplaySceneSummary: String {
        "\(session.screenplaySceneCount) scene\(session.screenplaySceneCount == 1 ? "" : "s")"
    }

    private var coreEditor: some View {
        TextKit2EditorView(
            attributedText: $session.attributedText,
            onEdit: {
                session.markDirty()
            },
            onScreenplayElementChange: { element in
                session.screenplayElement = element
            },
            onPaginationChange: { count in
                session.updateRenderedScreenplayPageCount(count)
            },
            bridge: session.formattingBridge,
            companionLexicon: session.companionLexicon,
            authoringMode: session.authoringMode,
            screenplayElement: session.screenplayElement,
            codeLanguage: session.codeLanguage,
            codeTheme: session.codeTheme,
            codeUseTabs: session.codeUseTabs,
            codeTabWidth: session.codeTabWidth,
            codeLineWrap: session.codeLineWrap
        )
    }

    private var screenplayEditorCanvas: some View {
        HStack {
            Spacer(minLength: 28)
            VStack(spacing: 0) {
                HStack {
                    Text("US Letter")
                    Spacer()
                    Text(screenplayPageSummary)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.45))
                .padding(.horizontal, 20)
                .padding(.top, 16)

                coreEditor
                    .frame(width: ScreenplayPageLayout.pageSize.width)
                    .frame(height: ScreenplayPageLayout.pageSize.height)
                    .background(selectedEditorBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .frame(width: ScreenplayPageLayout.pageSize.width)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.97))
                    .shadow(color: Color.black.opacity(0.08), radius: 28, x: 0, y: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            Spacer(minLength: 28)
        }
        .padding(.vertical, 18)
    }

    private var statusBar: some View {
        HStack {
            Text("\(session.wordCount) words")
            Text("·")
            Text("\(session.charCount) characters")
            Text("·")
            Text(session.authoringMode.title)
            Text("·")
            Text(session.companionSpellcheckSummary)
            if session.authoringMode == .screenplay {
                Text("·")
                Text(screenplayPageSummary)
                Text("·")
                Text(screenplaySceneSummary)
                Text("·")
                Text(session.screenplayElement.shortTitle)
            }
            Spacer()
            if let url = session.currentURL {
                Text(url.lastPathComponent)
                    .lineLimit(1)
            } else {
                Text("Untitled")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(DesignTokens.chromeText.opacity(0.62))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassChromeBackground(style: .deep, cornerRadius: 0)
    }

    private func statLine(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.48))
            Spacer()
            Text(value)
                .foregroundStyle(DesignTokens.chromeText)
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
    }

    private func formatButton(_ title: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(minWidth: 22)
                .foregroundStyle(isActive ? DesignTokens.accent : DesignTokens.chromeText)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? DesignTokens.accent.opacity(0.18) : DesignTokens.glassElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isActive ? DesignTokens.accent.opacity(0.55) : DesignTokens.borderRim, lineWidth: 0.5)
                )
        )
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignTokens.glassElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DesignTokens.borderRim, lineWidth: 0.5)
                )
        )
    }

    private var selectedEditorBackground: some View {
        ZStack {
            if session.authoringMode == .code {
                codeBackground.0
                LinearGradient(
                    colors: [codeBackground.1.opacity(0.42), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if session.authoringMode == .screenplay {
                Color(red: 0.97, green: 0.95, blue: 0.89)
                LinearGradient(
                    colors: [Color(red: 0.84, green: 0.78, blue: 0.62).opacity(0.22), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                DesignTokens.glassCard
                LinearGradient(
                    colors: [DesignTokens.glassHotSpot.opacity(0.24), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var codeBackground: (Color, Color) {
        switch session.codeTheme {
        case .cobalt:
            return (Color(red: 0.09, green: 0.11, blue: 0.14), Color(red: 0.20, green: 0.31, blue: 0.42))
        case .frost:
            return (Color(red: 0.07, green: 0.12, blue: 0.14), Color(red: 0.16, green: 0.39, blue: 0.45))
        case .amber:
            return (Color(red: 0.13, green: 0.10, blue: 0.08), Color(red: 0.42, green: 0.28, blue: 0.14))
        }
    }

    private var shortcutHelp: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Word Processor Shortcuts")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText)

            shortcutSection(
                "File",
                items: [
                    ("Cmd + O", "Open document"),
                    ("Cmd + S", "Save document"),
                    ("Cmd + Shift + S", "Save As"),
                    ("Cmd + K", "Command palette")
                ]
            )

            shortcutSection(
                "Editing",
                items: [
                    ("Cmd + B / I / U", "Bold / italic / underline"),
                    ("Cmd + Z", "Undo"),
                    ("Cmd + Shift + Z", "Redo")
                ]
            )

            shortcutSection(
                "Code Mode",
                items: [
                    ("Mode: Code", "Monospace + syntax color"),
                    ("Language Menu", "Swift/JS/Python/JSON presets"),
                    ("Theme Menu", "Cobalt/Frost/Amber themes"),
                    ("Esc", "Dismiss completion popup"),
                    ("Tab/Enter", "Accept completion")
                ]
            )

            shortcutSection(
                "Screenplay",
                items: [
                    ("Mode: Screenplay", "Courier-style script formatting"),
                    ("Tab / Shift + Tab", "Cycle screenplay elements"),
                    ("Return", "Advance to the next likely element")
                ]
            )
        }
        .padding(16)
        .frame(width: 320)
        .glassChromeBackground(style: .deep, cornerRadius: 14)
    }

    private func shortcutSection(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.55))
                .textCase(.uppercase)

            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline) {
                    Text(item.0)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignTokens.accent.opacity(0.95))
                        .frame(width: 140, alignment: .leading)

                    Text(item.1)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.84))
                }
            }
        }
    }

    private func runCommandPaletteAction(_ action: WordProcessorPaletteAction) {
        switch action {
        case .newDocument:
            session.newDocument()
        case .openDocument:
            session.openDocument()
        case .saveDocument:
            session.saveDocument()
        case .setMode(let mode):
            session.authoringMode = mode
        case .setScreenplayElement(let element):
            session.authoringMode = .screenplay
            session.screenplayElement = element
            session.formattingBridge.applyScreenplayElement(element)
        case .setLanguage(let language):
            session.authoringMode = .code
            session.codeLanguage = language
        case .setTheme(let theme):
            session.authoringMode = .code
            session.codeTheme = theme
        }
    }
}

private enum WordProcessorPaletteAction: Hashable {
    case newDocument
    case openDocument
    case saveDocument
    case setMode(AuthoringMode)
    case setScreenplayElement(ScreenplayElement)
    case setLanguage(CodeLanguage)
    case setTheme(CodeTheme)

    var title: String {
        switch self {
        case .newDocument: return "New Document"
        case .openDocument: return "Open Document"
        case .saveDocument: return "Save Document"
        case .setMode(let mode): return "Authoring Mode: \(mode.title)"
        case .setScreenplayElement(let element): return "Screenplay Element: \(element.title)"
        case .setLanguage(let language): return "Code Language: \(language.title)"
        case .setTheme(let theme): return "Code Theme: \(theme.title)"
        }
    }

    var symbol: String {
        switch self {
        case .newDocument: return "doc.badge.plus"
        case .openDocument: return "folder"
        case .saveDocument: return "square.and.arrow.down"
        case .setMode: return "rectangle.2.swap"
        case .setScreenplayElement: return "film"
        case .setLanguage: return "chevron.left.forwardslash.chevron.right"
        case .setTheme: return "paintpalette"
        }
    }
}

private struct WordProcessorCommandPaletteView: View {
    @Binding var query: String
    let onRunAction: (WordProcessorPaletteAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hoveredIndex: Int? = nil
    @FocusState private var searchFocused: Bool

    private struct PaletteSection {
        let title: String
        let items: [WordProcessorPaletteAction]
    }

    private enum PaletteRow: Identifiable {
        case header(String)
        case item(WordProcessorPaletteAction, Int)

        var id: String {
            switch self {
            case .header(let t): return "h:\(t)"
            case .item(let a, let i): return "i:\(i):\(a.title)"
            }
        }
    }

    private func fuzzyMatches(_ q: String, in title: String) -> Bool {
        let ql = q.lowercased(), tl = title.lowercased()
        if tl.contains(ql) { return true }
        var tIdx = tl.startIndex
        for ch in ql {
            guard let found = tl[tIdx...].firstIndex(of: ch) else { return false }
            tIdx = tl.index(after: found)
        }
        return true
    }

    private func highlightedText(_ title: String) -> Text {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let range = title.range(of: q, options: .caseInsensitive) else {
            return Text(title)
        }
        return Text(String(title[title.startIndex..<range.lowerBound]))
             + Text(String(title[range])).bold().foregroundColor(DesignTokens.accent)
             + Text(String(title[range.upperBound...]))
    }

    private var filteredSections: [PaletteSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let match: (WordProcessorPaletteAction) -> Bool = { q.isEmpty || fuzzyMatches(q, in: $0.title) }

        let fileItems  = [WordProcessorPaletteAction.newDocument, .openDocument, .saveDocument].filter(match)
        let modeItems  = AuthoringMode.allCases.map { WordProcessorPaletteAction.setMode($0) }.filter(match)
        let screenplayItems = ScreenplayElement.allCases.map { WordProcessorPaletteAction.setScreenplayElement($0) }.filter(match)
        let langItems  = CodeLanguage.allCases.map { WordProcessorPaletteAction.setLanguage($0) }.filter(match)
        let themeItems = CodeTheme.allCases.map { WordProcessorPaletteAction.setTheme($0) }.filter(match)

        var sections: [PaletteSection] = []
        if !fileItems.isEmpty  { sections.append(PaletteSection(title: "File",       items: fileItems))  }
        if !modeItems.isEmpty  { sections.append(PaletteSection(title: "Mode",       items: modeItems))  }
        if !screenplayItems.isEmpty { sections.append(PaletteSection(title: "Screenplay", items: screenplayItems)) }
        if !langItems.isEmpty  { sections.append(PaletteSection(title: "Language",   items: langItems))  }
        if !themeItems.isEmpty { sections.append(PaletteSection(title: "Theme",      items: themeItems)) }
        return sections
    }

    private var paletteRows: [PaletteRow] {
        var rows: [PaletteRow] = []
        var idx = 0
        for section in filteredSections {
            rows.append(.header(section.title))
            for item in section.items { rows.append(.item(item, idx)); idx += 1 }
        }
        return rows
    }

    private var flatCount: Int { filteredSections.reduce(0) { $0 + $1.items.count } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DesignTokens.accent)
                TextField("Run command, switch mode, theme, or language", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .focused($searchFocused)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)

            Divider().overlay(DesignTokens.borderRim)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(paletteRows) { row in
                        switch row {
                        case .header(let title):
                            Text(title.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(DesignTokens.chromeText.opacity(0.45))
                                .padding(.horizontal, 14)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        case .item(let action, let idx):
                            Button {
                                onRunAction(action)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: action.symbol)
                                        .foregroundStyle(DesignTokens.accent)
                                        .frame(width: 18)
                                    highlightedText(action.title)
                                        .foregroundStyle(DesignTokens.chromeText)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                                .background(hoveredIndex == idx ? DesignTokens.glassHotSpot.opacity(0.4) : .clear)
                            }
                            .buttonStyle(.plain)
                            .onHover { if $0 { hoveredIndex = idx } }
                        }
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .frame(width: 540, height: 420)
        .glassChromeBackground(style: .deep, cornerRadius: 14)
        .onAppear {
            searchFocused = true
            hoveredIndex = flatCount > 0 ? 0 : nil
        }
        .onChange(of: query) {
            hoveredIndex = flatCount > 0 ? 0 : nil
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard flatCount > 0 else { return .ignored }
            hoveredIndex = min((hoveredIndex ?? -1) + 1, flatCount - 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard flatCount > 0 else { return .ignored }
            hoveredIndex = max((hoveredIndex ?? 1) - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            guard let idx = hoveredIndex else { return .ignored }
            var counter = 0
            for section in filteredSections {
                for item in section.items {
                    if counter == idx { onRunAction(item); dismiss(); return .handled }
                    counter += 1
                }
            }
            return .ignored
        }
    }
}
