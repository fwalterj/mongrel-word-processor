import AppKit
import SharedFoundation

private struct ScreenplayStyle {
    let font: NSFont
    let paragraphStyle: NSParagraphStyle
    let uppercase: Bool
}

struct ScreenplaySuggestion: Identifiable, Hashable {
    enum Behavior: Hashable {
        case replaceParagraph
        case appendSlugSuffix
    }

    let label: String
    let text: String
    let element: ScreenplayElement
    let behavior: Behavior

    var id: String {
        "\(element.rawValue):\(behavior):\(label):\(text)"
    }
}

struct EditorLocationSnapshot {
    var selection: NSRange = NSRange(location: 0, length: 0)
    var visibleOrigin: NSPoint = .zero
}

/// Bridges formatting toolbar actions to the first-responder NSTextView.
///
/// Bold / italic / underline / alignment are sent through the NSResponder chain
/// so NSTextView handles them natively (no tight coupling needed).
/// Strikethrough and heading styles require direct text-storage access, so
/// the Coordinator stores a weak reference to the active NSTextView here.
@MainActor
final class FormattingBridge: ObservableObject {

    /// Set by TextKit2EditorView.Coordinator after the NSTextView is created.
    weak var textView: NSTextView?
    var documentTextColor: NSColor = .labelColor
    var documentCatalog: ScreenplayCatalog?
    private(set) var isApplyingExplicitFormatting = false
    private var restoreGeneration = 0

    // MARK: – Active-state publishers (updated on every selection change)
    @Published private(set) var isBold: Bool = false
    @Published private(set) var isItalic: Bool = false
    @Published private(set) var isUnderline: Bool = false
    @Published private(set) var isStrikethrough: Bool = false
    @Published private(set) var activeScreenplayElement: ScreenplayElement = .action
    @Published private(set) var screenplaySuggestions: [ScreenplaySuggestion] = []

    func captureEditorLocation() -> EditorLocationSnapshot {
        guard let textView else { return EditorLocationSnapshot() }
        return EditorLocationSnapshot(
            selection: textView.selectedRange(),
            visibleOrigin: textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
        )
    }

