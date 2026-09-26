import SwiftUI
import AppKit
import SharedFoundation

final class ScreenplayTextView: NSTextView {
    static let nativeSelectionType = NSPasteboard.PasteboardType("com.mongrel.screenplay-selection")
    private(set) var isPastingNativeContent = false
    weak var screenplayBridge: FormattingBridge?

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        isScreenplayPaginationActive ? [Self.nativeSelectionType] + super.writablePasteboardTypes : super.writablePasteboardTypes
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        isScreenplayPaginationActive ? [Self.nativeSelectionType] + super.readablePasteboardTypes : super.readablePasteboardTypes
    }

    override func paste(_ sender: Any?) {
        if !pasteScreenplay(from: .general) { super.paste(sender) }
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if !pasteScreenplay(from: .general, plainTextOnly: true) { super.pasteAsPlainText(sender) }
    }

    override func pasteAsRichText(_ sender: Any?) {
        if !pasteScreenplay(from: .general) { super.pasteAsRichText(sender) }
    }

    func pasteScreenplay(from pasteboard: NSPasteboard, plainTextOnly: Bool = false) -> Bool {
        guard isScreenplayPaginationActive, screenplayBridge != nil else { return false }
        let types: [NSPasteboard.PasteboardType] = plainTextOnly ? [.string] : [Self.nativeSelectionType, .rtfd, .rtf, .html, .string]
        for type in types where pasteboard.availableType(from: [type]) != nil {
            if readSelection(from: pasteboard, type: type) { return true }
        }
        return false
    }

    override func writeSelection(to pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == Self.nativeSelectionType else { return super.writeSelection(to: pasteboard, type: type) }
        guard let storage = textStorage else { return false }
        let selection = selectedRange()
        guard selection.location <= storage.length, selection.length <= storage.length - selection.location else { return false }
        do {
            let archive = try MongrelDocumentArchive(attributedText: storage.attributedSubstring(from: selection), authoringMode: .screenplay, pageLayout: .empty)
            return pasteboard.setData(try JSONEncoder().encode(archive), forType: type)
        } catch { return false }
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == Self.nativeSelectionType else {
            guard isScreenplayPaginationActive, let bridge = screenplayBridge else { return super.readSelection(from: pasteboard, type: type) }
            let incoming: NSAttributedString?
            if type == .string, let text = pasteboard.string(forType: .string) {
                incoming = NSAttributedString(string: text)
            } else if let data = pasteboard.data(forType: type), [.rtf, .rtfd, .html].contains(type) {
                let documentType: NSAttributedString.DocumentType = type == .rtf ? .rtf : (type == .rtfd ? .rtfd : .html)
                incoming = try? NSAttributedString(data: data, options: [.documentType: documentType], documentAttributes: nil)
            } else { incoming = nil }
            guard let incoming else { return super.readSelection(from: pasteboard, type: type) }
            let element = bridge.detectedScreenplayElement(in: self)
            insertScreenplayPaste(bridge.screenplayPaste(incoming, matching: element))
            return true
        }
        guard let data = pasteboard.data(forType: type), data.count <= 256 * 1_024 * 1_024,
              let archive = try? JSONDecoder().decode(MongrelDocumentArchive.self, from: data),
              let restored = try? archive.makeAttributedString() else { return false }
        let incoming = NSMutableAttributedString(attributedString: restored)
        var existingIDs = Set<String>()
        let selection = selectedRange()
        textStorage?.enumerateAttribute(.screenplaySceneIdentity, in: NSRange(location: 0, length: textStorage?.length ?? 0)) { value, range, _ in
            if let id = value as? String, NSIntersectionRange(range, selection).length < range.length { existingIDs.insert(id) }
        }
        // A cut-and-pasted scene keeps its identity. A copied scene gets a new one,
        // even when it is pasted ahead of the original in the same document.
        var duplicateRanges: [(NSRange, String)] = []
        var copiedIDs: [String: String] = [:]
        incoming.enumerateAttribute(.screenplaySceneIdentity, in: NSRange(location: 0, length: incoming.length)) { value, range, _ in
            if let id = value as? String, existingIDs.contains(id) {
                let replacement = copiedIDs[id] ?? UUID().uuidString
                copiedIDs[id] = replacement
                duplicateRanges.append((range, replacement))
            }
        }
        // Explicit fresh IDs also prevent AppKit from inheriting the adjacent
        // scene's identity when an untagged attributed string is inserted.
        for (range, replacement) in duplicateRanges { incoming.addAttribute(.screenplaySceneIdentity, value: replacement, range: range) }
        insertScreenplayPaste(incoming)
        return true
    }

    func insertScreenplayPaste(_ incoming: NSAttributedString) {
        let prepared = NSMutableAttributedString(attributedString: incoming)
        var elements: [(NSRange, String)] = []
        prepared.enumerateAttributes(in: NSRange(location: 0, length: prepared.length)) { attributes, range, _ in
            if attributes[.screenplayManualElement] == nil, let element = attributes[.screenplayElement] as? String {
                elements.append((range, element))
            }
        }
        // AppKit can inherit a destination paragraph's manual element when an
        // inserted run lacks that key. Make the pasted semantics explicit before
        // insertion so rendering, navigation, and later formatting agree.
        for (range, element) in elements { prepared.addAttribute(.screenplayManualElement, value: element, range: range) }
        breakUndoCoalescing()
        isPastingNativeContent = true
        defer { isPastingNativeContent = false }
        insertText(prepared, replacementRange: selectedRange())
        breakUndoCoalescing()
    }

    var pageBackgroundColor = NSColor(red: 0.97, green: 0.95, blue: 0.89, alpha: 1) {
        didSet { refreshScreenplayOverlay() }
    }
    var pageTextColor = NSColor(calibratedWhite: 0.08, alpha: 1) {
        didSet { refreshScreenplayOverlay() }
    }
    var isScreenplayPaginationActive: Bool = false {
        didSet {
            guard isScreenplayPaginationActive != oldValue else { return }
            refreshScreenplayOverlay()
        }
    }

    var screenplayPageCount: Int = 1 {
        didSet {
            guard screenplayPageCount != oldValue else { return }
            refreshScreenplayOverlay()
        }
    }

    var numberedScenes: [ScreenplayScene] = [] {
        didSet { if numberedScenes != oldValue { refreshScreenplayOverlay() } }
    }

    override var isOpaque: Bool { false }

    private lazy var screenplayOverlay = ScreenplayFurnitureView(frame: .zero)
    private weak var observedClipView: NSClipView?

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let observedClipView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        observedClipView = enclosingScrollView?.contentView
        if let observedClipView {
            observedClipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(viewportDidScroll), name: NSView.boundsDidChangeNotification, object: observedClipView)
        }
        refreshScreenplayOverlay()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func viewportDidScroll() { refreshScreenplayOverlay() }

    func refreshScreenplayOverlay() {
        if screenplayOverlay.superview == nil {
            screenplayOverlay.textView = self
            screenplayOverlay.wantsLayer = true
            screenplayOverlay.layer?.zPosition = 1
            addSubview(screenplayOverlay, positioned: .above, relativeTo: nil)
        }
        // Keep the backing layer viewport-sized even for thousand-page scripts.
        let viewport = visibleRect
        screenplayOverlay.frame = viewport
        screenplayOverlay.bounds = viewport
        screenplayOverlay.isHidden = !isScreenplayPaginationActive
        screenplayOverlay.needsDisplay = true
    }

    fileprivate func drawScreenplayFurniture(in dirtyRect: NSRect) {
        guard isScreenplayPaginationActive else { return }
        // TextKit 2 renders glyphs in layers. A transparent sibling layer keeps
        // margin furniture above the native editor's background without eating clicks.
        drawScreenplayPages(in: dirtyRect)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: pageTextColor
        ]
        for (number, rect) in sceneNumberPlacements() where dirtyRect.intersects(rect) {
            number.draw(at: NSPoint(x: 40, y: rect.minY), withAttributes: attrs)
            number.draw(at: NSPoint(x: 548, y: rect.minY), withAttributes: attrs)
        }
    }

    func sceneNumberPlacements() -> [(String, NSRect)] {
        numberedScenes.compactMap { scene in
            guard scene.location < (string as NSString).length else { return nil }
            let lineRect: NSRect
            if let manager = textLayoutManager, let content = manager.textContentManager,
               let location = content.location(content.documentRange.location, offsetBy: scene.location),
               let fragment = manager.textLayoutFragment(for: location) {
                let line = fragment.textLineFragments.first?.typographicBounds ?? .zero
                lineRect = NSRect(x: 0, y: fragment.layoutFragmentFrame.minY + line.minY,
                                  width: bounds.width, height: max(line.height, 14))
            } else if textLayoutManager == nil, let manager = layoutManager {
                let glyph = manager.glyphIndexForCharacter(at: scene.location)
                lineRect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else {
                return nil
            }
            return (scene.displayNumber, NSRect(x: 0, y: lineRect.minY + textContainerInset.height,
                                                width: bounds.width, height: lineRect.height))
        }
    }

    private func drawScreenplayPages(in dirtyRect: NSRect) {
        let seamColor = pageTextColor.withAlphaComponent(0.28)
        let numberColor = pageTextColor.withAlphaComponent(0.72)
        let pageWidth = ScreenplayPageLayout.pageSize.width
        let pageHeight = ScreenplayPageLayout.pageSize.height

        for pageIndex in 0..<max(screenplayPageCount, 1) {
            let pageRect = NSRect(
                x: 0,
                y: CGFloat(pageIndex) * pageHeight,
                width: pageWidth,
                height: pageHeight
            )
            guard dirtyRect.intersects(pageRect) else { continue }

            if pageIndex > 0 {
                seamColor.setStroke()
                let seam = NSBezierPath()
                seam.move(to: NSPoint(x: 0, y: pageRect.minY))
                seam.line(to: NSPoint(x: pageWidth, y: pageRect.minY))
                seam.lineWidth = 1
                seam.stroke()
            }

            let number = "\(pageIndex + 1)."
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: numberColor
            ]
            let size = number.size(withAttributes: attrs)
            let point = NSPoint(
                x: pageRect.maxX - ScreenplayPageLayout.horizontalInset + 12,
                y: pageRect.minY + 18 - size.height / 2
            )
            number.draw(at: point, withAttributes: attrs)
        }
    }
}

