import SwiftUI
import AppKit
import SharedFoundation

private final class ScreenplayTextView: NSTextView {
    var pageBackgroundColor = NSColor(red: 0.97, green: 0.95, blue: 0.89, alpha: 1) {
        didSet { needsDisplay = true }
    }
    var pageTextColor = NSColor(calibratedWhite: 0.08, alpha: 1) {
        didSet { needsDisplay = true }
    }
    var isScreenplayPaginationActive: Bool = false {
        didSet {
            guard isScreenplayPaginationActive != oldValue else { return }
            needsDisplay = true
        }
    }

    var screenplayPageCount: Int = 1 {
        didSet {
            guard screenplayPageCount != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if isScreenplayPaginationActive {
            drawScreenplayPages(in: dirtyRect)
        }
        super.draw(dirtyRect)
    }

    private func drawScreenplayPages(in dirtyRect: NSRect) {
        let pageColor = pageBackgroundColor
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

            pageColor.setFill()
            pageRect.fill()

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

struct TextKit2EditorView: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    let onEdit: () -> Void
    let onScreenplayElementChange: (ScreenplayElement) -> Void
    let onPaginationChange: (Int) -> Void
    let bridge: FormattingBridge
    let companionLexicon: MongrelDictionaryCompanionLexicon
    let authoringMode: AuthoringMode
    let screenplayElement: ScreenplayElement
    let codeLanguage: CodeLanguage
    let codeTheme: CodeTheme
    let codeUseTabs: Bool
    let codeTabWidth: Int
    let codeLineWrap: Bool
    let editorZoom: CGFloat
    let typewriterMode: Bool
    let pageBackgroundColor: NSColor
    let pageTextColor: NSColor

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

        let scrollView = NSScrollView()
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
        context.coordinator.lastMode = authoringMode
        context.coordinator.lastLanguage = codeLanguage
        context.coordinator.lastTheme = codeTheme
        context.coordinator.lastScreenplayElement = screenplayElement
        context.coordinator.lastZoom = editorZoom
        context.coordinator.lastTypewriterMode = typewriterMode
        context.coordinator.lastPageBackgroundColor = pageBackgroundColor
        context.coordinator.lastPageTextColor = pageTextColor
        bridge.textView = textView
        bridge.documentTextColor = pageTextColor
        context.coordinator.applyEditorMode(authoringMode, to: textView)
        context.coordinator.applyCompanionSpellings(to: textView, fullDocument: true)
        bridge.updateFormattingState(from: textView)
        context.coordinator.updateScreenplayPagination(for: textView)
        context.coordinator.updateMagnification(editorZoom, in: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        guard !context.coordinator.isApplyingEdit else { return }
        context.coordinator.parent = self

        if !textView.attributedString().isEqual(to: attributedText) {
            context.coordinator.isApplyingEdit = true
            textView.textStorage?.setAttributedString(attributedText)
            context.coordinator.isApplyingEdit = false
        }

        if context.coordinator.lastMode != authoringMode {
            context.coordinator.lastMode = authoringMode
            context.coordinator.applyEditorMode(authoringMode, to: textView)
            context.coordinator.updateScreenplayPagination(for: textView)
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
                bridge.configureTypingAttributes(for: screenplayElement, in: textView)
            }
        }

        if authoringMode == .screenplay {
            context.coordinator.updateScreenplayPagination(for: textView)
        }

        if context.coordinator.lastLanguage != codeLanguage || context.coordinator.lastTheme != codeTheme {
            context.coordinator.lastLanguage = codeLanguage
            context.coordinator.lastTheme = codeTheme
            if authoringMode == .code {
                context.coordinator.applyCodeHighlighting(to: textView)
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
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TextKit2EditorView
        weak var textView: NSTextView?
        var isApplyingEdit = false
        var lastMode: AuthoringMode = .prose
        var lastLanguage: CodeLanguage = .swift
        var lastTheme: CodeTheme = .cobalt
        var lastUseTabs: Bool = false
        var lastTabWidth: Int = 4
        var lastLineWrap: Bool = false
        var lastScreenplayElement: ScreenplayElement = .action
        var lastZoom: CGFloat = 1
        var lastTypewriterMode: Bool = false
        var lastPageBackgroundColor: NSColor = .clear
        var lastPageTextColor: NSColor = .clear
        var ignoredCompanionWords: Set<String> = []

        init(_ parent: TextKit2EditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            guard !isApplyingEdit else { return }

            if parent.authoringMode == .code {
                applyCodeHighlighting(to: textView)
                if shouldTriggerCompletion(in: textView) {
                    textView.complete(nil)
                }
            }

            isApplyingEdit = true
            applyCompanionSpellings(to: textView)
            let activeElement: ScreenplayElement
            if parent.authoringMode == .screenplay {
                activeElement = parent.bridge.autoFormatScreenplay(in: textView)
            } else {
                activeElement = parent.bridge.activeScreenplayElement
            }
            parent.attributedText = textView.attributedString()
            parent.onEdit()
            parent.bridge.updateFormattingState(from: textView)
            if parent.authoringMode == .screenplay {
                parent.onScreenplayElementChange(activeElement)
                updateScreenplayPagination(for: textView)
            }
            isApplyingEdit = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.bridge.updateFormattingState(from: textView)
            if parent.authoringMode == .screenplay {
                parent.onScreenplayElementChange(parent.bridge.activeScreenplayElement)
                updateScreenplayPagination(for: textView)
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
            let prefix = (textView.string as NSString).substring(with: charRange).lowercased()
            guard prefix.count >= 2 else { return words }

            if parent.authoringMode == .code {
                let matches = currentKeywords().filter { $0.hasPrefix(prefix) }
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

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard parent.authoringMode == .screenplay else { return false }

            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                let nextElement = parent.bridge.nextScreenplayElementOnReturn(in: textView)
                textView.insertText("\n", replacementRange: textView.selectedRange())
                parent.bridge.configureTypingAttributes(for: nextElement, in: textView)
                parent.onScreenplayElementChange(nextElement)
                return true
            case #selector(NSResponder.insertTab(_:)):
                let nextElement = parent.bridge.detectedScreenplayElement(in: textView).cycled(step: 1)
                parent.bridge.applyScreenplayElement(nextElement, to: textView)
                parent.onScreenplayElementChange(nextElement)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                let previousElement = parent.bridge.detectedScreenplayElement(in: textView).cycled(step: -1)
                parent.bridge.applyScreenplayElement(previousElement, to: textView)
                parent.onScreenplayElementChange(previousElement)
                return true
            default:
                return false
            }
        }

        func applyEditorMode(_ mode: AuthoringMode, to textView: NSTextView) {
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
                parent.bridge.configureTypingAttributes(for: parent.screenplayElement, in: textView)
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
            textView.enclosingScrollView?.hasHorizontalScroller = false
            textView.minSize = .zero
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.exclusionPaths = []
            textView.textContainerInset = NSSize(width: 16, height: 16)
        }

        private func applyScreenplayPageMetrics(to textView: NSTextView) {
            textView.enclosingScrollView?.hasHorizontalScroller = false
            textView.minSize = NSSize(width: ScreenplayPageLayout.pageSize.width, height: 0)
            textView.maxSize = NSSize(width: ScreenplayPageLayout.pageSize.width, height: .greatestFiniteMagnitude)
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

        func updateScreenplayPagination(for textView: NSTextView) {
            guard parent.authoringMode == .screenplay else { return }

            let contentHeight = measuredScreenplayContentHeight(in: textView)
            let requiredPages = ScreenplayPageLayout.pageCount(forLaidOutContentHeight: contentHeight)
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

            parent.onPaginationChange(requiredPages)
        }

        func updateMagnification(_ magnification: CGFloat, in scrollView: NSScrollView) {
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
            guard cursor != NSNotFound, cursor > 1 else { return false }
            let text = textView.string as NSString
            var start = cursor - 1
            while start > 0 {
                let ch = text.character(at: start - 1)
                let isAlphanumeric = UnicodeScalar(ch).map(CharacterSet.alphanumerics.contains) ?? false
                if !(isAlphanumeric || ch == 95) {
                    break
                }
                start -= 1
            }
            let length = cursor - start
            return length >= 2
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
            case .python:
                return [
                    "def", "class", "import", "from", "return", "if", "elif", "else", "for", "while", "try", "except",
                    "with", "as", "async", "await", "pass", "break", "continue", "lambda", "None", "True", "False"
                ]
            case .json:
                return ["true", "false", "null"]
            }
        }

        private func currentTheme() -> (base: NSColor, keyword: NSColor, string: NSColor, comment: NSColor, caret: NSColor) {
            let appearance = MongrelAppearancePreferences.shared
            if appearance.mode != .standard {
                let text = NSColor(appearance.text)
                return (text, text, text, text.withAlphaComponent(0.72), text)
            }
            switch parent.codeTheme {
            case .cobalt:
                return (
                    NSColor(calibratedRed: 0.88, green: 0.91, blue: 0.96, alpha: 1),
                    NSColor(calibratedRed: 0.47, green: 0.73, blue: 1.0, alpha: 1),
                    NSColor(calibratedRed: 0.94, green: 0.77, blue: 0.43, alpha: 1),
                    NSColor(calibratedRed: 0.53, green: 0.77, blue: 0.54, alpha: 1),
                    NSColor(calibratedRed: 0.47, green: 0.73, blue: 1.0, alpha: 1)
                )
            case .frost:
                return (
                    NSColor(calibratedRed: 0.85, green: 0.95, blue: 0.95, alpha: 1),
                    NSColor(calibratedRed: 0.39, green: 0.89, blue: 0.88, alpha: 1),
                    NSColor(calibratedRed: 0.99, green: 0.82, blue: 0.64, alpha: 1),
                    NSColor(calibratedRed: 0.62, green: 0.86, blue: 0.73, alpha: 1),
                    NSColor(calibratedRed: 0.39, green: 0.89, blue: 0.88, alpha: 1)
                )
            case .amber:
                return (
                    NSColor(calibratedRed: 0.98, green: 0.92, blue: 0.84, alpha: 1),
                    NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.23, alpha: 1),
                    NSColor(calibratedRed: 0.98, green: 0.84, blue: 0.54, alpha: 1),
                    NSColor(calibratedRed: 0.76, green: 0.86, blue: 0.52, alpha: 1),
                    NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.23, alpha: 1)
                )
            }
        }

        private func commentPattern() -> String {
            switch parent.codeLanguage {
            case .python:
                return "#.*"
            case .json:
                return ""
            case .swift, .javascript:
                return "//.*"
            }
        }

        fileprivate func applyCodeHighlighting(to textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            guard fullRange.length > 0 else { return }

            let palette = currentTheme()
            let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = 1.25

            storage.beginEditing()
            storage.setAttributes([
                .font: baseFont,
                .foregroundColor: palette.base,
                .paragraphStyle: paragraph
            ], range: fullRange)

            let source = storage.string as NSString
            let keywords = currentKeywords()
            if !keywords.isEmpty {
                let keywordPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
                if let regex = try? NSRegularExpression(pattern: keywordPattern) {
                    regex.matches(in: source as String, range: fullRange).forEach { match in
                        storage.addAttribute(.foregroundColor, value: palette.keyword, range: match.range)
                        storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold), range: match.range)
                    }
                }
            }

            if let stringRegex = try? NSRegularExpression(pattern: "\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'") {
                stringRegex.matches(in: source as String, range: fullRange).forEach { match in
                    storage.addAttribute(.foregroundColor, value: palette.string, range: match.range)
                }
            }

            let commentPattern = commentPattern()
            if !commentPattern.isEmpty,
               let commentRegex = try? NSRegularExpression(pattern: commentPattern, options: [.anchorsMatchLines]) {
                commentRegex.matches(in: source as String, range: fullRange).forEach { match in
                    storage.addAttribute(.foregroundColor, value: palette.comment, range: match.range)
                }
            }

            storage.endEditing()
            textView.typingAttributes[.font] = baseFont
            textView.insertionPointColor = palette.caret
        }
    }
}