    func restoreEditorLocation(_ snapshot: EditorLocationSnapshot) {
        restoreGeneration += 1
        let generation = restoreGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.restoreGeneration == generation, let textView = self.textView else { return }
            let length = (textView.string as NSString).length
            let location = min(max(0, snapshot.selection.location), length)
            let selection = NSRange(
                location: location,
                length: min(max(0, snapshot.selection.length), length - location)
            )
            textView.setSelectedRange(selection)
            if let contentView = textView.enclosingScrollView?.contentView {
                let maximumX = max(0, textView.bounds.width - contentView.bounds.width)
                let maximumY = max(0, textView.bounds.height - contentView.bounds.height)
                contentView.scroll(to: NSPoint(
                    x: min(max(0, snapshot.visibleOrigin.x), maximumX),
                    y: min(max(0, snapshot.visibleOrigin.y), maximumY)
                ))
                textView.enclosingScrollView?.reflectScrolledClipView(contentView)
            }
            textView.window?.makeFirstResponder(textView)
        }
    }

    func showFontPanel() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        NSFontManager.shared.orderFrontFontPanel(nil)
    }

    func checkSpelling() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.checkTextInDocument(nil)
        NSSpellChecker.shared.spellingPanel.makeKeyAndOrderFront(nil)
    }

    func insertImageAttachment() {
        guard let textView else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentImageSupport.contentTypes
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Insert PNG, JPEG, HEIC, TIFF, GIF, or PDF artwork up to 20 MB."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try DocumentImageSupport.loadPageImage(from: url)
            guard let image = imported.image else {
                throw CocoaError(.fileReadCorruptFile)
            }

            let availableWidth = max(160, min(textView.bounds.width - 40, 640))
            if image.size.width > availableWidth {
                let scale = availableWidth / image.size.width
                image.size = NSSize(width: availableWidth, height: image.size.height * scale)
            }

            let wrapper = FileWrapper(regularFileWithContents: imported.data)
            wrapper.preferredFilename = imported.filename
            let attachment = NSTextAttachment(fileWrapper: wrapper)
            attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
            let replacement = NSAttributedString(attachment: attachment)
            let selectedRange = textView.selectedRange()

            textView.insertText(replacement, replacementRange: selectedRange)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not insert image"
            alert.informativeText = "Choose a valid PNG, JPEG, HEIC, TIFF, GIF, or PDF file no larger than 20 MB."
            alert.runModal()
        }
    }

    func focusRange(_ range: NSRange) {
        guard let textView,
              range.location >= 0,
              range.length >= 0,
              range.location <= textView.string.utf16.count,
              range.length <= textView.string.utf16.count - range.location else { return }
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    func toggleLineComment(prefix: String) {
        guard let textView else { return }
        applyCodeEdit(
            CodeTextEditing.toggleLineComment(
                textView.string,
                selection: textView.selectedRange(),
                prefix: prefix
            ),
            to: textView
        )
    }

    func duplicateSelectedLines() {
        guard let textView else { return }
        applyCodeEdit(
            CodeTextEditing.duplicateLines(textView.string, selection: textView.selectedRange()),
            to: textView
        )
    }

    private func applyCodeEdit(_ edit: CodeEditResult, to textView: NSTextView) {
        guard edit.text != textView.string else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        guard textView.shouldChangeText(in: fullRange, replacementString: edit.text) else { return }
        textView.textStorage?.replaceCharacters(in: fullRange, with: edit.text)
        textView.setSelectedRange(edit.selection)
        textView.didChangeText()
    }

    /// Called by Coordinator.textViewDidChangeSelection to refresh active-state flags.
    func updateFormattingState(from tv: NSTextView) {
        let range = tv.selectedRange()
        let attrs: [NSAttributedString.Key: Any]
        if range.length > 0,
           let textStorage = tv.textStorage,
           range.location < textStorage.length {
            attrs = textStorage.attributes(at: range.location, effectiveRange: nil)
        } else {
            attrs = tv.typingAttributes
        }

        // Bold / italic derive from the symbolic traits of the current font
        let newIsBold: Bool
        let newIsItalic: Bool
        if let font = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            newIsBold = traits.contains(.boldFontMask)
            newIsItalic = traits.contains(.italicFontMask)
        } else {
            newIsBold = false
            newIsItalic = false
        }
        if isBold != newIsBold { isBold = newIsBold }
        if isItalic != newIsItalic { isItalic = newIsItalic }

        // Underline — non-zero value means active
        let underlineVal = attrs[.underlineStyle] as? Int ?? 0
        let newIsUnderline = underlineVal != 0
        if isUnderline != newIsUnderline { isUnderline = newIsUnderline }

        // Strikethrough — check at selection start when there's a selection
        let newIsStrikethrough: Bool
        if range.length > 0, let ts = tv.textStorage, range.location < ts.length {
            let strikeVal = ts.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
            newIsStrikethrough = strikeVal != 0
        } else {
            let strikeVal = attrs[.strikethroughStyle] as? Int ?? 0
            newIsStrikethrough = strikeVal != 0
        }
        if isStrikethrough != newIsStrikethrough { isStrikethrough = newIsStrikethrough }

        let element = detectedScreenplayElement(in: tv)
        publishScreenplayState(
            element: element,
            suggestions: makeScreenplaySuggestions(in: tv, activeElement: element)
        )
    }

    // MARK: – Responder-chain actions (NSTextView handles these when first responder)

    func bold() {
        NSApp.sendAction(NSSelectorFromString("toggleBoldface:"), to: nil, from: nil)
    }

    func italic() {
        NSApp.sendAction(NSSelectorFromString("toggleItalics:"), to: nil, from: nil)
    }

    func underline() {
        NSApp.sendAction(NSSelectorFromString("toggleUnderline:"), to: nil, from: nil)
    }

    func alignLeft() {
        NSApp.sendAction(#selector(NSText.alignLeft(_:)), to: nil, from: nil)
    }

    func alignCenter() {
        NSApp.sendAction(#selector(NSText.alignCenter(_:)), to: nil, from: nil)
    }

    func alignRight() {
        NSApp.sendAction(#selector(NSText.alignRight(_:)), to: nil, from: nil)
    }

    func increaseFontSize() {
        NSApp.sendAction(NSSelectorFromString("increaseFontSize:"), to: nil, from: nil)
    }

    func decreaseFontSize() {
        NSApp.sendAction(NSSelectorFromString("decreaseFontSize:"), to: nil, from: nil)
    }

    // MARK: – Direct text-storage actions

    func applyScreenplayElement(_ element: ScreenplayElement) {
        guard let tv = textView else { return }
        applyScreenplayElement(element, to: tv)
    }

    func applyScreenplayElement(
        _ element: ScreenplayElement,
        to tv: NSTextView,
        notifyTextChange: Bool = true,
        updatePublishedState: Bool = true,
        isExplicit: Bool = true
    ) {
        let style = screenplayStyle(for: element)
        let selection = tv.selectedRange()
        let paragraphRange = (tv.string as NSString).paragraphRange(for: selection)
        let wasExplicit = isApplyingExplicitFormatting
        if notifyTextChange { isApplyingExplicitFormatting = true }
        defer { isApplyingExplicitFormatting = wasExplicit }

        if paragraphRange.length > 0, let ts = tv.textStorage {
            let original = (tv.string as NSString).substring(with: paragraphRange) as NSString
            let uppercased = (original as String).uppercased()
            // Length-changing case conversion during a native keystroke would
            // invalidate AppKit's pending undo range (for example ß -> SS).
            let changesCase = style.uppercase && (isExplicit || uppercased.utf16.count == original.length)
            let replacement = NSMutableAttributedString(attributedString: ts.attributedSubstring(from: paragraphRange))
            if changesCase, uppercased != original as String {
                replacement.replaceCharacters(in: NSRange(location: 0, length: replacement.length), with: uppercased)
            }
            let fullRange = NSRange(location: 0, length: replacement.length)
            applyScreenplayAttributes(for: element, to: replacement, range: fullRange)
            if isExplicit { replacement.addAttribute(.screenplayManualElement, value: element.rawValue, range: fullRange) }
            if notifyTextChange, !tv.shouldChangeText(in: paragraphRange, replacementString: replacement.string) { return }
            ts.replaceCharacters(in: paragraphRange, with: replacement)
            if changesCase {
                let start = min(max(0, selection.location - paragraphRange.location), original.length)
                let end = min(start + selection.length, original.length)
                let mappedStart = original.substring(to: start).uppercased().utf16.count
                let mappedEnd = original.substring(to: end).uppercased().utf16.count
                tv.setSelectedRange(NSRange(location: paragraphRange.location + mappedStart, length: mappedEnd - mappedStart))
            } else {
                tv.setSelectedRange(selection)
            }
        }

        configureTypingAttributes(for: element, in: tv, updatePublishedState: updatePublishedState)
        if notifyTextChange {
            tv.didChangeText()
        }
    }

    func configureTypingAttributes(
        for element: ScreenplayElement,
        in tv: NSTextView,
        updatePublishedState: Bool = true
    ) {
        var attrs = tv.typingAttributes
        attrs.removeValue(forKey: .screenplaySceneIdentity)
        attrs.removeValue(forKey: .screenplayManualElement)
        screenplayAttributes(for: element).forEach { attrs[$0.key] = $0.value }
        tv.typingAttributes = attrs
        tv.defaultParagraphStyle = screenplayStyle(for: element).paragraphStyle
        tv.insertionPointColor = documentTextColor
        if updatePublishedState {
            publishScreenplayState(
                element: element,
                suggestions: makeScreenplaySuggestions(in: tv, activeElement: element)
            )
        }
    }

    func detectedScreenplayElement(in tv: NSTextView) -> ScreenplayElement {
        let range = tv.selectedRange()

        if let ts = tv.textStorage, ts.length > 0 {
            let text = tv.string as NSString
            let location: Int?
            if range.location < ts.length {
                location = max(0, range.location)
            } else if ts.length > 0, text.character(at: ts.length - 1) != 10 {
                location = ts.length - 1
            } else {
                location = nil
            }

            if let location,
               let tagged = ts.attribute(.screenplayElement, at: location, effectiveRange: nil) as? String,
               let element = ScreenplayElement(rawValue: tagged) {
                return element
            }
        }

        if let tagged = tv.typingAttributes[.screenplayElement] as? String,
           let element = ScreenplayElement(rawValue: tagged) {
            return element
        }

        return activeScreenplayElement
    }

    func nextScreenplayElementOnReturn(in tv: NSTextView) -> ScreenplayElement {
        let current = detectedScreenplayElement(in: tv)
        let paragraph = currentParagraphText(in: tv, range: currentParagraphRange(in: tv))

        if paragraph.isEmpty {
            switch current {
            case .character, .parenthetical, .dialogue:
                return .action
            default:
                break
            }
        }
        return current.nextOnReturn
    }

    func focusScreenplayLocation(_ location: Int) {
        guard let textView else { return }
        let safeLocation = max(0, min(location, (textView.string as NSString).length))
        textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        textView.scrollRangeToVisible(NSRange(location: safeLocation, length: 0))
        textView.window?.makeFirstResponder(textView)
        updateFormattingState(from: textView)
    }

    func focusEditor() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        textView.scrollRangeToVisible(textView.selectedRange())
    }

    func autoFormatScreenplay(in tv: NSTextView) -> ScreenplayElement {
        let paragraphRange = currentParagraphRange(in: tv)
        let paragraph = currentParagraphText(in: tv, range: paragraphRange)
        let currentElement = detectedScreenplayElement(in: tv)
        let previousElement = previousNonEmptyScreenplayElement(before: paragraphRange.location, in: tv)
        let explicit = paragraphRange.location < (tv.textStorage?.length ?? 0)
            ? (tv.textStorage?.attribute(.screenplayManualElement, at: paragraphRange.location, effectiveRange: nil) as? String).flatMap(ScreenplayElement.init(rawValue:))
            : nil
        let inferredElement = explicit ?? inferScreenplayElement(
            for: paragraph,
            currentElement: currentElement,
            previousElement: previousElement
        )

        // Live formatting must not trim text or synthesize punctuation while the
        // writer is still typing. Full normalization remains an explicit action.
        applyScreenplayElement(inferredElement, to: tv, notifyTextChange: false, isExplicit: false)
        updateFormattingState(from: tv)
        return inferredElement
    }

    func autoFormatEntireScreenplay() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = NSRange(location: 0, length: storage.length)
        guard range.length > 0 else { return }
        let selection = tv.selectedRange()
        let formatted = formattedScreenplay(storage, normalize: true)
        let wasExplicit = isApplyingExplicitFormatting
        isApplyingExplicitFormatting = true
        defer { isApplyingExplicitFormatting = wasExplicit }
        guard !formatted.isEqual(to: storage), tv.shouldChangeText(in: range, replacementString: formatted.string) else { return }
        storage.setAttributedString(formatted)
        tv.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        configureTypingAttributes(for: detectedScreenplayElement(in: tv), in: tv)
        tv.didChangeText()
    }

    /// A multiline paste is one edit; format its paragraphs in one storage transaction.
    /// Text and punctuation are left intact. The explicit Auto action can normalize them.
    func formatInsertedScreenplay(in tv: NSTextView, range: NSRange) {
        guard let storage = tv.textStorage, range.location >= 0, range.length >= 0,
              range.location <= storage.length else { return }
        let safe = NSRange(location: range.location, length: min(range.length, storage.length - range.location))
        let paragraphs = (storage.string as NSString).paragraphRange(for: safe)
        let source = storage.attributedSubstring(from: paragraphs)
        let formatted = formattedScreenplay(source, normalize: false)
        let selection = tv.selectedRange()
        storage.beginEditing()
        storage.replaceCharacters(in: paragraphs, with: formatted)
        storage.endEditing()
        tv.setSelectedRange(selection)
        if selection.location > 0, selection.location <= storage.length,
           (storage.string as NSString).character(at: selection.location - 1) == 10,
           let raw = storage.attribute(.screenplayElement, at: selection.location - 1, effectiveRange: nil) as? String,
           let previous = ScreenplayElement(rawValue: raw) {
            configureTypingAttributes(for: previous.nextOnReturn, in: tv)
        }
    }

    private func formattedScreenplay(_ source: NSAttributedString, normalize: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let string = source.string as NSString
        var location = 0
        var previous: ScreenplayElement?
        while location < string.length {
            let range = string.paragraphRange(for: NSRange(location: location, length: 0))
            let original = string.substring(with: range)
            let value = original.trimmingCharacters(in: .whitespacesAndNewlines)
            let tagged = (source.attribute(.screenplayElement, at: location, effectiveRange: nil) as? String)
                .flatMap(ScreenplayElement.init(rawValue:))
            // Pasted text often inherits the preceding paragraph's attributes. Classify
            // the batch from its contents; explicit Auto preserves existing semantics.
            let current = normalize ? (tagged ?? .action) : .action
            let explicit = normalize ? (source.attribute(.screenplayManualElement, at: location, effectiveRange: nil) as? String).flatMap(ScreenplayElement.init(rawValue:)) : nil
            let element = explicit ?? inferScreenplayElement(for: value, currentElement: current, previousElement: previous)
            let paragraph = NSMutableAttributedString(attributedString: source.attributedSubstring(from: range))
            if !normalize {
                paragraph.removeAttribute(.screenplayManualElement, range: NSRange(location: 0, length: paragraph.length))
            }
            if normalize, !value.isEmpty {
                var normalized = value
                if element == .parenthetical {
                    if !normalized.hasPrefix("(") { normalized = "(" + normalized }
                    if !normalized.hasSuffix(")") { normalized += ")" }
                }
                if element == .transition, !normalized.hasSuffix(":"), !normalized.hasSuffix(".") { normalized += ":" }
                if screenplayStyle(for: element).uppercase { normalized = normalized.uppercased() }
                let ending = String(original.reversed().prefix(while: \.isNewline).reversed())
                // Avoid replacing unchanged text so mixed bold/italic runs survive.
                if normalized + ending != original { paragraph.replaceCharacters(in: NSRange(location: 0, length: paragraph.length), with: normalized + ending) }
            }
            applyScreenplayAttributes(for: element, to: paragraph, range: NSRange(location: 0, length: paragraph.length))
            result.append(paragraph)
            previous = value.isEmpty ? nil : element
            location = NSMaxRange(range)
        }
        return result
    }

    private func applyScreenplayAttributes(for element: ScreenplayElement, to text: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        var attributes = screenplayAttributes(for: element)
        let baseFont = attributes.removeValue(forKey: .font) as! NSFont
        let preservesEmphasis = element == .action || element == .dialogue || element == .parenthetical
        var fonts: [(NSRange, NSFont)] = []
        text.enumerateAttribute(.font, in: range) { value, run, _ in
            var font = baseFont
            if preservesEmphasis, let original = value as? NSFont {
                var traits = NSFontManager.shared.traits(of: original).intersection([.boldFontMask, .italicFontMask])
                if let raw = text.attribute(.screenplayElement, at: run.location, effectiveRange: nil) as? String,
                   let previous = ScreenplayElement(rawValue: raw), previous != element {
                    // A paste can inherit a bold heading font. Remove the old element's
                    // built-in traits while retaining emphasis the writer added.
                    let inherited = NSFontManager.shared.traits(of: screenplayStyle(for: previous).font)
                        .intersection([.boldFontMask, .italicFontMask])
                    traits.subtract(inherited)
                }
                font = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
            }
            fonts.append((run, font))
        }
        text.addAttributes(attributes, range: range)
        for (run, font) in fonts { text.addAttribute(.font, value: font, range: run) }
    }

    func applySuggestion(_ suggestion: ScreenplaySuggestion) {
        guard let tv = textView else { return }

        let paragraphRange = currentParagraphRange(in: tv)
        let currentText = currentParagraphText(in: tv, range: paragraphRange)
        let replacement = suggestion.behavior == .appendSlugSuffix
            ? appendedSlugSuffix(from: currentText, suffix: suggestion.text)
            : suggestion.text

        guard let storage = tv.textStorage else { return }
        let original = (tv.string as NSString).substring(with: paragraphRange)
        // A suggestion replaces the paragraph's contents, never its separator.
        // Dropping the newline would join the following action/dialogue to the cue.
        let ending = String(original.reversed().prefix(while: \.isNewline).reversed())
        var value = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        if suggestion.element == .parenthetical {
            if !value.hasPrefix("(") { value = "(" + value }
            if !value.hasSuffix(")") { value += ")" }
        }
        if suggestion.element == .transition, !value.hasSuffix(":"), !value.hasSuffix(".") { value += ":" }
        if screenplayStyle(for: suggestion.element).uppercase { value = value.uppercased() }
        let formatted = NSMutableAttributedString(string: value + ending, attributes: screenplayAttributes(for: suggestion.element))
        formatted.addAttribute(.screenplayManualElement, value: suggestion.element.rawValue, range: NSRange(location: 0, length: formatted.length))
        if paragraphRange.length > 0, let identity = storage.attribute(.screenplaySceneIdentity, at: paragraphRange.location, effectiveRange: nil) {
            formatted.addAttribute(.screenplaySceneIdentity, value: identity, range: NSRange(location: 0, length: formatted.length))
        }
        let wasExplicit = isApplyingExplicitFormatting
        isApplyingExplicitFormatting = true
        defer { isApplyingExplicitFormatting = wasExplicit }
        guard tv.shouldChangeText(in: paragraphRange, replacementString: formatted.string) else { return }
        storage.replaceCharacters(in: paragraphRange, with: formatted)
        tv.setSelectedRange(NSRange(location: paragraphRange.location + value.utf16.count, length: 0))
        configureTypingAttributes(for: suggestion.element, in: tv)
        updateFormattingState(from: tv)
        tv.didChangeText()
    }

    /// Toggles strikethrough on the current selection.
    func strikethrough() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        guard range.length > 0, let ts = tv.textStorage else { return }
        let existing = ts.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        let newValue = existing == 0 ? NSUnderlineStyle.single.rawValue : 0
        guard tv.shouldChangeText(in: range, replacementString: nil) else { return }
        ts.addAttribute(.strikethroughStyle, value: newValue, range: range)
        tv.didChangeText()
    }

    /// Applies a heading style to the current paragraph by setting font size and bold weight.
    /// - Parameter level: 1 = H1 (26pt), 2 = H2 (22pt), 3 = H3 (18pt)
    func applyHeading(_ level: Int) {
        guard let tv = textView else { return }
        let selectedRange = tv.selectedRange()
        guard let ts = tv.textStorage else { return }
        let paragraphRange = (tv.string as NSString).paragraphRange(for: selectedRange)
        guard paragraphRange.length > 0 else { return }

        let fontSize: CGFloat
        switch level {
        case 1: fontSize = 26
        case 2: fontSize = 22
        default: fontSize = 18
        }

        let loc = paragraphRange.location
        let baseFont = (ts.attribute(.font, at: loc, effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: 14)
        let sizedFont = NSFontManager.shared.convert(baseFont, toSize: fontSize)
        let boldFont  = NSFontManager.shared.convert(sizedFont, toHaveTrait: .boldFontMask)

        guard tv.shouldChangeText(in: paragraphRange, replacementString: nil) else { return }
        ts.addAttribute(.font, value: boldFont, range: paragraphRange)
        tv.didChangeText()
    }

    private func screenplayAttributes(for element: ScreenplayElement) -> [NSAttributedString.Key: Any] {
        let style = screenplayStyle(for: element)
        return [
            .font: style.font,
            .paragraphStyle: style.paragraphStyle,
            .foregroundColor: documentTextColor,
            .screenplayElement: element.rawValue
        ]
    }

    private func screenplayStyle(for element: ScreenplayElement) -> ScreenplayStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.05
        paragraph.paragraphSpacing = 4
        paragraph.paragraphSpacingBefore = 0

        let baseFont = screenplayFont(size: 12, weight: .regular)

        switch element {
        case .sceneHeading:
            paragraph.paragraphSpacingBefore = 10
            paragraph.paragraphSpacing = 6
            return ScreenplayStyle(font: screenplayFont(size: 12, weight: .semibold), paragraphStyle: paragraph, uppercase: true)
        case .action:
            return ScreenplayStyle(font: baseFont, paragraphStyle: paragraph, uppercase: false)
        case .character:
            paragraph.firstLineHeadIndent = 144
            paragraph.headIndent = 144
            paragraph.paragraphSpacingBefore = 8
            paragraph.paragraphSpacing = 2
            return ScreenplayStyle(font: screenplayFont(size: 12, weight: .semibold), paragraphStyle: paragraph, uppercase: true)
        case .parenthetical:
            paragraph.firstLineHeadIndent = 108
            paragraph.headIndent = 108
            paragraph.tailIndent = -108
            paragraph.paragraphSpacing = 2
            return ScreenplayStyle(font: screenplayFont(size: 12, weight: .regular), paragraphStyle: paragraph, uppercase: false)
        case .dialogue:
            paragraph.firstLineHeadIndent = 72
            paragraph.headIndent = 72
            paragraph.tailIndent = -72
            paragraph.paragraphSpacing = 4
            return ScreenplayStyle(font: baseFont, paragraphStyle: paragraph, uppercase: false)
        case .transition:
            paragraph.alignment = .right
            paragraph.paragraphSpacingBefore = 8
            paragraph.paragraphSpacing = 6
            return ScreenplayStyle(font: screenplayFont(size: 12, weight: .semibold), paragraphStyle: paragraph, uppercase: true)
        case .shot:
            paragraph.paragraphSpacingBefore = 8
            paragraph.paragraphSpacing = 4
            return ScreenplayStyle(font: screenplayFont(size: 12, weight: .semibold), paragraphStyle: paragraph, uppercase: true)
        case .insert:
            paragraph.paragraphSpacingBefore = 8
            paragraph.paragraphSpacing = 4
            return ScreenplayStyle(font: screenplayFont(size: 12, weight: .semibold), paragraphStyle: paragraph, uppercase: true)
        case .titleCard:
            paragraph.alignment = .center
            paragraph.paragraphSpacingBefore = 10
            paragraph.paragraphSpacing = 6
            return ScreenplayStyle(font: screenplayFont(size: 12, weight: .semibold), paragraphStyle: paragraph, uppercase: true)
        case .timeJump:
            paragraph.paragraphSpacingBefore = 8
            paragraph.paragraphSpacing = 5
            return ScreenplayStyle(font: screenplayFont(size: 12, weight: .semibold), paragraphStyle: paragraph, uppercase: true)
        }
    }

    private func currentParagraphRange(in tv: NSTextView) -> NSRange {
        (tv.string as NSString).paragraphRange(for: tv.selectedRange())
    }

    private func currentParagraphText(in tv: NSTextView, range: NSRange) -> String {
        let original = (tv.string as NSString).substring(with: range)
        return original.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func previousNonEmptyScreenplayElement(before location: Int, in tv: NSTextView) -> ScreenplayElement? {
        let text = tv.string as NSString
        guard text.length > 0, location > 0 else { return nil }

        var searchLocation = max(0, location - 1)
        while searchLocation > 0 {
            let paragraphRange = text.paragraphRange(for: NSRange(location: searchLocation, length: 0))
            let paragraph = text.substring(with: paragraphRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                if let tagged = tv.textStorage?.attribute(.screenplayElement, at: paragraphRange.location, effectiveRange: nil) as? String,
                   let element = ScreenplayElement(rawValue: tagged) {
                    return element
                }
                let inferred = explicitScreenplayElement(from: paragraph)
                if inferred != .action || looksLikeCharacterCue(paragraph) || paragraph.hasPrefix("(") {
                    return inferred
                }
                return .action
            }

            guard paragraphRange.location > 0 else { break }
            searchLocation = paragraphRange.location - 1
        }

        return nil
    }

    private func inferScreenplayElement(
        for paragraph: String,
        currentElement: ScreenplayElement,
        previousElement: ScreenplayElement?
    ) -> ScreenplayElement {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return currentElement }

        if let explicit = explicitScreenplayElementIfMatched(from: trimmed) {
            return explicit
        }

        if trimmed.hasPrefix("(") || currentElement == .parenthetical {
            return .parenthetical
        }

        if previousElement == .character || previousElement == .parenthetical {
            return .dialogue
        }

        if looksLikeCharacterCue(trimmed) {
            return .character
        }

        if currentElement == .dialogue {
            return .dialogue
        }

        if currentElement == .shot || currentElement == .insert || currentElement == .titleCard || currentElement == .timeJump {
            return currentElement
        }

        return .action
    }

    private func explicitScreenplayElementIfMatched(from paragraph: String) -> ScreenplayElement? {
        let inferred = explicitScreenplayElement(from: paragraph)
        return inferred == .action ? nil : inferred
    }

    private func explicitScreenplayElement(from paragraph: String) -> ScreenplayElement {
        let normalized = paragraph
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        let sceneHeadingPrefixes = ScreenplayCatalog.scenePrefixes
        if sceneHeadingPrefixes.contains(where: { matchesPrefix($0, in: normalized) }) {
            return .sceneHeading
        }

        let titleCardPrefixes = ["TITLE CARD", "SUPER", "SUPER:", "TITLE:", "ON BLACK", "TEXT ON SCREEN"]
        if titleCardPrefixes.contains(where: { matchesPrefix($0, in: normalized) }) {
            return .titleCard
        }

        let insertPrefixes = ["INSERT", "INSERT -", "ON SCREEN", "PHONE SCREEN", "TEXT MESSAGE", "NEWSFEED"]
        if insertPrefixes.contains(where: { matchesPrefix($0, in: normalized) }) {
            return .insert
        }

        let timeJumpPrefixes = [
            "MEANWHILE", "MOMENTS LATER", "LATER", "CONTINUOUS", "FLASHBACK", "FLASHFORWARD",
            "BACK TO PRESENT", "BACK TO SCENE", "DREAM SEQUENCE", "INTERCUT"
        ]
        if timeJumpPrefixes.contains(where: { matchesPrefix($0, in: normalized) }) {
            return .timeJump
        }

        let shotPrefixes = ["SHOT", "ANGLE ON", "CLOSE ON", "WIDE ON", "POV", "POV SHOT", "TRACKING SHOT", "INSERT SHOT"]
        if shotPrefixes.contains(where: { matchesPrefix($0, in: normalized) }) {
            return .shot
        }

        let transitionPrefixes = [
            "CUT TO", "DISSOLVE TO", "MATCH CUT TO", "SMASH CUT TO", "FADE IN", "FADE OUT",
            "BACK TO", "WIPE TO", "JUMP CUT TO"
        ]
        if transitionPrefixes.contains(where: { matchesPrefix($0, in: normalized) }) || normalized.hasSuffix(" TO:") {
            return .transition
        }

        return .action
    }

    private func matchesPrefix(_ prefix: String, in value: String) -> Bool {
        guard value.hasPrefix(prefix) else { return false }
        guard value.count > prefix.count else { return true }
        let boundary = value.index(value.startIndex, offsetBy: prefix.count)
        return value[boundary].isWhitespace || "-:.(".contains(value[boundary])
    }

    private func looksLikeCharacterCue(_ paragraph: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.uppercased()

        guard !normalized.isEmpty, normalized.count <= 32 else { return false }
        // Ordinary short action lines must not be mistaken for character cues.
        guard trimmed == normalized else { return false }
        guard !normalized.contains("INT.") && !normalized.contains("EXT.") else { return false }
        guard !normalized.contains(":") else { return false }
        let words = normalized.split(whereSeparator: \.isWhitespace)
        guard words.count <= 4 else { return false }

        if normalized.hasSuffix("!") || normalized.hasSuffix("?") || normalized.hasSuffix("—") || normalized.hasSuffix("--") {
            return false
        }
        if normalized.hasSuffix("."),
           !["DR.", "MR.", "MRS.", "MS.", "ST."].contains(where: { normalized.hasPrefix($0) }) {
            return false
        }
        return normalized.rangeOfCharacter(from: CharacterSet.letters) != nil
    }

    private func appendedSlugSuffix(from paragraph: String, suffix: String) -> String {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return suffix }

        let uppercase = trimmed.uppercased()
        if uppercase.contains(" - ") {
            let components = uppercase.components(separatedBy: " - ")
            if components.count > 1 {
                return components.dropLast().joined(separator: " - ") + " - " + suffix
            }
        }

        return uppercase + " - " + suffix
    }

    private func makeScreenplaySuggestions(in tv: NSTextView, activeElement: ScreenplayElement) -> [ScreenplaySuggestion] {
        let paragraph = currentParagraphText(in: tv, range: currentParagraphRange(in: tv))
        let inferredElement = inferScreenplayElement(
            for: paragraph,
            currentElement: activeElement,
            previousElement: previousNonEmptyScreenplayElement(before: tv.selectedRange().location, in: tv)
        )
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        switch inferredElement {
        case .sceneHeading:
            var suggestions: [ScreenplaySuggestion] = []
            if trimmed.isEmpty || ["INT", "INT.", "EXT", "EXT.", "EST", "EST."].contains(trimmed) {
                suggestions += [
                    ScreenplaySuggestion(label: "INT.", text: "INT. LOCATION - DAY", element: .sceneHeading, behavior: .replaceParagraph),
                    ScreenplaySuggestion(label: "EXT.", text: "EXT. LOCATION - NIGHT", element: .sceneHeading, behavior: .replaceParagraph),
                    ScreenplaySuggestion(label: "INT./EXT.", text: "INT./EXT. VEHICLE - DAY", element: .sceneHeading, behavior: .replaceParagraph),
                    ScreenplaySuggestion(label: "EST.", text: "EST. CITYSCAPE - DAWN", element: .sceneHeading, behavior: .replaceParagraph)
                ]
            }
            if let documentCatalog {
                suggestions += documentCatalog.headings.filter { trimmed.isEmpty || $0.hasPrefix(trimmed) }
                    .prefix(6).map { ScreenplaySuggestion(label: $0, text: $0, element: .sceneHeading, behavior: .replaceParagraph) }
            }
            suggestions += [
                ScreenplaySuggestion(label: "DAY", text: "DAY", element: .sceneHeading, behavior: .appendSlugSuffix),
                ScreenplaySuggestion(label: "NIGHT", text: "NIGHT", element: .sceneHeading, behavior: .appendSlugSuffix),
                ScreenplaySuggestion(label: "MORNING", text: "MORNING", element: .sceneHeading, behavior: .appendSlugSuffix),
                ScreenplaySuggestion(label: "AFTERNOON", text: "AFTERNOON", element: .sceneHeading, behavior: .appendSlugSuffix),
                ScreenplaySuggestion(label: "EVENING", text: "EVENING", element: .sceneHeading, behavior: .appendSlugSuffix),
                ScreenplaySuggestion(label: "CONTINUOUS", text: "CONTINUOUS", element: .sceneHeading, behavior: .appendSlugSuffix),
                ScreenplaySuggestion(label: "MOMENTS LATER", text: "MOMENTS LATER", element: .sceneHeading, behavior: .appendSlugSuffix),
                ScreenplaySuggestion(label: "MEANWHILE", text: "MEANWHILE", element: .sceneHeading, behavior: .appendSlugSuffix)
            ]
            return deduplicatedSuggestions(suggestions)
        case .transition:
            return [
                ScreenplaySuggestion(label: "CUT TO:", text: "CUT TO:", element: .transition, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "DISSOLVE TO:", text: "DISSOLVE TO:", element: .transition, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "SMASH CUT TO:", text: "SMASH CUT TO:", element: .transition, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "FADE OUT.", text: "FADE OUT.", element: .transition, behavior: .replaceParagraph)
            ]
        case .shot:
            return [
                ScreenplaySuggestion(label: "ANGLE ON", text: "ANGLE ON", element: .shot, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "CLOSE ON", text: "CLOSE ON", element: .shot, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "POV", text: "POV", element: .shot, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "WIDE ON", text: "WIDE ON", element: .shot, behavior: .replaceParagraph)
            ]
        case .insert:
            return [
                ScreenplaySuggestion(label: "INSERT", text: "INSERT -", element: .insert, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "PHONE SCREEN", text: "PHONE SCREEN", element: .insert, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "TEXT MESSAGE", text: "TEXT MESSAGE", element: .insert, behavior: .replaceParagraph)
            ]
        case .titleCard:
            return [
                ScreenplaySuggestion(label: "TITLE CARD", text: "TITLE CARD:", element: .titleCard, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "SUPER:", text: "SUPER:", element: .titleCard, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "ON BLACK", text: "ON BLACK", element: .titleCard, behavior: .replaceParagraph)
            ]
        case .timeJump:
            return [
                ScreenplaySuggestion(label: "MOMENTS LATER", text: "MOMENTS LATER", element: .timeJump, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "MEANWHILE", text: "MEANWHILE", element: .timeJump, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "FLASHBACK", text: "FLASHBACK", element: .timeJump, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "BACK TO PRESENT", text: "BACK TO PRESENT", element: .timeJump, behavior: .replaceParagraph)
            ]
        case .parenthetical:
            return [
                ScreenplaySuggestion(label: "(beat)", text: "(beat)", element: .parenthetical, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "(whispering)", text: "(whispering)", element: .parenthetical, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "(O.S.)", text: "(O.S.)", element: .parenthetical, behavior: .replaceParagraph)
            ]
        case .character:
            let characterName = canonicalCharacterName(from: trimmed)
            let recentCharacters = existingCharacterNames(in: tv)
                .filter { $0 != characterName }
                .prefix(5)
                .map {
                    ScreenplaySuggestion(
                        label: $0,
                        text: $0,
                        element: .character,
                        behavior: .replaceParagraph
                    )
                }
            return recentCharacters + [
                ScreenplaySuggestion(label: "O.S.", text: "\(characterName) (O.S.)", element: .character, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "V.O.", text: "\(characterName) (V.O.)", element: .character, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "CONT'D", text: "\(characterName) (CONT'D)", element: .character, behavior: .replaceParagraph)
            ]
        case .action, .dialogue:
            return []
        }
    }

    private func deduplicatedSuggestions(_ suggestions: [ScreenplaySuggestion]) -> [ScreenplaySuggestion] {
        var seen = Set<String>()
        return suggestions.filter { suggestion in
            let key = suggestion.id
            return seen.insert(key).inserted
        }
    }

    private func existingCharacterNames(in tv: NSTextView) -> [String] {
        if let documentCatalog { return documentCatalog.characters }
        let text = tv.string as NSString
        guard text.length > 0 else { return [] }

        var names: [String] = []
        var location = 0
        while location < text.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            let paragraph = text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let tagged = tv.textStorage?.attribute(.screenplayElement, at: range.location, effectiveRange: nil) as? String
            if !paragraph.isEmpty,
               tagged == ScreenplayElement.character.rawValue || looksLikeCharacterCue(paragraph) {
                names.append(canonicalCharacterName(from: paragraph))
            }
            location = NSMaxRange(range)
        }

        var seen = Set<String>()
        return names.reversed().filter { seen.insert($0).inserted }
    }

    private func publishScreenplayState(
        element: ScreenplayElement,
        suggestions: [ScreenplaySuggestion]
    ) {
        if activeScreenplayElement != element {
            activeScreenplayElement = element
        }
        if screenplaySuggestions != suggestions {
            screenplaySuggestions = suggestions
        }
    }

    private func canonicalCharacterName(from cue: String) -> String {
        ScreenplayCatalog.canonicalCharacterName(cue)
    }

    private func screenplayFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let courierPrime = NSFont(name: "Courier Prime", size: size) {
            return courierPrime
        }
        if let courier = NSFont(name: "Courier", size: size) {
            return weight == .regular ? courier : NSFontManager.shared.convert(courier, toHaveTrait: .boldFontMask)
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}