private final class ScreenplayFurnitureView: NSView {
    weak var textView: ScreenplayTextView?
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        textView?.drawScreenplayFurniture(in: dirtyRect)
    }
}

/// Immutable render configuration; safe even if TextKit requests link attributes
/// outside the main actor. The editor retains it because TextKit's delegate is weak.
private final class ContrastLinkRenderingDelegate: NSObject, NSTextLayoutManagerDelegate {
    private let foreground: NSColor
    init(foreground: NSColor) { self.foreground = foreground }

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, renderingAttributesForLink link: Any,
                           at location: NSTextLocation, defaultAttributes renderingAttributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any]? {
        [.foregroundColor: foreground, .underlineStyle: NSUnderlineStyle.single.rawValue]
    }
}

struct TextKit2EditorView: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    let onEdit: () -> Void
    let onScreenplayElementChange: (ScreenplayElement) -> Void
    let onPaginationChange: (Int) -> Void
    let onCodePositionChange: (Int, Int, Int) -> Void
    let bridge: FormattingBridge
    let companionLexicon: MongrelDictionaryCompanionLexicon
    let authoringMode: AuthoringMode
    let screenplayElement: ScreenplayElement
    let codeLanguage: CodeLanguage
    let codeTheme: CodeTheme
    let codeFont: CodeFont
    let codeFontSize: CGFloat
    let codeUseTabs: Bool
    let codeTabWidth: Int
    let codeLineWrap: Bool
    let editorZoom: CGFloat
    let typewriterMode: Bool
    let pageBackgroundColor: NSColor
    let pageTextColor: NSColor
    var documentID: UUID? = nil
    var numberedScenes: [ScreenplayScene] = []
    var contrastPolarity: MongrelContrastPolarity? = nil
    var onScreenplayCursorChange: (Int) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.textContainer = textContainer

        let textView = ScreenplayTextView(frame: .zero, textContainer: textContainer)
        textView.numberedScenes = numberedScenes
        textView.isRichText = true
        textView.usesFontPanel = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.delegate = context.coordinator
        textView.defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.35
            return style
        }()

        contentStorage.textStorage?.setAttributedString(attributedText)

        let scrollView = EditorScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        // The SwiftUI canvas owns zoom so its allocated size always matches
        // AppKit's magnification. Independent pinch zoom would desynchronize them.
        scrollView.allowsMagnification = false
        scrollView.minMagnification = 0.6
        scrollView.maxMagnification = 2
        scrollView.magnification = 1
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.startObservingCompanionLexicon()
        context.coordinator.lastMode = authoringMode
        context.coordinator.lastDocumentID = documentID
        context.coordinator.lastDocumentSnapshot = attributedText
        context.coordinator.lastLanguage = codeLanguage
        context.coordinator.lastTheme = codeTheme
        context.coordinator.lastCodeFont = codeFont
        context.coordinator.lastCodeFontSize = codeFontSize
        context.coordinator.lastScreenplayElement = screenplayElement
        context.coordinator.lastZoom = editorZoom
        context.coordinator.lastTypewriterMode = typewriterMode
        context.coordinator.lastPageBackgroundColor = pageBackgroundColor
        context.coordinator.lastPageTextColor = pageTextColor
        context.coordinator.lastContrastPolarity = contrastPolarity
        bridge.textView = textView
        bridge.documentTextColor = pageTextColor
        context.coordinator.applyEditorMode(authoringMode, to: textView, updatePublishedState: false)
        context.coordinator.applyCompanionSpellings(to: textView, fullDocument: true)
        context.coordinator.updateScreenplayPagination(for: textView, reportChange: false)
        context.coordinator.updateMagnification(editorZoom, in: scrollView)
        context.coordinator.scheduleStateReport(for: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        guard !context.coordinator.isApplyingEdit else { return }
        context.coordinator.parent = self

        let changedDocument = context.coordinator.lastDocumentID != documentID
        context.coordinator.lastDocumentID = documentID
        let needsDocumentSync = changedDocument || (context.coordinator.lastDocumentSnapshot !== attributedText && (authoringMode == .code
            ? textView.string != attributedText.string
            : !textView.attributedString().isEqual(to: attributedText)))
        context.coordinator.lastDocumentSnapshot = attributedText
        if needsDocumentSync {
            context.coordinator.isApplyingEdit = true
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            if changedDocument {
                context.coordinator.resetDocumentEditingState(in: textView)
            } else {
                let location = min(selection.location, attributedText.length)
                textView.setSelectedRange(NSRange(location: location, length: min(selection.length, attributedText.length - location)))
            }
            context.coordinator.paginationNeedsUpdate = true
            if authoringMode == .code {
                context.coordinator.applyCodeHighlighting(to: textView)
            }
            context.coordinator.isApplyingEdit = false
        }

        if context.coordinator.lastMode != authoringMode {
            context.coordinator.lastMode = authoringMode
            context.coordinator.applyEditorMode(authoringMode, to: textView, updatePublishedState: false)
            context.coordinator.updateScreenplayPagination(for: textView, reportChange: false)
        }

        if !context.coordinator.lastPageBackgroundColor.isEqual(pageBackgroundColor)
            || !context.coordinator.lastPageTextColor.isEqual(pageTextColor) {
            context.coordinator.lastPageBackgroundColor = pageBackgroundColor
            context.coordinator.lastPageTextColor = pageTextColor
            bridge.documentTextColor = pageTextColor
            context.coordinator.applyPagePalette(to: textView)
        }

        if context.coordinator.lastScreenplayElement != screenplayElement {
            context.coordinator.lastScreenplayElement = screenplayElement
            if authoringMode == .screenplay {
                bridge.configureTypingAttributes(
                    for: screenplayElement,
                    in: textView,
                    updatePublishedState: false
                )
                context.coordinator.applyEditorPresentation(to: textView, refreshRendering: false)
            }
        }

        if let screenplayTextView = textView as? ScreenplayTextView {
            screenplayTextView.numberedScenes = numberedScenes
        }

        if context.coordinator.lastLanguage != codeLanguage
            || context.coordinator.lastTheme != codeTheme
            || context.coordinator.lastCodeFont != codeFont
            || context.coordinator.lastCodeFontSize != codeFontSize {
            context.coordinator.lastLanguage = codeLanguage
            context.coordinator.lastTheme = codeTheme
            context.coordinator.lastCodeFont = codeFont
            context.coordinator.lastCodeFontSize = codeFontSize
            if authoringMode == .code {
                if let viewport = nsView as? EditorScrollView {
                    viewport.preservingAnchor { context.coordinator.applyCodeHighlighting(to: textView) }
                } else {
                    context.coordinator.applyCodeHighlighting(to: textView)
                }
            }
        }

        if context.coordinator.lastUseTabs != codeUseTabs || context.coordinator.lastTabWidth != codeTabWidth {
            context.coordinator.lastUseTabs = codeUseTabs
            context.coordinator.lastTabWidth = codeTabWidth
            if authoringMode == .code {
                context.coordinator.applyFormattingPrefs(useTabs: codeUseTabs, tabWidth: codeTabWidth, to: textView)
            }
        }

        if context.coordinator.lastLineWrap != codeLineWrap {
            context.coordinator.lastLineWrap = codeLineWrap
            context.coordinator.applyLineWrap(codeLineWrap, to: nsView)
        }

        if abs(context.coordinator.lastZoom - editorZoom) > 0.001 {
            context.coordinator.lastZoom = editorZoom
            context.coordinator.updateMagnification(editorZoom, in: nsView)
        }

        if context.coordinator.lastTypewriterMode != typewriterMode {
            context.coordinator.lastTypewriterMode = typewriterMode
            if typewriterMode {
                context.coordinator.centerSelection(in: textView)
            }
        }

        if context.coordinator.lastContrastPolarity != contrastPolarity || needsDocumentSync {
            context.coordinator.lastContrastPolarity = contrastPolarity
            context.coordinator.applyEditorPresentation(to: textView)
        }

        context.coordinator.scheduleStateReport(for: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextKit2EditorView
        weak var textView: NSTextView?
        var isApplyingEdit = false
        var lastMode: AuthoringMode = .prose
        var lastDocumentID: UUID?
        var lastDocumentSnapshot: NSAttributedString?
        var paginationNeedsUpdate = true
        private var paginationWorkItem: DispatchWorkItem?
        private var pendingInsertedRange: NSRange?
        private var codeHighlightWorkItem: DispatchWorkItem?
        private var pendingFormattingAnchor: EditorScrollView.Anchor?
        private var codeSyntaxExpressions: [CodeLanguage: NSRegularExpression] = [:]
        var lastLanguage: CodeLanguage = .swift
        var lastTheme: CodeTheme = .studio
        var lastCodeFont: CodeFont = .systemMono
        var lastCodeFontSize: CGFloat = 14
        var lastUseTabs: Bool = false
        var lastTabWidth: Int = 4
        var lastLineWrap: Bool = false
        var lastScreenplayElement: ScreenplayElement = .action
        var lastZoom: CGFloat = 1
        var lastTypewriterMode: Bool = false
        var lastPageBackgroundColor: NSColor = .clear
        var lastPageTextColor: NSColor = .clear
        var lastContrastPolarity: MongrelContrastPolarity?
        var ignoredCompanionWords: Set<String> = []
        private var stateReportGeneration = 0
        private let editorUndoManager = UndoManager()
        private var linkRenderingDelegate: ContrastLinkRenderingDelegate?

        init(_ parent: TextKit2EditorView) {
            self.parent = parent
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            editorUndoManager
        }

        func resetDocumentEditingState(in textView: NSTextView) {
            cancelPendingCodeHighlighting()
            textView.breakUndoCoalescing()
            textView.undoManager?.removeAllActions()
            pendingInsertedRange = nil
            pendingFormattingAnchor = nil
            ignoredCompanionWords.removeAll()
            lastMode = parent.authoringMode
            // NSTextView retains typing attributes when its storage becomes empty.
            // A fresh tab must not inherit a heading font or another tab's element.
            applyEditorMode(parent.authoringMode, to: textView, updatePublishedState: false)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func startObservingCompanionLexicon() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(companionLexiconDidFinishLoading(_:)),
                name: MongrelDictionaryCompanionLexicon.didFinishLoadingNotification,
                object: parent.companionLexicon
            )
        }

        @objc private func companionLexiconDidFinishLoading(_ notification: Notification) {
            guard let textView else { return }
            ignoredCompanionWords.removeAll()
            applyCompanionSpellings(to: textView, fullDocument: true)
        }

        func scheduleStateReport(for textView: NSTextView) {
            stateReportGeneration += 1
            let generation = stateReportGeneration
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self,
                      let textView,
                      self.textView === textView,
                      self.stateReportGeneration == generation else { return }
                self.parent.bridge.updateFormattingState(from: textView)
                if self.parent.authoringMode == .screenplay {
                    self.reportScreenplayElement(self.parent.bridge.activeScreenplayElement)
                    self.parent.onScreenplayCursorChange(textView.selectedRange().location)
                    if self.paginationNeedsUpdate {
                        self.scheduleScreenplayPagination(for: textView)
                    } else if let editor = textView as? ScreenplayTextView {
                        self.parent.onPaginationChange(editor.screenplayPageCount)
                    }
                } else if self.parent.authoringMode == .code {
                    self.reportCodePosition(in: textView)
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            guard !isApplyingEdit else { return }
            // Native completion can synchronously insert its preview and send a
            // second didChangeText. Guard before calling AppKit, not afterwards.
            isApplyingEdit = true
            defer { isApplyingEdit = false }

            if parent.authoringMode == .code {
                if !textView.hasMarkedText(), textView.undoManager?.isUndoing != true,
                   textView.undoManager?.isRedoing != true, shouldTriggerCompletion(in: textView) {
                    textView.complete(nil)
                }
                updateCodeHighlightingAfterEdit(in: textView)
                reportCodePosition(in: textView)
            }

            applyCompanionSpellings(to: textView)
            if parent.authoringMode == .screenplay, !textView.hasMarkedText(),
               !parent.bridge.isApplyingExplicitFormatting,
               (textView as? ScreenplayTextView)?.isPastingNativeContent != true,
               textView.undoManager?.isUndoing != true, textView.undoManager?.isRedoing != true {
                if let range = pendingInsertedRange {
                    parent.bridge.formatInsertedScreenplay(in: textView, range: range)
                }
                _ = parent.bridge.autoFormatScreenplay(in: textView)
            }
            let refreshEntirePresentation = pendingInsertedRange != nil || parent.bridge.isApplyingExplicitFormatting
                || textView.undoManager?.isUndoing == true || textView.undoManager?.isRedoing == true
            pendingInsertedRange = nil
            paginationNeedsUpdate = true
            let snapshot = NSAttributedString(attributedString: textView.attributedString())
            lastDocumentSnapshot = snapshot
            parent.attributedText = snapshot
            parent.onEdit()
            parent.bridge.updateFormattingState(from: textView)
            applyEditorPresentation(to: textView, refreshRendering: refreshEntirePresentation)
            let formattingAnchor = pendingFormattingAnchor
            pendingFormattingAnchor = nil
            if let anchor = formattingAnchor, let viewport = textView.enclosingScrollView as? EditorScrollView {
                viewport.synchronizeDocumentGeometry()
                viewport.restoreAnchor(anchor)
            }
            if parent.authoringMode == .screenplay {
                reportScreenplayElement(parent.bridge.activeScreenplayElement)
                parent.onScreenplayCursorChange(textView.selectedRange().location)
                scheduleScreenplayPagination(for: textView)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView, !isApplyingEdit else { return }
            parent.bridge.updateFormattingState(from: textView)
            if parent.authoringMode == .screenplay {
                reportScreenplayElement(parent.bridge.activeScreenplayElement)
                parent.onScreenplayCursorChange(textView.selectedRange().location)
            }
            if parent.authoringMode == .code {
                reportCodePosition(in: textView)
            }
            if parent.typewriterMode {
                centerSelection(in: textView)
            }
        }

        func textView(
            _ textView: NSTextView,
            completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            let source = textView.string as NSString
            guard charRange.location != NSNotFound, charRange.location >= 0,
                  charRange.length >= 0, charRange.location <= source.length,
                  charRange.length <= source.length - charRange.location else { return [] }
            let prefix = source.substring(with: charRange).lowercased()
            guard prefix.count >= 2 else { return words }

            if parent.authoringMode == .code {
                let matches = currentKeywords().filter { $0.lowercased().hasPrefix(prefix) }
                return matches.isEmpty ? words : matches
            }

            let matches = parent.companionLexicon.suggestions(for: prefix, limit: 8)
            if matches.isEmpty {
                return words
            }

            let merged = Array(NSOrderedSet(array: matches + words))
                .compactMap { $0 as? String }
            return merged
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            if replacementString == nil {
                pendingFormattingAnchor = (textView.enclosingScrollView as? EditorScrollView)?.captureAnchor()
            }
            if let replacementString,
               replacementString.utf16.count > 1, replacementString.contains(where: \.isNewline) {
                pendingInsertedRange = NSRange(location: affectedCharRange.location, length: replacementString.utf16.count)
            }
            guard parent.authoringMode == .code,
                  let replacementString,
                  (replacementString as NSString).length == 1,
                  let edit = CodeTextEditing.insertClosingDelimiter(
                    replacementString,
                    in: textView.string,
                    selection: affectedCharRange,
                    tabWidth: parent.codeTabWidth
                  ) else { return true }
            applyCodeEdit(edit, to: textView)
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if parent.authoringMode == .code {
                switch commandSelector {
                case #selector(NSResponder.insertNewline(_:)):
                    applyCodeEdit(CodeTextEditing.insertNewline(
                        in: textView.string,
                        selection: textView.selectedRange(),
                        language: parent.codeLanguage,
                        useTabs: parent.codeUseTabs,
                        tabWidth: parent.codeTabWidth
                    ), to: textView)
                    return true
                case #selector(NSResponder.insertTab(_:)):
                    applyCodeEdit(CodeTextEditing.indent(
                        textView.string,
                        selection: textView.selectedRange(),
                        useTabs: parent.codeUseTabs,
                        tabWidth: parent.codeTabWidth
                    ), to: textView)
                    return true
                case #selector(NSResponder.insertBacktab(_:)):
                    applyCodeEdit(CodeTextEditing.outdent(
                        textView.string,
                        selection: textView.selectedRange(),
                        tabWidth: parent.codeTabWidth
                    ), to: textView)
                    return true
                default:
                    return false
                }
            }

            guard parent.authoringMode == .screenplay else { return false }

            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                let nextElement = parent.bridge.nextScreenplayElementOnReturn(in: textView)
                textView.insertText("\n", replacementRange: textView.selectedRange())
                parent.bridge.configureTypingAttributes(for: nextElement, in: textView)
                reportScreenplayElement(nextElement)
                return true
            case #selector(NSResponder.insertTab(_:)):
                let nextElement = parent.bridge.detectedScreenplayElement(in: textView).cycled(step: 1)
                parent.bridge.applyScreenplayElement(nextElement, to: textView)
                reportScreenplayElement(nextElement)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                let previousElement = parent.bridge.detectedScreenplayElement(in: textView).cycled(step: -1)
                parent.bridge.applyScreenplayElement(previousElement, to: textView)
                reportScreenplayElement(previousElement)
                return true
            default:
                return false
            }
        }

        func reportCodePosition(in textView: NSTextView) {
            guard parent.authoringMode == .code else { return }
            let position = CodeTextEditing.cursorPosition(in: textView.string, selection: textView.selectedRange())
            parent.onCodePositionChange(position.line, position.column, position.selectionLength)
        }

        private func reportScreenplayElement(_ element: ScreenplayElement) {
            guard parent.screenplayElement != element else { return }
            parent.onScreenplayElementChange(element)
        }

        private func applyCodeEdit(_ edit: CodeEditResult, to textView: NSTextView) {
            guard edit.text != textView.string else { return }
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            guard textView.shouldChangeText(in: fullRange, replacementString: edit.text) else { return }
            textView.textStorage?.replaceCharacters(in: fullRange, with: edit.text)
            textView.setSelectedRange(edit.selection)
            textView.didChangeText()
        }

        func applyEditorMode(
            _ mode: AuthoringMode,
            to textView: NSTextView,
            updatePublishedState: Bool = true
        ) {
            cancelPendingCodeHighlighting()
            (textView as? ScreenplayTextView)?.screenplayBridge = parent.bridge
            switch mode {
            case .prose:
                if let screenplayTextView = textView as? ScreenplayTextView {
                    screenplayTextView.isScreenplayPaginationActive = false
                    screenplayTextView.screenplayPageCount = 1
                }
                textView.isAutomaticQuoteSubstitutionEnabled = true
                textView.isAutomaticTextReplacementEnabled = true
                textView.isAutomaticSpellingCorrectionEnabled = true
                textView.isContinuousSpellCheckingEnabled = true
                textView.drawsBackground = true
                textView.backgroundColor = parent.pageBackgroundColor
                applyStandardDocumentMetrics(to: textView)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineHeightMultiple = 1.35
                let textColor = parent.pageTextColor
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraph
                ]
                textView.defaultParagraphStyle = paragraph
                textView.insertionPointColor = textColor
            case .code:
                if let screenplayTextView = textView as? ScreenplayTextView {
                    screenplayTextView.isScreenplayPaginationActive = false
                    screenplayTextView.screenplayPageCount = 1
                }
                textView.isAutomaticQuoteSubstitutionEnabled = false
                textView.isAutomaticTextReplacementEnabled = false
                textView.isAutomaticSpellingCorrectionEnabled = false
                textView.isContinuousSpellCheckingEnabled = false
                textView.drawsBackground = false
                applyStandardDocumentMetrics(to: textView)
                textView.textContainerInset = NSSize(width: 28, height: 24)
                if let scrollView = textView.enclosingScrollView {
                    applyLineWrap(parent.codeLineWrap, to: scrollView)
                }
                applyFormattingPrefs(useTabs: parent.codeUseTabs, tabWidth: parent.codeTabWidth, to: textView)
                applyCodeHighlighting(to: textView)
            case .screenplay:
                if let screenplayTextView = textView as? ScreenplayTextView {
                    screenplayTextView.isScreenplayPaginationActive = true
                }
                textView.isAutomaticQuoteSubstitutionEnabled = false
                textView.isAutomaticTextReplacementEnabled = false
                textView.isAutomaticSpellingCorrectionEnabled = true
                textView.isContinuousSpellCheckingEnabled = true
                textView.drawsBackground = true
                textView.backgroundColor = parent.pageBackgroundColor
                applyScreenplayPageMetrics(to: textView)
                parent.bridge.configureTypingAttributes(
                    for: parent.screenplayElement,
                    in: textView,
                    updatePublishedState: updatePublishedState
                )
            }
            applyPagePalette(to: textView)
        }

        func applyPagePalette(to textView: NSTextView) {
            guard parent.authoringMode != .code else { return }
            parent.bridge.documentTextColor = parent.pageTextColor
            textView.drawsBackground = true
            textView.backgroundColor = parent.pageBackgroundColor
            textView.insertionPointColor = parent.pageTextColor
            textView.typingAttributes[.foregroundColor] = parent.pageTextColor
            if let screenplayTextView = textView as? ScreenplayTextView {
                screenplayTextView.pageBackgroundColor = parent.pageBackgroundColor
                screenplayTextView.pageTextColor = parent.pageTextColor
            }
            applyEditorPresentation(to: textView)
        }

        /// Rendering attributes change the working surface without putting theme
        /// colors into the document, clipboard, undo history, or exported pages.
        func applyEditorPresentation(to textView: NSTextView, refreshRendering: Bool = true) {
            let polarity = parent.contrastPolarity
            let foreground = polarity?.foreground ?? parent.pageTextColor
            let background = polarity?.background ?? parent.pageBackgroundColor
            if let polarity {
                textView.appearance = NSAppearance(named: polarity == .black ? .darkAqua : .aqua)
                textView.drawsBackground = true
                textView.backgroundColor = background
                textView.insertionPointColor = foreground
                textView.selectedTextAttributes = [.backgroundColor: foreground, .foregroundColor: background]
                textView.linkTextAttributes = [.foregroundColor: foreground, .underlineStyle: NSUnderlineStyle.single.rawValue]
                textView.enclosingScrollView?.scrollerKnobStyle = polarity == .black ? .light : .dark
            } else {
                textView.appearance = nil
                textView.drawsBackground = parent.authoringMode != .code
                textView.backgroundColor = background
                let caret = parent.authoringMode == .code ? currentTheme().caret : foreground
                textView.insertionPointColor = caret
                textView.selectedTextAttributes = parent.authoringMode == .code
                    ? [.backgroundColor: caret.withAlphaComponent(0.24), .foregroundColor: currentTheme().base]
                    : [.backgroundColor: NSColor.selectedTextBackgroundColor, .foregroundColor: NSColor.selectedTextColor]
                textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
            }
            if parent.authoringMode == .prose {
                textView.textContainerInset = polarity == nil ? NSSize(width: 16, height: 16) : NSSize(width: 38, height: 34)
            }
            if let editor = textView as? ScreenplayTextView {
                editor.pageBackgroundColor = background
                editor.pageTextColor = foreground
            }
            if let manager = textView.textLayoutManager {
                manager.renderingAttributesValidator = polarity == nil ? nil : { [weak self] manager, fragment in
                    self?.applyContrastRendering(to: manager, range: fragment.rangeInElement)
                }
                if refreshRendering {
                    linkRenderingDelegate = polarity.map { ContrastLinkRenderingDelegate(foreground: $0.foreground) }
                    manager.delegate = linkRenderingDelegate
                    manager.invalidateRenderingAttributes(for: manager.documentRange)
                    if polarity != nil { applyContrastRendering(to: manager, range: manager.documentRange) }
                } else if polarity != nil, let content = manager.textContentManager {
                    // AppKit can replace the active paragraph's rendering attributes
                    // after validating the other fragments during native typing/paste.
                    // Repaint that paragraph without invalidating the whole document.
                    let text = textView.string as NSString
                    let selection = textView.selectedRange()
                    let start = min(selection.location, text.length)
                    let range = text.paragraphRange(for: NSRange(location: start, length: min(selection.length, text.length - start)))
                    if range.length > 0,
                       let begin = content.location(content.documentRange.location, offsetBy: range.location),
                       let end = content.location(begin, offsetBy: range.length),
                       let textRange = NSTextRange(location: begin, end: end) {
                        applyContrastRendering(to: manager, range: textRange)
                    }
                }
            } else if let manager = textView.layoutManager, let storage = textView.textStorage {
                let range = NSRange(location: 0, length: storage.length)
                manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
                manager.removeTemporaryAttribute(.font, forCharacterRange: range)
                manager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
                manager.removeTemporaryAttribute(.underlineColor, forCharacterRange: range)
                manager.removeTemporaryAttribute(.strikethroughColor, forCharacterRange: range)
                if polarity != nil {
                    for (run, attributes) in contrastRenderingRuns(in: range, storage: storage) {
                        manager.addTemporaryAttributes(attributes, forCharacterRange: run)
                    }
                }
            }
            textView.needsDisplay = true
        }

        private func applyContrastRendering(to manager: NSTextLayoutManager, range: NSTextRange) {
            guard parent.contrastPolarity != nil, let content = manager.textContentManager,
                  let storage = textView?.textStorage else { return }
            let start = content.offset(from: content.documentRange.location, to: range.location)
            let end = content.offset(from: content.documentRange.location, to: range.endLocation)
            guard start >= 0, end >= start, end <= storage.length else { return }
            for (run, attributes) in contrastRenderingRuns(in: NSRange(location: start, length: end - start), storage: storage) {
                guard let begin = content.location(content.documentRange.location, offsetBy: run.location),
                      let finish = content.location(begin, offsetBy: run.length),
                      let textRange = NSTextRange(location: begin, end: finish) else { continue }
                manager.setRenderingAttributes(attributes, for: textRange)
            }
        }

        private func contrastRenderingRuns(in range: NSRange, storage: NSTextStorage) -> [(NSRange, [NSAttributedString.Key: Any])] {
            guard let polarity = parent.contrastPolarity else { return [] }
            let foreground = polarity.foreground
            let base: [NSAttributedString.Key: Any] = [
                .foregroundColor: foreground,
                .underlineColor: foreground,
                .strikethroughColor: foreground
            ]
            if parent.authoringMode != .code {
                var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
                storage.enumerateAttribute(.backgroundColor, in: range) { color, run, _ in
                    var attributes = base
                    // Retain visible highlighting while preventing imported yellow
                    // or dark fills from defeating the monochrome text contrast.
                    let highlighted = (color as? NSColor).map { $0.alphaComponent > 0 } ?? false
                    attributes[.backgroundColor] = highlighted
                        ? foreground.withAlphaComponent(polarity == .black ? 0.20 : 0.12) : NSColor.clear
                    runs.append((run, attributes))
                }
                return runs
            }
            let theme = currentTheme()
            var runs: [(NSRange, [NSAttributedString.Key: Any])] = []
            storage.enumerateAttribute(.foregroundColor, in: range) { color, run, _ in
                let color = color as? NSColor
                var attributes = base
                let gray: CGFloat?
                if color == theme.comment {
                    gray = polarity == .black ? 0.66 : 0.34
                    attributes[.font] = NSFontManager.shared.convert(self.codeFont(weight: .regular), toHaveTrait: .italicFontMask)
                } else if color == theme.string {
                    gray = polarity == .black ? 0.84 : 0.16
                } else if color == theme.number {
                    gray = polarity == .black ? 0.92 : 0.08
                } else { gray = nil }
                if let gray { attributes[.foregroundColor] = NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1) }
                runs.append((run, attributes))
            }
            return runs
        }

        func applyFormattingPrefs(useTabs: Bool, tabWidth: Int, to textView: NSTextView) {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = 1.35
            let tabPts = CGFloat(tabWidth) * 8.0
            style.defaultTabInterval = tabPts
            style.tabStops = []
            textView.defaultParagraphStyle = style
            if useTabs {
                textView.isAutomaticTextReplacementEnabled = false
            }
        }

        func applyLineWrap(_ wrap: Bool, to scrollView: NSScrollView) {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            if let editorScroll = scrollView as? EditorScrollView {
                editorScroll.preservingAnchor {
                    editorScroll.layoutMode = wrap ? .reflow : .unwrapped
                    editorScroll.hasHorizontalScroller = !wrap
                }
                return
            }
            scrollView.hasHorizontalScroller = !wrap
            if wrap {
                textView.isHorizontallyResizable = false
                textView.textContainer?.widthTracksTextView = true
                textView.textContainer?.containerSize = NSSize(
                    width: scrollView.contentSize.width,
                    height: CGFloat.greatestFiniteMagnitude
                )
            } else {
                textView.isHorizontallyResizable = true
                textView.textContainer?.widthTracksTextView = false
                textView.textContainer?.containerSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
        }

        private func applyStandardDocumentMetrics(to textView: NSTextView) {
            (textView.enclosingScrollView as? EditorScrollView)?.layoutMode = .reflow
            textView.enclosingScrollView?.hasHorizontalScroller = false
            textView.minSize = .zero
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.exclusionPaths = []
            textView.textContainerInset = NSSize(width: 16, height: 16)
        }

        private func applyScreenplayPageMetrics(to textView: NSTextView) {
            (textView.enclosingScrollView as? EditorScrollView)?.layoutMode = .screenplay
            textView.enclosingScrollView?.hasHorizontalScroller = false
            textView.minSize = NSSize(width: ScreenplayPageLayout.pageSize.width, height: 0)
            textView.maxSize = NSSize(width: ScreenplayPageLayout.pageSize.width, height: .greatestFiniteMagnitude)
            textView.autoresizingMask = []
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: ScreenplayPageLayout.contentWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            // Full-width exclusions create a real bottom and top margin at each
            // page boundary instead of merely painting a line behind flowing text.
            textView.textContainer?.exclusionPaths = ScreenplayPageLayout.exclusionPaths()
            textView.textContainerInset = NSSize(
                width: ScreenplayPageLayout.horizontalInset,
                height: ScreenplayPageLayout.verticalInset
            )
        }

        func scheduleScreenplayPagination(for textView: NSTextView) {
            guard paginationNeedsUpdate else { return }
            paginationWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, self.textView === textView else { return }
                self.updateScreenplayPagination(for: textView)
            }
            paginationWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }

        func updateScreenplayPagination(for textView: NSTextView, reportChange: Bool = true) {
            guard parent.authoringMode == .screenplay else { return }
            paginationWorkItem?.cancel()
            paginationNeedsUpdate = false

            var contentHeight = measuredScreenplayContentHeight(in: textView)
            var requiredPages = ScreenplayPageLayout.pageCount(forLaidOutContentHeight: contentHeight)
            while let container = textView.textContainer, requiredPages >= container.exclusionPaths.count + 1 {
                container.exclusionPaths = ScreenplayPageLayout.exclusionPaths(maximumPageCount: requiredPages + 100)
                contentHeight = measuredScreenplayContentHeight(in: textView)
                requiredPages = ScreenplayPageLayout.pageCount(forLaidOutContentHeight: contentHeight)
            }
            let requiredHeight = CGFloat(requiredPages) * ScreenplayPageLayout.pageSize.height
            let visibleHeight = textView.enclosingScrollView?.documentVisibleRect.height
                ?? ScreenplayPageLayout.pageSize.height
            let finalHeight = max(requiredHeight, visibleHeight)

            let requiredSize = NSSize(width: ScreenplayPageLayout.pageSize.width, height: finalHeight)
            if textView.minSize != requiredSize {
                textView.minSize = requiredSize
            }
            if textView.frame.size != requiredSize {
                textView.setFrameSize(requiredSize)
            }

            if let screenplayTextView = textView as? ScreenplayTextView,
               screenplayTextView.screenplayPageCount != requiredPages {
                screenplayTextView.screenplayPageCount = requiredPages
            }

            (textView as? ScreenplayTextView)?.refreshScreenplayOverlay()
            if reportChange {
                parent.onPaginationChange(requiredPages)
            }
        }

        func updateMagnification(_ magnification: CGFloat, in scrollView: NSScrollView) {
            if let editorScroll = scrollView as? EditorScrollView {
                editorScroll.setEditorMagnification(magnification)
                return
            }
            let previousOrigin = scrollView.documentVisibleRect.origin
            scrollView.magnification = magnification

            // Width is allocated by SwiftUI at the same scale, so x must stay at
            // the document origin. Retain vertical reading position in document units.
            let visibleHeight = scrollView.documentVisibleRect.height
            let documentHeight = scrollView.documentView?.bounds.height ?? visibleHeight
            let maximumY = max(0, documentHeight - visibleHeight)
            scrollView.contentView.setBoundsOrigin(
                NSPoint(x: 0, y: min(max(0, previousOrigin.y), maximumY))
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func centerSelection(in textView: NSTextView) {
            guard let scrollView = textView.enclosingScrollView else { return }
            let selection = textView.selectedRange()
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let screenRect = textView.firstRect(forCharacterRange: selection, actualRange: &actualRange)
            guard !screenRect.isEmpty, let window = textView.window else { return }

            let windowRect = window.convertFromScreen(screenRect)
            let localRect = textView.convert(windowRect, from: nil)
            let clipView = scrollView.contentView
            let maximumY = max(0, textView.bounds.height - clipView.bounds.height)
            let targetY = min(max(0, localRect.midY - (clipView.bounds.height * 0.45)), maximumY)
            clipView.animator().setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
        }

        private func measuredScreenplayContentHeight(in textView: NSTextView) -> CGFloat {
            if let textLayoutManager = textView.textLayoutManager {
                textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)
                var maxY: CGFloat = 0
                textLayoutManager.enumerateTextLayoutFragments(from: textLayoutManager.documentRange.location) { fragment in
                    maxY = max(maxY, fragment.layoutFragmentFrame.maxY)
                    return true
                }
                return maxY
            }

            if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
                layoutManager.ensureLayout(for: textContainer)
                return layoutManager.usedRect(for: textContainer).height
            }

            return 0
        }

        func applyCompanionSpellings(to textView: NSTextView, fullDocument: Bool = false) {
            guard parent.authoringMode != .code else { return }
            guard parent.companionLexicon.status.isAvailable else { return }

            let scopedText: String
            if fullDocument {
                scopedText = textView.string
            } else {
                let range = (textView.string as NSString).paragraphRange(for: textView.selectedRange())
                scopedText = (textView.string as NSString).substring(with: range)
            }

            let spellChecker = NSSpellChecker.shared
            let documentTag = textView.spellCheckerDocumentTag

            for token in parent.companionLexicon.tokenizedCompanionWords(in: scopedText) where ignoredCompanionWords.insert(token).inserted {
                spellChecker.ignoreWord(token, inSpellDocumentWithTag: documentTag)
            }
        }

        private func shouldTriggerCompletion(in textView: NSTextView) -> Bool {
            let cursor = textView.selectedRange().location
            let text = textView.string as NSString
            guard cursor != NSNotFound, cursor > 1, cursor <= text.length else { return false }
            var start = cursor
            while start > 0, cursor - start <= 128 {
                let ch = text.character(at: start - 1)
                let isAlphanumeric = UnicodeScalar(ch).map(CharacterSet.alphanumerics.contains) ?? false
                if !(isAlphanumeric || ch == 95) {
                    break
                }
                start -= 1
            }
            let length = cursor - start
            guard length >= 2, length <= 128 else { return false }
            let palette = currentTheme()
            let color = textView.textStorage?.attribute(.foregroundColor, at: cursor - 1, effectiveRange: nil) as? NSColor
            guard color != palette.comment, color != palette.string else { return false }
            let prefix = text.substring(with: NSRange(location: start, length: length)).lowercased()
            // Native completion consults the system spellchecker. Only ask for a
            // useful keyword prefix, not every identifier, string, or comment.
            return currentKeywords().contains { $0.count > prefix.count && $0.lowercased().hasPrefix(prefix) }
        }

        private func currentKeywords() -> [String] {
            switch parent.codeLanguage {
            case .swift:
                return [
                    "func", "var", "let", "struct", "class", "enum", "protocol", "extension", "import", "return",
                    "if", "else", "switch", "case", "for", "while", "guard", "defer", "async", "await", "throws",
                    "try", "catch", "public", "private", "internal", "fileprivate", "static", "self", "super"
                ]
            case .javascript:
                return [
                    "function", "const", "let", "var", "class", "import", "export", "return", "if", "else", "switch",
                    "case", "for", "while", "try", "catch", "finally", "async", "await", "new", "this"
                ]
            case .typescript:
                return [
                    "interface", "type", "namespace", "declare", "implements", "extends", "public", "private",
                    "protected", "readonly", "function", "const", "let", "class", "import", "export", "return",
                    "if", "else", "switch", "case", "for", "while", "try", "catch", "async", "await", "new", "this"
                ]
            case .python:
                return [
                    "def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "try", "except",
                    "with", "as", "async", "await", "pass", "break", "continue", "lambda", "None", "True", "False"
                ]
            case .json:
                return ["true", "false", "null"]
            case .html:
                return [
                    "html", "head", "body", "main", "section", "article", "header", "footer", "nav", "div", "span",
                    "script", "style", "link", "meta", "form", "input", "button", "label", "table", "template"
                ]
            case .css:
                return [
                    "color", "background", "display", "position", "margin", "padding", "border", "width", "height",
                    "grid", "flex", "font", "transform", "transition", "animation", "var", "calc", "important"
                ]
            case .shell:
                return [
                    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
                    "function", "in", "export", "local", "readonly", "return", "break", "continue"
                ]
            case .markdown:
                return []
            case .yaml:
                return ["true", "false", "null", "yes", "no", "on", "off"]
            case .sql:
                return [
                    "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "GROUP", "ORDER",
                    "BY", "HAVING", "LIMIT", "OFFSET", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE",
                    "ALTER", "DROP", "TABLE", "VIEW", "INDEX", "AS", "AND", "OR", "NOT", "NULL", "BEGIN", "COMMIT"
                ]
            }
        }

        private func currentTheme() -> (
            base: NSColor,
            keyword: NSColor,
            string: NSColor,
            comment: NSColor,
            number: NSColor,
            caret: NSColor
        ) {
            switch parent.codeTheme {
            case .studio:
                return (
                    NSColor(calibratedRed: 0.86, green: 0.88, blue: 0.91, alpha: 1),
                    NSColor(calibratedRed: 0.45, green: 0.67, blue: 0.93, alpha: 1),
                    NSColor(calibratedRed: 0.86, green: 0.67, blue: 0.42, alpha: 1),
                    NSColor(calibratedRed: 0.47, green: 0.63, blue: 0.51, alpha: 1),
                    NSColor(calibratedRed: 0.72, green: 0.61, blue: 0.88, alpha: 1),
                    NSColor(calibratedRed: 0.55, green: 0.76, blue: 1.0, alpha: 1)
                )
            case .paper:
                return (
                    NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.18, alpha: 1),
                    NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.62, alpha: 1),
                    NSColor(calibratedRed: 0.52, green: 0.27, blue: 0.08, alpha: 1),
                    NSColor(calibratedRed: 0.30, green: 0.43, blue: 0.32, alpha: 1),
                    NSColor(calibratedRed: 0.45, green: 0.23, blue: 0.51, alpha: 1),
                    NSColor(calibratedRed: 0.08, green: 0.35, blue: 0.72, alpha: 1)
                )
            case .midnight:
                return (
                    NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 1),
                    NSColor(calibratedRed: 0.42, green: 0.78, blue: 1.0, alpha: 1),
                    NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.43, alpha: 1),
                    NSColor(calibratedRed: 0.55, green: 0.76, blue: 0.59, alpha: 1),
                    NSColor(calibratedRed: 0.82, green: 0.69, blue: 1.0, alpha: 1),
                    NSColor.white
                )
            case .cobalt:
                return (
                    NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.96, alpha: 1),
                    NSColor(calibratedRed: 0.47, green: 0.73, blue: 1.0, alpha: 1),
                    NSColor(calibratedRed: 0.94, green: 0.77, blue: 0.43, alpha: 1),
                    NSColor(calibratedRed: 0.53, green: 0.77, blue: 0.54, alpha: 1),
                    NSColor(calibratedRed: 0.78, green: 0.64, blue: 0.98, alpha: 1),
                    NSColor(calibratedRed: 0.47, green: 0.73, blue: 1.0, alpha: 1)
                )
            case .frost:
                return (
                    NSColor(calibratedRed: 0.85, green: 0.95, blue: 0.95, alpha: 1),
                    NSColor(calibratedRed: 0.39, green: 0.89, blue: 0.88, alpha: 1),
                    NSColor(calibratedRed: 0.99, green: 0.82, blue: 0.64, alpha: 1),
                    NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.73, alpha: 1),
                    NSColor(calibratedRed: 0.72, green: 0.73, blue: 1.0, alpha: 1),
                    NSColor(calibratedRed: 0.39, green: 0.89, blue: 0.88, alpha: 1)
                )
            case .amber:
                return (
                    NSColor(calibratedRed: 0.98, green: 0.92, blue: 0.84, alpha: 1),
                    NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.23, alpha: 1),
                    NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.54, alpha: 1),
                    NSColor(calibratedRed: 0.76, green: 0.86, blue: 0.52, alpha: 1),
                    NSColor(calibratedRed: 0.91, green: 0.65, blue: 0.98, alpha: 1),
                    NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.23, alpha: 1)
                )
            }
        }

        private func commentPattern() -> String {
            switch parent.codeLanguage {
            case .python, .shell, .yaml:
                return "#.*"
            case .json:
                return ""
            case .swift, .javascript, .typescript, .css:
                return "//.*|/\\*[\\s\\S]*?\\*/"
            case .html, .markdown:
                return "<!--[\\s\\S]*?-->"
            case .sql:
                return "--.*|/\\*[\\s\\S]*?\\*/"
            }
        }

        private func cancelPendingCodeHighlighting() {
            codeHighlightWorkItem?.cancel()
            codeHighlightWorkItem = nil
        }

        private func updateCodeHighlightingAfterEdit(in textView: NSTextView) {
            cancelPendingCodeHighlighting()
            guard (textView.textStorage?.length ?? 0) > 24_000 else {
                applyCodeHighlighting(to: textView)
                return
            }
            // Keep native typing immediate. One syntax pass follows a burst of edits;
            // changing language, theme, mode, or document still refreshes immediately.
            let documentID = parent.documentID
            let work = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, self.textView === textView,
                      self.parent.documentID == documentID, self.parent.authoringMode == .code else { return }
                self.flushPendingCodeHighlighting()
            }
            codeHighlightWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: work)
        }

        func flushPendingCodeHighlighting() {
            guard codeHighlightWorkItem != nil, parent.authoringMode == .code, let textView else { return }
            applyCodeHighlighting(to: textView)
            let snapshot = NSAttributedString(attributedString: textView.attributedString())
            lastDocumentSnapshot = snapshot
            parent.attributedText = snapshot
        }

        private func codeSyntaxExpression() -> NSRegularExpression? {
            if let cached = codeSyntaxExpressions[parent.codeLanguage] { return cached }
            let comments = commentPattern().isEmpty ? "(?!)" : commentPattern()
            let strings = #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#
            let numbers = #"\b(?:0[xX][0-9a-fA-F]+|[0-9]+(?:\.[0-9]+)?)\b"#
            let keywords = currentKeywords().map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            let words = keywords.isEmpty ? "(?!)" : "\\b(?:" + keywords + ")\\b"
            let pattern = "(?<comment>" + comments + ")|(?<string>" + strings
                + ")|(?<number>" + numbers + ")|(?<keyword>" + words + ")"
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if parent.codeLanguage == .sql { options.insert(.caseInsensitive) }
            let expression = try? NSRegularExpression(pattern: pattern, options: options)
            codeSyntaxExpressions[parent.codeLanguage] = expression
            return expression
        }

        fileprivate func applyCodeHighlighting(to textView: NSTextView) {
            cancelPendingCodeHighlighting()
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)

            let palette = currentTheme()
            let baseFont = codeFont(weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.25
            let typingAttributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: palette.base,
                .paragraphStyle: paragraph
            ]
            textView.typingAttributes = typingAttributes
            textView.defaultParagraphStyle = paragraph
            textView.insertionPointColor = palette.caret
            textView.selectedTextAttributes = [
                .backgroundColor: palette.caret.withAlphaComponent(0.24),
                .foregroundColor: palette.base
            ]
            guard fullRange.length > 0 else {
                applyEditorPresentation(to: textView)
                return
            }

            storage.beginEditing()
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: palette.base,
                .paragraphStyle: paragraph
            ], range: fullRange)

            let keywordFont = codeFont(weight: .semibold)
            // A single lexical pass consumes strings and comments as complete tokens.
            // Quotes inside comments and comment markers inside strings cannot leak.
            codeSyntaxExpression()?.enumerateMatches(in: storage.string, range: fullRange) { match, _, _ in
                guard let match else { return }
                let color: NSColor
                if match.range(withName: "comment").location != NSNotFound {
                    color = palette.comment
                } else if match.range(withName: "string").location != NSNotFound {
                    color = palette.string
                } else if match.range(withName: "number").location != NSNotFound {
                    color = palette.number
                } else {
                    color = palette.keyword
                    storage.addAttribute(.font, value: keywordFont, range: match.range)
                }
                storage.addAttribute(.foregroundColor, value: color, range: match.range)
            }

            storage.endEditing()
            applyEditorPresentation(to: textView)
        }

        private func codeFont(weight: NSFont.Weight) -> NSFont {
            let size = parent.codeFontSize
            switch parent.codeFont {
            case .systemMono:
                return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            case .menlo:
                let name = weight.rawValue >= NSFont.Weight.semibold.rawValue ? "Menlo-Bold" : "Menlo-Regular"
                return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            case .monaco:
                return NSFont(name: "Monaco", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            }
        }
    }
}
