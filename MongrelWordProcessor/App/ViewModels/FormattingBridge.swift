import AppKit

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

    // MARK: – Active-state publishers (updated on every selection change)
    @Published private(set) var isBold: Bool = false
    @Published private(set) var isItalic: Bool = false
    @Published private(set) var isUnderline: Bool = false
    @Published private(set) var isStrikethrough: Bool = false
    @Published private(set) var activeScreenplayElement: ScreenplayElement = .action
    @Published private(set) var screenplaySuggestions: [ScreenplaySuggestion] = []

    /// Called by Coordinator.textViewDidChangeSelection to refresh active-state flags.
    func updateFormattingState(from tv: NSTextView) {
        let attrs = tv.selectedRange().length > 0
            ? tv.typingAttributes
            : tv.typingAttributes

        // Bold / italic derive from the symbolic traits of the current font
        if let font = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            isBold      = traits.contains(.boldFontMask)
            isItalic    = traits.contains(.italicFontMask)
        } else {
            isBold  = false
            isItalic = false
        }

        // Underline — non-zero value means active
        let underlineVal = attrs[.underlineStyle] as? Int ?? 0
        isUnderline = underlineVal != 0

        // Strikethrough — check at selection start when there's a selection
        let range = tv.selectedRange()
        if range.length > 0, let ts = tv.textStorage {
            let strikeVal = ts.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
            isStrikethrough = strikeVal != 0
        } else {
            let strikeVal = attrs[.strikethroughStyle] as? Int ?? 0
            isStrikethrough = strikeVal != 0
        }

        activeScreenplayElement = detectedScreenplayElement(in: tv)
        screenplaySuggestions = makeScreenplaySuggestions(in: tv, activeElement: activeScreenplayElement)
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

    func applyScreenplayElement(_ element: ScreenplayElement, to tv: NSTextView, notifyTextChange: Bool = true) {
        let style = screenplayStyle(for: element)
        let selection = tv.selectedRange()
        let paragraphRange = (tv.string as NSString).paragraphRange(for: selection)

        if paragraphRange.length > 0, let ts = tv.textStorage {
            ts.beginEditing()

            if style.uppercase {
                let original = (tv.string as NSString).substring(with: paragraphRange)
                let uppercased = original.uppercased()
                if uppercased != original {
                    ts.replaceCharacters(in: paragraphRange, with: uppercased)
                }
            }

            let refreshedParagraphRange = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
            ts.addAttributes(screenplayAttributes(for: element), range: refreshedParagraphRange)
            ts.endEditing()
        }

        configureTypingAttributes(for: element, in: tv)
        activeScreenplayElement = element
        screenplaySuggestions = makeScreenplaySuggestions(in: tv, activeElement: element)
        if notifyTextChange {
            tv.didChangeText()
        }
    }

    func configureTypingAttributes(for element: ScreenplayElement, in tv: NSTextView) {
        var attrs = tv.typingAttributes
        screenplayAttributes(for: element).forEach { attrs[$0.key] = $0.value }
        tv.typingAttributes = attrs
        tv.defaultParagraphStyle = screenplayStyle(for: element).paragraphStyle
        tv.insertionPointColor = .labelColor
        activeScreenplayElement = element
        screenplaySuggestions = makeScreenplaySuggestions(in: tv, activeElement: element)
    }

    func detectedScreenplayElement(in tv: NSTextView) -> ScreenplayElement {
        let range = tv.selectedRange()

        if let tagged = tv.typingAttributes[.screenplayElement] as? String,
           let element = ScreenplayElement(rawValue: tagged) {
            return element
        }

        if let ts = tv.textStorage, ts.length > 0 {
            let location = max(0, min(range.location, ts.length - 1))
            if let tagged = ts.attribute(.screenplayElement, at: location, effectiveRange: nil) as? String,
               let element = ScreenplayElement(rawValue: tagged) {
                return element
            }
        }

        return activeScreenplayElement
    }

    func autoFormatScreenplay(in tv: NSTextView) -> ScreenplayElement {
        let paragraphRange = currentParagraphRange(in: tv)
        let paragraph = currentParagraphText(in: tv, range: paragraphRange)
        let currentElement = detectedScreenplayElement(in: tv)
        let previousElement = previousNonEmptyScreenplayElement(before: paragraphRange.location, in: tv)
        let inferredElement = inferScreenplayElement(
            for: paragraph,
            currentElement: currentElement,
            previousElement: previousElement
        )

        normalizeScreenplayParagraph(in: tv, range: paragraphRange, for: inferredElement)
        applyScreenplayElement(inferredElement, to: tv, notifyTextChange: false)
        updateFormattingState(from: tv)
        return inferredElement
    }

    func applySuggestion(_ suggestion: ScreenplaySuggestion) {
        guard let tv = textView else { return }

        let paragraphRange = currentParagraphRange(in: tv)
        let currentText = currentParagraphText(in: tv, range: paragraphRange)
        let replacement = suggestion.behavior == .appendSlugSuffix
            ? appendedSlugSuffix(from: currentText, suffix: suggestion.text)
            : suggestion.text

        replaceParagraph(in: tv, range: paragraphRange, with: replacement)
        applyScreenplayElement(suggestion.element, to: tv, notifyTextChange: false)
        normalizeScreenplayParagraph(in: tv, range: currentParagraphRange(in: tv), for: suggestion.element)
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

        ts.addAttribute(.font, value: boldFont, range: paragraphRange)
        tv.didChangeText()
    }

    private func screenplayAttributes(for element: ScreenplayElement) -> [NSAttributedString.Key: Any] {
        let style = screenplayStyle(for: element)
        return [
            .font: style.font,
            .paragraphStyle: style.paragraphStyle,
            .foregroundColor: NSColor.labelColor,
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

        let sceneHeadingPrefixes = ["INT.", "EXT.", "INT/EXT.", "INT./EXT.", "EXT./INT.", "I/E.", "EST."]
        if sceneHeadingPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return .sceneHeading
        }

        let titleCardPrefixes = ["TITLE CARD", "SUPER", "SUPER:", "TITLE:", "ON BLACK", "TEXT ON SCREEN"]
        if titleCardPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return .titleCard
        }

        let insertPrefixes = ["INSERT", "INSERT -", "ON SCREEN", "PHONE SCREEN", "TEXT MESSAGE", "NEWSFEED"]
        if insertPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return .insert
        }

        let timeJumpPrefixes = [
            "MEANWHILE", "MOMENTS LATER", "LATER", "CONTINUOUS", "FLASHBACK", "FLASHFORWARD",
            "BACK TO PRESENT", "BACK TO SCENE", "DREAM SEQUENCE", "INTERCUT"
        ]
        if timeJumpPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return .timeJump
        }

        let shotPrefixes = ["SHOT", "ANGLE ON", "CLOSE ON", "WIDE ON", "POV", "POV SHOT", "TRACKING SHOT", "INSERT SHOT"]
        if shotPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return .shot
        }

        let transitionPrefixes = [
            "CUT TO", "DISSOLVE TO", "MATCH CUT TO", "SMASH CUT TO", "FADE IN", "FADE OUT",
            "BACK TO", "WIPE TO", "JUMP CUT TO"
        ]
        if transitionPrefixes.contains(where: { normalized.hasPrefix($0) }) || normalized.hasSuffix(" TO:") {
            return .transition
        }

        return .action
    }

    private func looksLikeCharacterCue(_ paragraph: String) -> Bool {
        let normalized = paragraph
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard !normalized.isEmpty, normalized.count <= 32 else { return false }
        guard normalized == paragraph.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return false }
        guard !normalized.contains("INT.") && !normalized.contains("EXT.") else { return false }
        guard !normalized.contains(":") else { return false }
        return normalized.rangeOfCharacter(from: CharacterSet.letters) != nil
    }

    private func normalizeScreenplayParagraph(in tv: NSTextView, range: NSRange, for element: ScreenplayElement) {
        let originalParagraph = (tv.string as NSString).substring(with: range)
        let hasTrailingNewline = originalParagraph.hasSuffix("\n")
        let trimmed = originalParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var normalized = trimmed
        let style = screenplayStyle(for: element)

        if element == .parenthetical {
            if !normalized.hasPrefix("(") {
                normalized = "(\(normalized)"
            }
            if !normalized.hasSuffix(")") {
                normalized += ")"
            }
        }

        if element == .transition {
            if !normalized.hasSuffix(":") && !normalized.hasSuffix(".") {
                normalized += ":"
            }
        }

        if style.uppercase {
            normalized = normalized.uppercased()
        }

        let replacement = hasTrailingNewline ? normalized + "\n" : normalized
        guard replacement != originalParagraph else { return }

        replaceParagraph(in: tv, range: range, with: replacement)
    }

    private func replaceParagraph(in tv: NSTextView, range: NSRange, with replacement: String) {
        guard let textStorage = tv.textStorage else { return }

        let originalSelection = tv.selectedRange()
        let selectionOffset = max(0, originalSelection.location - range.location)
        let oldLength = range.length

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: replacement)
        textStorage.endEditing()

        let lengthDelta = replacement.count - oldLength
        let newLocation = min(range.location + selectionOffset + max(0, lengthDelta), (tv.string as NSString).length)
        tv.setSelectedRange(NSRange(location: newLocation, length: 0))
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
            return [
                ScreenplaySuggestion(label: "O.S.", text: "\(trimmed.isEmpty ? "CHARACTER" : trimmed) (O.S.)", element: .character, behavior: .replaceParagraph),
                ScreenplaySuggestion(label: "V.O.", text: "\(trimmed.isEmpty ? "CHARACTER" : trimmed) (V.O.)", element: .character, behavior: .replaceParagraph)
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
