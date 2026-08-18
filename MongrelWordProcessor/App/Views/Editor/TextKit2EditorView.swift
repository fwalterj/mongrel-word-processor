import SwiftUI
import AppKit

private final class ScreenplayTextView: NSTextView {
    var isScreenplayPaginationActive: Bool = false {
        didSet { needsDisplay = true }
    }

    var screenplayPageCount: Int = 1 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if isScreenplayPaginationActive {
            drawScreenplayPages(in: dirtyRect)
        }
        super.draw(dirtyRect)
    }

    private func drawScreenplayPages(in dirtyRect: NSRect) {
        let pageColor = NSColor(calibratedWhite: 0.995, alpha: 1)
        let seamColor = NSColor(calibratedWhite: 0.84, alpha: 1)
        let numberColor = NSColor(calibratedWhite: 0.38, alpha: 1)
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
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.lastMode = authoringMode
        context.coordinator.lastLanguage = codeLanguage
        context.coordinator.lastTheme = codeTheme
        context.coordinator.lastScreenplayElement = screenplayElement
        bridge.textView = textView
        context.coordinator.applyEditorMode(authoringMode, to: textView)
        context.coordinator.applyCompanionSpellings(to: textView, fullDocument: true)
        bridge.updateFormattingState(from: textView)
        context.coordinator.updateScreenplayPagination(for: textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        guard !context.coordinator.isApplyingEdit else { return }

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
                let nextElement = parent.bridge.detectedScreenplayElement(in: textView).nextOnReturn
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
                applyStandardDocumentMetrics(to: textView)
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineHeightMultiple = 1.35
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraph
                ]
                textView.defaultParagraphStyle = paragraph
                textView.insertionPointColor = .labelColor
            case .code:
                if let screenplayTextView = textView as? ScreenplayTextView {
                    screenplayTextView.isScreenplayPaginationActive = false
                    screenplayTextView.screenplayPageCount = 1
                }
                textView.isAutomaticQuoteSubstitutionEnabled = false
                textView.isAutomaticTextReplacementEnabled = false
                textView.isAutomaticSpellingCorrectionEnabled = false
                textView.isContinuousSpellCheckingEnabled = false
                applyStandardDocumentMetrics(to: textView)
                applyCodeHighlighting(to: textView)
            case .screenplay:
                if let screenplayTextView = textView as? ScreenplayTextView {
                    screenplayTextView.isScreenplayPaginationActive = true
                }
                textView.isAutomaticQuoteSubstitutionEnabled = false
                textView.isAutomaticTextReplacementEnabled = false
                textView.isAutomaticSpellingCorrectionEnabled = true
                textView.isContinuousSpellCheckingEnabled = true
                applyScreenplayPageMetrics(to: textView)
                parent.bridge.configureTypingAttributes(for: parent.screenplayElement, in: textView)
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
            if wrap {
                textView.textContainer?.widthTracksTextView = true
                textView.textContainer?.containerSize = NSSize(
                    width: scrollView.contentSize.width,
                    height: CGFloat.greatestFiniteMagnitude
                )
            } else {
                textView.textContainer?.widthTracksTextView = false
                textView.textContainer?.containerSize = NSSize(
                    width: 10_000,
                    height: CGFloat.greatestFiniteMagnitude
                )
            }
        }

        private func applyStandardDocumentMetrics(to textView: NSTextView) {
            textView.minSize = .zero
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainerInset = NSSize(width: 16, height: 16)
        }

        private func applyScreenplayPageMetrics(to textView: NSTextView) {
            textView.minSize = NSSize(width: ScreenplayPageLayout.pageSize.width, height: 0)
            textView.maxSize = NSSize(width: ScreenplayPageLayout.pageSize.width, height: .greatestFiniteMagnitude)
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.textContainer?.widthTracksTextView = false
            textView.textContainer?.containerSize = NSSize(
                width: ScreenplayPageLayout.contentWidth,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.textContainerInset = NSSize(
                width: ScreenplayPageLayout.horizontalInset,
                height: ScreenplayPageLayout.verticalInset
            )
        }

        func updateScreenplayPagination(for textView: NSTextView) {
            guard parent.authoringMode == .screenplay else { return }

            let contentHeight = measuredScreenplayContentHeight(in: textView)
            let pageContentHeight = ScreenplayPageLayout.pageSize.height - (ScreenplayPageLayout.verticalInset * 2)
            let requiredPages = max(1, Int(ceil(max(contentHeight, 1) / pageContentHeight)))
            let requiredHeight = CGFloat(requiredPages) * ScreenplayPageLayout.pageSize.height
            let visibleHeight = textView.enclosingScrollView?.contentSize.height ?? ScreenplayPageLayout.pageSize.height
            let finalHeight = max(requiredHeight, visibleHeight)

            textView.minSize = NSSize(width: ScreenplayPageLayout.pageSize.width, height: finalHeight)
            textView.setFrameSize(NSSize(width: ScreenplayPageLayout.pageSize.width, height: finalHeight))

            if let screenplayTextView = textView as? ScreenplayTextView {
                screenplayTextView.screenplayPageCount = requiredPages
            }

            parent.onPaginationChange(requiredPages)
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
                if !(CharacterSet.alphanumerics.contains(UnicodeScalar(ch)!) || ch == 95) {
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
