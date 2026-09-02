import SwiftUI
import SharedFoundation

struct WordProcessorContentView: View {
    @EnvironmentObject private var session: DocumentSession
    @ObservedObject private var appearance = MongrelAppearancePreferences.shared
    @State private var showShortcutHelp: Bool = false
    @State private var showCommandPalette: Bool = false
    @State private var commandQuery: String = ""
    @State private var isSidebarVisible: Bool = true
    @State private var isFocusMode: Bool = false
    @State private var showDocumentInsights: Bool = false
    @State private var showWritingTools: Bool = false
    @State private var showPageLayout: Bool = false
    @State private var isNativeFullScreen: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible && !isFocusMode {
                sidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Rectangle()
                    .fill(DesignTokens.borderRim.opacity(0.38))
                    .frame(width: 0.5)
            }
            detailPane
        }
        .background(DesignTokens.glassDeep.ignoresSafeArea())
        .sheet(isPresented: $showCommandPalette) {
            WordProcessorCommandPaletteView(query: $commandQuery, onRunAction: runCommandPaletteAction)
        }
        .sheet(isPresented: $showDocumentInsights) {
            DocumentInsightsView(snapshot: session.documentInsights, mode: session.authoringMode)
        }
        .sheet(isPresented: $showWritingTools) {
            WritingToolsView(session: session)
        }
        .sheet(isPresented: $showPageLayout) {
            DocumentPageLayoutView(session: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isNativeFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isNativeFullScreen = false
        }
        .onExitCommand {
            if isFocusMode {
                setFocusMode(false)
            }
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
            .padding(.top, isNativeFullScreen ? 14 : 34)
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent Documents")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.58))
                        .textCase(.uppercase)
                    Spacer()
                    Menu {
                        Button("Clear Recent Documents") {
                            session.clearRecentDocuments()
                        }
                        .disabled(session.recentDocuments.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.5))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

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
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)

            if session.authoringMode == .screenplay {
                screenplaySceneNavigator
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("Document Stats")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.58))
                    .textCase(.uppercase)

                if session.authoringMode == .code {
                    statLine("Lines", value: "\(session.codeLineCount)")
                    statLine("Characters", value: "\(session.charCount)")
                    statLine("Language", value: session.codeLanguage.title)
                    statLine("Indentation", value: session.codeIndentationSummary)
                } else {
                    statLine("Words", value: "\(session.wordCount)")
                    statLine("Characters", value: "\(session.charCount)")
                    statLine("Spellcheck", value: session.companionSpellcheckDetail)
                }
                if session.authoringMode == .screenplay {
                    statLine("Pages", value: "\(session.screenplayPageCount)")
                    statLine("Scenes", value: "\(session.screenplaySceneCount)")
                }
                statLine("State", value: session.documentStatusLabel)
            }
            .padding(12)
            .background(DesignTokens.glassBase.opacity(0.42))
        }
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
        .glassChromeBackground(style: .deep, cornerRadius: 0)
    }

    private var screenplaySceneNavigator: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scenes")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                Spacer()
                Text("\(session.screenplayScenes.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(DesignTokens.chromeText.opacity(0.58))

            if session.screenplayScenes.isEmpty {
                Text("Scene headings appear here as you draft.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(session.screenplayScenes) { scene in
                            Button {
                                session.formattingBridge.focusScreenplayLocation(scene.location)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(scene.number)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(DesignTokens.accent)
                                        .frame(width: 20, alignment: .trailing)
                                    Text(scene.heading)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(DesignTokens.glassCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var detailPane: some View {
        VStack(spacing: 0) {
            if !isFocusMode {
                topChrome
                    .fixedSize(horizontal: false, vertical: true)
                formattingToolbar
                    .fixedSize(horizontal: false, vertical: true)
            }
            editorArea
            if !isFocusMode {
                statusBar
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(DesignTokens.glassDeep)
        .overlay(alignment: .topTrailing) {
            if isFocusMode {
                focusModeControls
                    .padding(14)
            }
        }
    }

    private var topChrome: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isSidebarVisible.toggle()
                }
            } label: {
                Image(systemName: isSidebarVisible ? "sidebar.left" : "sidebar.right")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.76))
            }
            .buttonStyle(.plain)
            .help(isSidebarVisible ? "Hide sidebar" : "Show sidebar")

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
                        .fill(DesignTokens.glassCard.opacity(0.7))
                )
                .frame(minWidth: 210, idealWidth: 280, maxWidth: 360)

            if session.hasUnsavedChanges {
                Text("Unsaved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignTokens.accent.opacity(0.12), in: Capsule())
            }

            Spacer()

            Menu {
                Button("New Document") {
                    session.newDocument()
                }
                Button("New Screenplay") {
                    session.newScreenplay()
                }
                Button("New Code File") {
                    session.newCodeDocument()
                }
            } label: {
                Text("New")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

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
            } else if session.authoringMode == .screenplay {
                Menu {
                    ForEach(ScreenplayViewStyle.allCases) { style in
                        Button {
                            session.screenplayViewStyle = style
                        } label: {
                            if session.screenplayViewStyle == style {
                                Label(style.title, systemImage: "checkmark")
                            } else {
                                Text(style.title)
                            }
                        }
                    }
                } label: {
                    Label(
                        session.screenplayViewStyle.title,
                        systemImage: session.screenplayViewStyle.systemImage
                    )
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.78))
                }
                .menuStyle(.borderlessButton)
                .help("Choose paged, fit-width, or clean document presentation")

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

            if session.authoringMode != .code {
                Divider()
                    .frame(height: 18)

                Button {
                    showPageLayout = true
                } label: {
                    Label("Page Layout", systemImage: "doc.badge.gearshape")
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.88))
                }
                .buttonStyle(.plain)
                .help("Page colors, headers, footers, page fields, and artwork")

                Button {
                    session.formattingBridge.insertImageAttachment()
                } label: {
                    Image(systemName: "photo.badge.plus")
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
                }
                .buttonStyle(.plain)
                .help("Insert image (PNG, JPEG, HEIC, TIFF, GIF, or PDF)")
            }

            Menu {
                Button("Save a Copy...") {
                    session.saveDocumentCopyAs()
                }
                if session.authoringMode == .code {
                    Button("Export as Plain Text...") {
                        session.exportAsPlainText()
                    }
                } else {
                    Divider()
                    Button("Export as PDF...") {
                        session.exportAsPDF()
                    }
                    Button("Export as RTF...") {
                        session.exportAsRTF()
                    }
                    Button("Export as RTFD with Attachments...") {
                        session.exportAsRTFD()
                    }
                    Button("Export as Word (.docx)...") {
                        session.exportAsWordDocument()
                    }
                    Button("Export as Plain Text...") {
                        session.exportAsPlainText()
                    }
                }
                Divider()
                Button("Print...") {
                    session.printDocument()
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
                setFocusMode(true)
            } label: {
                Image(systemName: "viewfinder")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
            }
            .buttonStyle(.plain)
            .help("Focus mode")
            .keyboardShortcut("f", modifiers: [.command, .shift])

            if session.authoringMode != .code {
                Button {
                    showDocumentInsights = true
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
                }
                .buttonStyle(.plain)
                .help("Document insights")

                Button {
                    showWritingTools = true
                } label: {
                    Image(systemName: "text.badge.checkmark")
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
                }
                .buttonStyle(.plain)
                .help("Spelling and grammar tools")
            }

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
        }
        .padding(.horizontal, 12)
        .padding(.top, isNativeFullScreen ? 11 : 9)
        .padding(.bottom, 9)
        .background(
            LinearGradient(
                colors: [DesignTokens.glassElevated.opacity(0.94), DesignTokens.glassBase.opacity(0.80)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.borderRim.opacity(0.46))
                .frame(height: 0.5)
        }
    }

    private var formattingToolbar: some View {
        HStack(spacing: 6) {
            if session.authoringMode == .screenplay {
                screenplayToolbar
            } else if session.authoringMode == .code {
                codeToolbar
            } else {
                proseToolbar
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
        .padding(.top, 5)
        .padding(.bottom, 8)
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(DesignTokens.chromeText)
        .background(DesignTokens.glassBase.opacity(0.58))
    }

    private var codeToolbar: some View {
        Group {
            Menu {
                Section("Typeface") {
                    ForEach(CodeFont.allCases, id: \.rawValue) { font in
                        Button {
                            session.codeFont = font
                        } label: {
                            if session.codeFont == font {
                                Label(font.title, systemImage: "checkmark")
                            } else {
                                Text(font.title)
                            }
                        }
                    }
                }

                Section("Size") {
                    ForEach([11, 12, 13, 14, 15, 16, 18, 20, 22, 24], id: \.self) { size in
                        Button {
                            session.codeFontSize = CGFloat(size)
                        } label: {
                            if Int(session.codeFontSize) == size {
                                Label("\(size) pt", systemImage: "checkmark")
                            } else {
                                Text("\(size) pt")
                            }
                        }
                    }
                }
            } label: {
                Label("\(session.codeFont.title) \(Int(session.codeFontSize))", systemImage: "textformat")
                    .foregroundStyle(DesignTokens.accent)
            }
            .menuStyle(.borderlessButton)

            Divider().frame(height: 14)

            Button(session.codeUseTabs ? "Tabs" : "Spaces") {
                session.codeUseTabs.toggle()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.chromeText.opacity(0.85))

            Menu {
                ForEach([2, 4, 8], id: \.self) { width in
                    Button("\(width) columns") { session.codeTabWidth = width }
                }
            } label: {
                Label("Width \(session.codeTabWidth)", systemImage: "ruler")
                    .foregroundStyle(DesignTokens.accent)
            }
            .menuStyle(.borderlessButton)

            Button(session.codeLineWrap ? "Wrap On" : "Wrap Off") {
                session.codeLineWrap.toggle()
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.chromeText.opacity(0.85))

            Divider().frame(height: 14)

            Button {
                session.toggleCodeComment()
            } label: {
                Label("Comment", systemImage: "text.badge.minus")
            }
            .buttonStyle(.plain)
            .disabled(session.codeLanguage.lineCommentPrefix == nil)
            .help("Toggle line comment (Cmd-/)")

            Button {
                session.duplicateCodeLines()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.plain)
            .help("Duplicate line or selected lines (Cmd-Shift-D)")

            Divider().frame(height: 14)

            Text("Tab / Shift-Tab indents")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.58))
        }
    }

    private var proseToolbar: some View {
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

            Menu {
                Button("Show Font Panel") {
                    session.showFontPanel()
                }
                Button("Install Font Files...") {
                    session.installFontFiles()
                }
            } label: {
                Image(systemName: "textformat")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
            }
            .menuStyle(.borderlessButton)
            .help("Choose or install fonts")

            Button {
                session.formattingBridge.insertImageAttachment()
            } label: {
                Image(systemName: "photo.badge.plus")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
            }
            .buttonStyle(.plain)
            .help("Insert image")

            Button {
                session.formattingBridge.checkSpelling()
            } label: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.82))
            }
            .buttonStyle(.plain)
            .help("Check spelling and grammar")
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

                Button {
                    session.formattingBridge.autoFormatEntireScreenplay()
                } label: {
                    Label("Auto Format", systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.accent)
                }
                .buttonStyle(.plain)
                .help("Format every paragraph using screenplay context")

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
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var editorArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if session.authoringMode == .screenplay {
                GeometryReader { geometry in
                    let scale = screenplayCanvasScale(availableWidth: geometry.size.width)
                    ScrollView([.horizontal, .vertical]) {
                        screenplayEditorCanvas(
                            scale: scale,
                            availableWidth: geometry.size.width,
                            availableHeight: geometry.size.height
                        )
                    }
                    .scrollIndicators(.visible)
                }
            } else if session.authoringMode == .code {
                coreEditor(editorZoom: session.editorZoom)
                    .background(selectedEditorBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DesignTokens.borderRim.opacity(0.45), lineWidth: 0.6)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                proseEditorCanvas
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [DesignTokens.glassDeep, DesignTokens.glassBase],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay {
            if session.attributedText.length == 0 {
                emptyDocumentHint
                    .allowsHitTesting(false)
            }
        }
    }

    private var proseEditorCanvas: some View {
        GeometryReader { geometry in
            let outerMargin: CGFloat = isFocusMode ? 52 : 30
            let maximumWidth: CGFloat = isFocusMode ? 1_080 : 980
            let canvasWidth = max(560, min(maximumWidth, geometry.size.width - outerMargin))

            HStack(spacing: 0) {
                Spacer(minLength: 14)
                coreEditor(editorZoom: session.editorZoom)
                    .frame(width: canvasWidth, height: geometry.size.height)
                    .background(selectedEditorBackground)
                    .clipShape(RoundedRectangle(cornerRadius: isFocusMode ? 8 : 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: isFocusMode ? 8 : 12, style: .continuous)
                            .stroke(DesignTokens.borderRim.opacity(isFocusMode ? 0.18 : 0.34), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(isFocusMode ? 0.04 : 0.10), radius: 20, y: 10)
                Spacer(minLength: 14)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var screenplayPageSummary: String {
        "\(session.screenplayPageCount) page\(session.screenplayPageCount == 1 ? "" : "s")"
    }

    private var screenplaySceneSummary: String {
        "\(session.screenplaySceneCount) scene\(session.screenplaySceneCount == 1 ? "" : "s")"
    }

    private func coreEditor(editorZoom: CGFloat) -> some View {
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
            onCodePositionChange: { line, column, selectionLength in
                session.updateCodeCursor(line: line, column: column, selectionLength: selectionLength)
            },
            bridge: session.formattingBridge,
            companionLexicon: session.companionLexicon,
            authoringMode: session.authoringMode,
            screenplayElement: session.screenplayElement,
            codeLanguage: session.codeLanguage,
            codeTheme: session.codeTheme,
            codeFont: session.codeFont,
            codeFontSize: session.codeFontSize,
            codeUseTabs: session.codeUseTabs,
            codeTabWidth: session.codeTabWidth,
            codeLineWrap: session.codeLineWrap,
            editorZoom: editorZoom,
            typewriterMode: session.typewriterMode,
            pageBackgroundColor: session.pageLayout.pageColors.background.nsColor,
            pageTextColor: session.pageLayout.pageColors.text.nsColor
        )
    }

    private func screenplayEditorCanvas(
        scale: CGFloat,
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> some View {
        let scaledWidth = ScreenplayPageLayout.pageSize.width * scale
        let scaledHeight = ScreenplayPageLayout.pageSize.height * scale
        let style = session.screenplayViewStyle
        let cornerRadius: CGFloat = style.showsPaperChrome ? 14 : 5
        let horizontalMargin: CGFloat = style.showsPaperChrome ? 28 : 12

        return HStack(spacing: 0) {
            Spacer(minLength: horizontalMargin)
            coreEditor(editorZoom: scale)
                .frame(width: scaledWidth, height: scaledHeight)
                .background(selectedEditorBackground)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(alignment: .top) {
                    if style.showsPaperChrome {
                        HStack {
                            Text("US Letter")
                            Spacer()
                            Text(screenplayPageSummary)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(screenplayPaperForeground.opacity(0.58))
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(screenplayPaperBackground)
                        .shadow(
                            color: style.showsPaperChrome ? Color.black.opacity(0.10) : .clear,
                            radius: style.showsPaperChrome ? 22 : 0,
                            x: 0,
                            y: style.showsPaperChrome ? 12 : 0
                        )
                )
                .overlay {
                    if style.showsPaperChrome {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(screenplayPaperForeground.opacity(0.12), lineWidth: 0.6)
                    }
                }
            Spacer(minLength: horizontalMargin)
        }
        .frame(
            minWidth: max(availableWidth, scaledWidth + (horizontalMargin * 2)),
            minHeight: max(availableHeight, scaledHeight + 20),
            alignment: .top
        )
        .padding(.vertical, style.showsPaperChrome ? 14 : 6)
    }

    private func screenplayCanvasScale(availableWidth: CGFloat) -> CGFloat {
        guard session.screenplayViewStyle.usesAutomaticZoom else {
            return session.editorZoom
        }
        let margin: CGFloat = isFocusMode ? 88 : 64
        let proposed = (availableWidth - margin) / ScreenplayPageLayout.pageSize.width
        return min(max(proposed, 0.6), 1.6)
    }

    private var statusBar: some View {
        HStack {
            if session.authoringMode == .code {
                Text("\(session.codeLineCount) lines")
                Text("·")
                Text("\(session.charCount) characters")
                Text("·")
                Text(session.codeLanguage.title)
                Text("·")
                Text(session.codeIndentationSummary)
                Text("·")
                Text("Ln \(session.codeCursorLine), Col \(session.codeCursorColumn)")
                if session.codeSelectionLength > 0 {
                    Text("·")
                    Text("\(session.codeSelectionLength) selected")
                }
            } else {
                Text("\(session.wordCount) words")
                Text("·")
                Text("\(session.charCount) characters")
                Text("·")
                Text(session.authoringMode.title)
                Text("·")
                Text(session.companionSpellcheckSummary)
            }
            if session.authoringMode == .screenplay {
                Text("·")
                Text(screenplayPageSummary)
                Text("·")
                Text(screenplaySceneSummary)
                Text("·")
                Text(session.screenplayElement.shortTitle)
            }
            Spacer()
            writingControls
            Text("·")
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
        .padding(.vertical, 7)
        .background(DesignTokens.glassDeep.opacity(0.84))
    }

    private var writingControls: some View {
        HStack(spacing: 7) {
            Button {
                session.typewriterMode.toggle()
            } label: {
                Image(systemName: session.typewriterMode ? "scope" : "scope")
                    .foregroundStyle(session.typewriterMode ? DesignTokens.accent : DesignTokens.chromeText.opacity(0.62))
            }
            .buttonStyle(.plain)
            .help("Keep the current line near the center")

            if session.authoringMode == .screenplay,
               session.screenplayViewStyle.usesAutomaticZoom {
                Button {
                    session.screenplayViewStyle = .page
                    session.resetEditorZoom()
                } label: {
                    Label(session.screenplayViewStyle.title, systemImage: "arrow.left.and.right")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .help("Switch to manual page zoom at actual size")
            } else {
                Button {
                    session.adjustEditorZoom(by: -0.1)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .disabled(session.editorZoom <= 0.6)

                Button {
                    session.resetEditorZoom()
                } label: {
                    Text("\(session.editorZoomPercentage)%")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(minWidth: 34)
                }
                .buttonStyle(.plain)
                .help("Reset zoom")

                Button {
                    session.adjustEditorZoom(by: 0.1)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .disabled(session.editorZoom >= 2)
            }
        }
    }

    private var focusModeControls: some View {
        HStack(spacing: 10) {
            Text(session.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)

            writingControls

            Button {
                setFocusMode(false)
            } label: {
                Label("Exit Focus", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .buttonStyle(.plain)
            .help("Exit focus mode (Esc)")
        }
        .foregroundStyle(DesignTokens.chromeText.opacity(0.86))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassChromeBackground(style: .card, cornerRadius: 12)
    }

    private var emptyDocumentHint: some View {
        VStack(spacing: 9) {
            Image(systemName: emptyDocumentSymbol)
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DesignTokens.accent.opacity(0.72))
            Text(emptyDocumentTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.68))
            Text(emptyDocumentDetail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.4))
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(DesignTokens.glassElevated.opacity(0.66), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DesignTokens.borderRim, lineWidth: 0.6)
        )
    }

    private var emptyDocumentDetail: String {
        if isFocusMode {
            return "Esc exits focus mode"
        }
        if session.authoringMode == .screenplay {
            return "Try INT. or EXT. · Tab changes element"
        }
        if session.authoringMode == .code {
            return "Tab indents · Cmd-/ comments · Cmd-Shift-D duplicates"
        }
        return "Cmd-S saves · Cmd-Shift-F enters focus mode"
    }

    private var emptyDocumentSymbol: String {
        switch session.authoringMode {
        case .prose: return "text.cursor"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .screenplay: return "film.stack"
        }
    }

    private var emptyDocumentTitle: String {
        switch session.authoringMode {
        case .prose: return "Click anywhere and begin writing"
        case .code: return "Start a \(session.codeLanguage.title) file"
        case .screenplay: return "Begin with a scene heading"
        }
    }

    private func setFocusMode(_ enabled: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isFocusMode = enabled
        }
        session.formattingBridge.focusEditor()
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
                .fill(isActive ? DesignTokens.accent.opacity(0.18) : DesignTokens.glassElevated.opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isActive ? DesignTokens.accent.opacity(0.55) : .clear,
                            lineWidth: 0.5
                        )
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
                .fill(DesignTokens.glassElevated.opacity(0.58))
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
                screenplayPaperBackground
                if session.pageLayout.palette == .warmPaper || session.pageLayout.palette == .sepia {
                    LinearGradient(
                        colors: [Color(red: 0.84, green: 0.78, blue: 0.62).opacity(0.22), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [screenplayPaperForeground.opacity(0.035), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            } else {
                Color(nsColor: session.pageLayout.pageColors.background.nsColor)
                LinearGradient(
                    colors: [Color.white.opacity(0.035), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var screenplayPaperBackground: Color {
        Color(nsColor: session.pageLayout.pageColors.background.nsColor)
    }

    private var screenplayPaperForeground: Color {
        Color(nsColor: session.pageLayout.pageColors.text.nsColor)
    }

    private var codeBackground: (Color, Color) {
        switch session.codeTheme {
        case .studio:
            return (Color(red: 0.075, green: 0.082, blue: 0.095), Color(red: 0.18, green: 0.21, blue: 0.25))
        case .paper:
            return (Color(red: 0.96, green: 0.95, blue: 0.91), Color(red: 0.72, green: 0.80, blue: 0.86))
        case .midnight:
            return (Color(red: 0.012, green: 0.016, blue: 0.022), Color(red: 0.08, green: 0.18, blue: 0.26))
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
                    ("Cmd + N", "New document"),
                    ("Cmd + Shift + N", "New screenplay"),
                    ("Cmd + O", "Open document"),
                    ("Cmd + S", "Save document"),
                    ("Cmd + Shift + S", "Save As"),
                    ("Cmd + P", "Print document"),
                    ("Cmd + K", "Command palette")
                ]
            )

            shortcutSection(
                "Writing",
                items: [
                    ("Cmd + Shift + F", "Enter focus mode"),
                    ("Esc", "Exit focus mode"),
                    ("Cmd + Option + T", "Typewriter scrolling"),
                    ("Cmd + + / -", "Zoom in / out"),
                    ("Cmd + 0", "Actual size")
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
                    ("Cmd + Option + N", "New code file"),
                    ("Tab / Shift + Tab", "Indent / outdent"),
                    ("Cmd + /", "Toggle line comment"),
                    ("Cmd + Shift + D", "Duplicate selected lines"),
                    ("Language Menu", "Choose language or format"),
                    ("Theme Menu", "Cobalt/Frost/Amber themes"),
                    ("Esc", "Dismiss completion popup")
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
        case .newScreenplay:
            session.newScreenplay()
        case .newCodeDocument:
            session.newCodeDocument()
        case .openDocument:
            session.openDocument()
        case .saveDocument:
            session.saveDocument()
        case .saveCopy:
            session.saveDocumentCopyAs()
        case .printDocument:
            session.printDocument()
        case .toggleFocusMode:
            setFocusMode(!isFocusMode)
        case .toggleTypewriterMode:
            session.typewriterMode.toggle()
        case .zoomIn:
            session.adjustEditorZoom(by: 0.1)
        case .zoomOut:
            session.adjustEditorZoom(by: -0.1)
        case .resetZoom:
            session.resetEditorZoom()
        case .clearRecentDocuments:
            session.clearRecentDocuments()
        case .autoFormatScreenplay:
            session.authoringMode = .screenplay
            session.formattingBridge.autoFormatEntireScreenplay()
        case .toggleCodeComment:
            session.toggleCodeComment()
        case .duplicateCodeLines:
            session.duplicateCodeLines()
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

private struct DocumentPageLayoutView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Page Layout")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("Page colors, headers, and footers used by Mongrel documents, PDF export, and print")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.56))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider().opacity(0.35)

            ScrollView {
                VStack(spacing: 16) {
                    pageColorControls
                    pagePreview

                    PageBandEditor(
                        title: "Header",
                        band: $session.pageLayout.header,
                        chooseImage: { session.choosePageBandImage(for: .header) },
                        removeImage: { session.removePageBandImage(for: .header) }
                    )

                    PageBandEditor(
                        title: "Footer",
                        band: $session.pageLayout.footer,
                        chooseImage: { session.choosePageBandImage(for: .footer) },
                        removeImage: { session.removePageBandImage(for: .footer) }
                    )

                    Toggle("Show header and footer on the first page", isOn: $session.pageLayout.showsOnFirstPage)
                        .toggleStyle(.switch)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fields")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .textCase(.uppercase)
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.55))
                        Text("Use {title}, {page}, {pages}, or {date} in either text field.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.74))
                        Text("RTFD retains embedded body images. RTF and DOCX retain styled text but may discard attachments. None preserve Mongrel page colors or furniture; use .mongreldoc for editable fidelity or PDF for final delivery.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.52))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(DesignTokens.glassCard.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 820)
        .background(DesignTokens.glassDeep)
        .foregroundStyle(DesignTokens.chromeText)
    }

    private var pageColorControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Page colors")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Applied to the document canvas, body text, PDF, and print.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.54))
                }
                Spacer()
                Text(String(format: "%.1f:1", session.pageLayout.pageColors.contrastRatio))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(
                        session.pageLayout.pageColors.contrastRatio >= 7
                            ? DesignTokens.accent
                            : (session.pageLayout.pageColors.contrastRatio >= 4.5 ? DesignTokens.chromeText : .orange)
                    )
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(DocumentPagePalette.allCases) { palette in
                    Button {
                        session.applyPagePalette(palette)
                    } label: {
                        let colors = palette.colors(
                            customBackground: session.pageLayout.customPageBackground,
                            customText: session.pageLayout.customPageText
                        )
                        VStack(spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(nsColor: colors.background.nsColor))
                                Text("Aa")
                                    .font(.system(size: 15, weight: .bold, design: .serif))
                                    .foregroundStyle(Color(nsColor: colors.text.nsColor))
                            }
                            .frame(height: 42)
                            Text(palette.title)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .padding(7)
                        .background(DesignTokens.glassCard.opacity(0.54), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    session.pageLayout.palette == palette
                                        ? DesignTokens.accent
                                        : DesignTokens.borderRim.opacity(0.55),
                                    lineWidth: session.pageLayout.palette == palette ? 1.4 : 0.6
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if session.pageLayout.palette == .custom {
                HStack(spacing: 18) {
                    ColorPicker("Background", selection: customBackgroundBinding, supportsOpacity: false)
                    ColorPicker("Text", selection: customTextBinding, supportsOpacity: false)
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
            }

            if session.pageLayout.pageColors.contrastRatio < 4.5 {
                Label("This pairing is difficult to read. Aim for at least 4.5:1.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(DesignTokens.glassElevated.opacity(0.60), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignTokens.borderRim.opacity(0.45), lineWidth: 0.6))
    }

    private var customBackgroundBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: session.pageLayout.customPageBackground.nsColor) },
            set: { color in
                session.updateCustomPageColors(
                    background: documentColor(from: color, fallback: session.pageLayout.customPageBackground),
                    text: session.pageLayout.customPageText
                )
            }
        )
    }

    private var customTextBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: session.pageLayout.customPageText.nsColor) },
            set: { color in
                session.updateCustomPageColors(
                    background: session.pageLayout.customPageBackground,
                    text: documentColor(from: color, fallback: session.pageLayout.customPageText)
                )
            }
        )
    }

    private func documentColor(from color: Color, fallback: DocumentRGBColor) -> DocumentRGBColor {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return fallback }
        return DocumentRGBColor(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent)
        )
    }

    private var pagePreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: session.pageLayout.pageColors.background.nsColor))
                .shadow(color: Color.black.opacity(0.16), radius: 18, y: 8)

            VStack(spacing: 0) {
                previewBand(session.pageLayout.header, pageNumber: 1, pageCount: 3)
                Spacer()
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 2).frame(width: 230, height: 5)
                    RoundedRectangle(cornerRadius: 2).frame(width: 205, height: 5)
                    RoundedRectangle(cornerRadius: 2).frame(width: 220, height: 5)
                }
                .foregroundStyle(Color(nsColor: session.pageLayout.pageColors.text.nsColor).opacity(0.16))
                Spacer()
                previewBand(session.pageLayout.footer, pageNumber: 1, pageCount: 3)
            }
            .padding(18)
        }
        .frame(width: 310, height: 220)
    }

    @ViewBuilder
    private func previewBand(_ band: DocumentPageBand, pageNumber: Int, pageCount: Int) -> some View {
        if band.hasRenderableContent {
            HStack(spacing: 7) {
                if let image = band.image?.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 44, maxHeight: 18)
                }
                Text(session.pageLayout.resolvedText(
                    for: band,
                    title: session.title,
                    pageNumber: pageNumber,
                    pageCount: pageCount
                ))
                .font(.system(size: 7.5, weight: .medium, design: .rounded))
                .lineLimit(1)
            }
            .foregroundStyle(Color(nsColor: session.pageLayout.pageColors.text.nsColor).opacity(0.72))
            .frame(maxWidth: .infinity, alignment: swiftUIAlignment(for: band.alignment))
        } else {
            Color.clear.frame(height: 18)
        }
    }

    private func swiftUIAlignment(for alignment: PageBandAlignment) -> Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

private struct PageBandEditor: View {
    let title: String
    @Binding var band: DocumentPageBand
    let chooseImage: () -> Void
    let removeImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(title, isOn: $band.isEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 14, weight: .semibold, design: .rounded))

            Group {
                TextField("Text or fields", text: $band.text)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Picker("Alignment", selection: $band.alignment) {
                        ForEach(PageBandAlignment.allCases) { alignment in
                            Text(alignment.title).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Page number", isOn: $band.includesPageNumber)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                }

                HStack(spacing: 10) {
                    Button {
                        chooseImage()
                    } label: {
                        Label(band.image == nil ? "Attach Artwork" : "Replace Artwork", systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    if let image = band.image {
                        Text(image.filename)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.58))
                            .lineLimit(1)
                        Button("Remove", role: .destructive) { removeImage() }
                            .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .disabled(!band.isEnabled)
        }
        .padding(16)
        .background(DesignTokens.glassElevated.opacity(0.60), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DesignTokens.borderRim.opacity(band.isEnabled ? 0.56 : 0.24), lineWidth: 0.6)
        )
    }
}

private struct DocumentInsightsView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: DocumentInsightSnapshot
    let mode: AuthoringMode

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Document Insights")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Structure and rhythm, computed locally")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.55))
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.accent)
            }

            HStack(spacing: 10) {
                metricCard("Reading", value: snapshot.readingMinutes == 0 ? "-" : "\(snapshot.readingMinutes) min")
                metricCard("Sentences", value: "\(snapshot.sentenceCount)")
                metricCard(
                    "Avg. sentence",
                    value: snapshot.averageWordsPerSentence == 0
                        ? "-"
                        : String(format: "%.1f words", snapshot.averageWordsPerSentence)
                )
                if mode == .screenplay {
                    metricCard("Dialogue", value: "\(Int((snapshot.dialogueShare * 100).rounded()))%")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Paragraph Rhythm")
                rhythmChart.frame(height: 110)
            }

            if mode == .screenplay, !snapshot.scenes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionTitle("Scene Weight")
                    GeometryReader { geometry in
                        HStack(spacing: 3) {
                            ForEach(snapshot.scenes) { scene in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(DesignTokens.accent.opacity(min(0.9, 0.35 + (scene.share * 1.8))))
                                    .frame(width: max(5, geometry.size.width * scene.share))
                            }
                        }
                    }
                    .frame(height: 28)
                }
            }

            if mode == .screenplay, !snapshot.characters.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    sectionTitle("Character Cues")
                    ForEach(snapshot.characters) { character in
                        HStack {
                            Text(character.name).lineLimit(1)
                            Spacer()
                            Text("\(character.cueCount)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(DesignTokens.accent)
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 680)
        .frame(minHeight: 470)
        .foregroundStyle(DesignTokens.chromeText)
        .glassChromeBackground(style: .deep, cornerRadius: 16)
    }

    private var rhythmChart: some View {
        GeometryReader { geometry in
            let maximum = max(snapshot.paragraphWordCounts.max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(snapshot.paragraphWordCounts.enumerated()), id: \.offset) { _, count in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DesignTokens.accent.opacity(0.76))
                        .frame(
                            width: max(2, (geometry.size.width / CGFloat(max(snapshot.paragraphWordCounts.count, 1))) - 2),
                            height: max(3, geometry.size.height * CGFloat(count) / CGFloat(maximum))
                        )
                        .help("\(count) words")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .background(
                LinearGradient(
                    colors: [DesignTokens.glassCard.opacity(0.65), DesignTokens.glassBase.opacity(0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.48))
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DesignTokens.glassCard.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(DesignTokens.chromeText.opacity(0.62))
    }
}

private struct WritingToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Writing Tools")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Immediate spelling plus optional local grammar analysis")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.55))
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.accent)
            }

            HStack(spacing: 10) {
                writingToolCard(
                    title: "SPELLING",
                    value: session.companionSpellcheckSummary,
                    detail: "macOS checker + Mongrel companion lexicon",
                    buttonTitle: "Check Now"
                ) {
                    session.formattingBridge.checkSpelling()
                }

                writingToolCard(
                    title: "LOCAL LANGUAGETOOL",
                    value: session.languageToolState.title,
                    detail: "127.0.0.1:8081 · text stays on this Mac",
                    buttonTitle: "Run Local Check"
                ) {
                    session.checkWithLocalLanguageTool()
                }
            }

            if case .unavailable(let message) = session.languageToolState {
                Text("Start a LanguageTool HTTP server on port 8081, then retry. \(message)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.58))
                    .padding(.horizontal, 2)
            }

            if session.languageToolIssues.isEmpty {
                Spacer()
                Text("LanguageTool suggestions will appear here. System spelling remains active while you type.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.chromeText.opacity(0.46))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(session.languageToolIssues) { issue in
                            issueCard(issue)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 720)
        .frame(minHeight: 500)
        .foregroundStyle(DesignTokens.chromeText)
        .glassChromeBackground(style: .deep, cornerRadius: 16)
    }

    private func issueCard(_ issue: LanguageToolIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                session.focusLanguageToolIssue(issue)
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(issue.shortMessage.isEmpty ? issue.message : issue.shortMessage)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.chromeText.opacity(0.58))
                    }
                    Spacer()
                    Text(issue.ruleID)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignTokens.chromeText.opacity(0.38))
                }
            }
            .buttonStyle(.plain)

            if !issue.replacements.isEmpty {
                HStack(spacing: 6) {
                    ForEach(issue.replacements, id: \.self) { replacement in
                        Button(replacement) {
                            session.applyLanguageToolReplacement(replacement, for: issue)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(12)
        .background(DesignTokens.glassCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }

    private func writingToolCard(
        title: String,
        value: String,
        detail: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.chromeText.opacity(0.48))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.caption)
                .foregroundStyle(DesignTokens.chromeText.opacity(0.52))
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(DesignTokens.glassCard.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum WordProcessorPaletteAction: Hashable {
    case newDocument
    case newScreenplay
    case newCodeDocument
    case openDocument
    case saveDocument
    case saveCopy
    case printDocument
    case toggleFocusMode
    case toggleTypewriterMode
    case zoomIn
    case zoomOut
    case resetZoom
    case clearRecentDocuments
    case autoFormatScreenplay
    case toggleCodeComment
    case duplicateCodeLines
    case setMode(AuthoringMode)
    case setScreenplayElement(ScreenplayElement)
    case setLanguage(CodeLanguage)
    case setTheme(CodeTheme)

    var title: String {
        switch self {
        case .newDocument: return "New Document"
        case .newScreenplay: return "New Screenplay"
        case .newCodeDocument: return "New Code File"
        case .openDocument: return "Open Document"
        case .saveDocument: return "Save Document"
        case .saveCopy: return "Save a Copy"
        case .printDocument: return "Print Document"
        case .toggleFocusMode: return "Toggle Focus Mode"
        case .toggleTypewriterMode: return "Toggle Typewriter Scrolling"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .resetZoom: return "Actual Size"
        case .clearRecentDocuments: return "Clear Recent Documents"
        case .autoFormatScreenplay: return "Screenplay: Auto Format Document"
        case .toggleCodeComment: return "Code: Toggle Line Comment"
        case .duplicateCodeLines: return "Code: Duplicate Lines"
        case .setMode(let mode): return "Authoring Mode: \(mode.title)"
        case .setScreenplayElement(let element): return "Screenplay Element: \(element.title)"
        case .setLanguage(let language): return "Code Language: \(language.title)"
        case .setTheme(let theme): return "Code Theme: \(theme.title)"
        }
    }

    var symbol: String {
        switch self {
        case .newDocument: return "doc.badge.plus"
        case .newScreenplay: return "film.stack"
        case .newCodeDocument: return "chevron.left.forwardslash.chevron.right"
        case .openDocument: return "folder"
        case .saveDocument: return "square.and.arrow.down"
        case .saveCopy: return "doc.on.doc"
        case .printDocument: return "printer"
        case .toggleFocusMode: return "viewfinder"
        case .toggleTypewriterMode: return "scope"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .resetZoom: return "1.magnifyingglass"
        case .clearRecentDocuments: return "clock.arrow.circlepath"
        case .autoFormatScreenplay: return "wand.and.stars"
        case .toggleCodeComment: return "text.badge.minus"
        case .duplicateCodeLines: return "plus.square.on.square"
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

        let fileItems  = [WordProcessorPaletteAction.newDocument, .newScreenplay, .newCodeDocument, .openDocument, .saveDocument, .saveCopy, .printDocument, .clearRecentDocuments].filter(match)
        let writingItems = [WordProcessorPaletteAction.toggleFocusMode, .toggleTypewriterMode, .zoomIn, .zoomOut, .resetZoom].filter(match)
        let modeItems  = AuthoringMode.allCases.map { WordProcessorPaletteAction.setMode($0) }.filter(match)
        let screenplayItems = ([WordProcessorPaletteAction.autoFormatScreenplay]
            + ScreenplayElement.allCases.map { WordProcessorPaletteAction.setScreenplayElement($0) }).filter(match)
        let codeItems = [WordProcessorPaletteAction.toggleCodeComment, .duplicateCodeLines].filter(match)
        let langItems  = CodeLanguage.allCases.map { WordProcessorPaletteAction.setLanguage($0) }.filter(match)
        let themeItems = CodeTheme.allCases.map { WordProcessorPaletteAction.setTheme($0) }.filter(match)

        var sections: [PaletteSection] = []
        if !fileItems.isEmpty  { sections.append(PaletteSection(title: "File",       items: fileItems))  }
        if !writingItems.isEmpty { sections.append(PaletteSection(title: "Writing", items: writingItems)) }
        if !modeItems.isEmpty  { sections.append(PaletteSection(title: "Mode",       items: modeItems))  }
        if !screenplayItems.isEmpty { sections.append(PaletteSection(title: "Screenplay", items: screenplayItems)) }
        if !codeItems.isEmpty { sections.append(PaletteSection(title: "Code", items: codeItems)) }
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
