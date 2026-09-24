import AppKit
import Combine
import XCTest
@testable import MongrelWordProcessor

@MainActor
final class ScreenplayFormattingTests: XCTestCase {
    func testSceneHeadingIsDetectedUppercasedAndTagged() {
        let (bridge, textView) = makeEditor("int. kitchen - morning")

        let element = bridge.autoFormatScreenplay(in: textView)

        XCTAssertEqual(element, .sceneHeading)
        XCTAssertEqual(textView.string, "INT. KITCHEN - MORNING")
        XCTAssertEqual(screenplayTag(in: textView), .sceneHeading)
    }

    func testMixedCaseShortActionIsNotMisclassifiedAsCharacter() {
        let (bridge, textView) = makeEditor("He crosses the room.")

        XCTAssertEqual(bridge.autoFormatScreenplay(in: textView), .action)
        XCTAssertEqual(textView.string, "He crosses the room.")
    }

    func testLiveFormattingPreservesTrailingSpaceWhileTyping() {
        let (bridge, textView) = makeEditor("A quiet room ")

        let element = bridge.autoFormatScreenplay(in: textView)

        XCTAssertEqual(element, .action)
        XCTAssertEqual(textView.string, "A quiet room ")
    }

    func testLiveFormattingDoesNotPrematurelyCloseParenthetical() {
        let (bridge, textView) = makeEditor("(")

        let element = bridge.autoFormatScreenplay(in: textView)

        XCTAssertEqual(element, .parenthetical)
        XCTAssertEqual(textView.string, "(")
    }

    func testUppercaseCharacterCueFlowsIntoDialogue() {
        let bridge = FormattingBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.string = "MARA\nWhere did everyone go?"
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        bridge.applyScreenplayElement(.character, to: textView, notifyTextChange: false)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        bridge.configureTypingAttributes(for: .action, in: textView)

        XCTAssertEqual(bridge.autoFormatScreenplay(in: textView), .dialogue)
        XCTAssertEqual(screenplayTag(in: textView, location: 5), .dialogue)
    }

    func testExplicitProductionElementsAreDetected() {
        let cases: [(String, ScreenplayElement)] = [
            ("CUT TO:", .transition),
            ("ANGLE ON THE DOOR", .shot),
            ("INSERT - THE LETTER", .insert),
            ("TITLE CARD: THREE YEARS EARLIER", .titleCard),
            ("MOMENTS LATER", .timeJump),
            ("(under her breath)", .parenthetical)
        ]

        for (text, expected) in cases {
            let (bridge, textView) = makeEditor(text)
            XCTAssertEqual(bridge.autoFormatScreenplay(in: textView), expected, "Failed to classify: \(text)")
            XCTAssertEqual(screenplayTag(in: textView), expected)
        }
    }

    func testSceneHeadingSuggestionsIncludeTimesAndTemporalContinuity() {
        let (bridge, textView) = makeEditor("INT. KITCHEN")

        _ = bridge.autoFormatScreenplay(in: textView)
        let labels = Set(bridge.screenplaySuggestions.map(\.label))

        XCTAssertTrue(labels.isSuperset(of: ["MORNING", "AFTERNOON", "NIGHT", "MEANWHILE", "MOMENTS LATER"]))
    }

    func testCaretMovementUsesParagraphTagInsteadOfStaleTypingAttributes() {
        let bridge = FormattingBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.string = "INT. HALL - DAY\nSomething moves."
        let text = textView.string as NSString
        let headingRange = text.paragraphRange(for: NSRange(location: 0, length: 0))
        let actionRange = text.paragraphRange(for: NSRange(location: NSMaxRange(headingRange), length: 0))
        textView.textStorage?.addAttribute(.screenplayElement, value: ScreenplayElement.sceneHeading.rawValue, range: headingRange)
        textView.textStorage?.addAttribute(.screenplayElement, value: ScreenplayElement.action.rawValue, range: actionRange)
        bridge.configureTypingAttributes(for: .dialogue, in: textView)

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        XCTAssertEqual(bridge.detectedScreenplayElement(in: textView), .sceneHeading)

        textView.setSelectedRange(NSRange(location: 20, length: 0))
        XCTAssertEqual(bridge.detectedScreenplayElement(in: textView), .action)
    }

    func testFormattingStateReflectsSelectedTextInsteadOfTypingAttributes() {
        let bridge = FormattingBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.string = "Bold plain"
        textView.textStorage?.addAttribute(
            .font,
            value: NSFont.boldSystemFont(ofSize: 14),
            range: NSRange(location: 0, length: 4)
        )
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 14)
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        bridge.updateFormattingState(from: textView)

        XCTAssertTrue(bridge.isBold)
        XCTAssertFalse(bridge.isItalic)
    }

    func testReturnEscapesEmptyDialogueBlocksToAction() {
        let bridge = FormattingBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))

        bridge.configureTypingAttributes(for: .dialogue, in: textView)
        XCTAssertEqual(bridge.nextScreenplayElementOnReturn(in: textView), .action)

        textView.string = "We should go."
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        bridge.configureTypingAttributes(for: .dialogue, in: textView)
        XCTAssertEqual(bridge.nextScreenplayElementOnReturn(in: textView), .character)
    }

    func testUppercaseSentenceAndPrefixLookalikesRemainAction() {
        for text in ["THE CAR EXPLODES.", "WHO GOES THERE?", "LATERAL LIGHT CUTS THE ROOM"] {
            let (bridge, textView) = makeEditor(text)
            XCTAssertEqual(bridge.autoFormatScreenplay(in: textView), .action, "Misclassified: \(text)")
        }
    }

    func testPageBreakGeometryReservesBothPageMargins() {
        let paths = ScreenplayPageLayout.exclusionPaths(maximumPageCount: 3)

        XCTAssertEqual(paths.count, 2)
        XCTAssertEqual(paths[0].bounds.origin.y, ScreenplayPageLayout.contentHeight)
        XCTAssertEqual(paths[0].bounds.height, ScreenplayPageLayout.pageBreakHeight)
        XCTAssertEqual(
            ScreenplayPageLayout.pageCount(forLaidOutContentHeight: ScreenplayPageLayout.contentHeight),
            1
        )
        XCTAssertEqual(
            ScreenplayPageLayout.pageCount(forLaidOutContentHeight: ScreenplayPageLayout.pageSize.height),
            2
        )
    }

    func testWholeDocumentAutoFormatUsesParagraphContext() {
        let bridge = FormattingBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        textView.string = [
            "int. workshop - afternoon",
            "Mara watches the monitor.",
            "MARA",
            "Did it finish?",
            "(a beat)",
            "Almost.",
            "CUT TO"
        ].joined(separator: "\n")
        bridge.textView = textView

        bridge.autoFormatEntireScreenplay()

        XCTAssertEqual(textView.string, [
            "INT. WORKSHOP - AFTERNOON",
            "Mara watches the monitor.",
            "MARA",
            "Did it finish?",
            "(a beat)",
            "Almost.",
            "CUT TO:"
        ].joined(separator: "\n"))
        XCTAssertEqual(paragraphElements(in: textView), [
            .sceneHeading, .action, .character, .dialogue, .parenthetical, .dialogue, .transition
        ])
    }

    func testCharacterSuggestionsReuseNamesFromTheDraft() {
        let bridge = FormattingBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        textView.string = "MARA\nFirst line.\nDAVID\nSecond line.\n"
        let text = textView.string as NSString
        var location = 0
        for element in [ScreenplayElement.character, .dialogue, .character, .dialogue] {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            textView.textStorage?.addAttribute(.screenplayElement, value: element.rawValue, range: range)
            location = NSMaxRange(range)
        }
        textView.setSelectedRange(NSRange(location: text.length, length: 0))

        bridge.configureTypingAttributes(for: .character, in: textView)
        let labels = Set(bridge.screenplaySuggestions.map(\.label))

        XCTAssertTrue(labels.isSuperset(of: ["MARA", "DAVID", "O.S.", "V.O.", "CONT'D"]))
    }

    func testCharacterSuggestionsDoNotStackCueExtensions() throws {
        let bridge = FormattingBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        textView.string = "MARA (V.O.)"
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        bridge.configureTypingAttributes(for: .character, in: textView)

        let voiceOver = try XCTUnwrap(bridge.screenplaySuggestions.first(where: { $0.label == "V.O." }))
        let offScreen = try XCTUnwrap(bridge.screenplaySuggestions.first(where: { $0.label == "O.S." }))
        let continued = try XCTUnwrap(bridge.screenplaySuggestions.first(where: { $0.label == "CONT'D" }))
        XCTAssertEqual(voiceOver.text, "MARA (V.O.)")
        XCTAssertEqual(offScreen.text, "MARA (O.S.)")
        XCTAssertEqual(continued.text, "MARA (CONT'D)")
    }

    func testFormattingStateDoesNotRepublishUnchangedValues() {
        let (bridge, textView) = makeEditor("Quiet action.")
        bridge.updateFormattingState(from: textView)
        var updateCount = 0
        let subscription = bridge.objectWillChange.sink { updateCount += 1 }

        bridge.updateFormattingState(from: textView)

        XCTAssertEqual(updateCount, 0)
        withExtendedLifetime(subscription) {}
    }

    func testTypingAttributesCanBeConfiguredWithoutPublishingDuringViewUpdate() {
        let (bridge, textView) = makeEditor("")
        var updateCount = 0
        let subscription = bridge.objectWillChange.sink { updateCount += 1 }

        bridge.configureTypingAttributes(
            for: .sceneHeading,
            in: textView,
            updatePublishedState: false
        )

        XCTAssertEqual(updateCount, 0)
        XCTAssertEqual(
            textView.typingAttributes[.screenplayElement] as? String,
            ScreenplayElement.sceneHeading.rawValue
        )
        withExtendedLifetime(subscription) {}
    }

    func testCompanionSuggestionsRejectNonpositiveLimits() {
        let lexicon = MongrelDictionaryCompanionLexicon(headwords: ["screenplay", "screenwriter"])

        XCTAssertEqual(lexicon.suggestions(for: "screen", limit: 0), [])
        XCTAssertEqual(lexicon.suggestions(for: "screen", limit: -1), [])
    }

    func testCompanionSuggestionsFindBoundedSingleEditCorrections() {
        let lexicon = MongrelDictionaryCompanionLexicon(
            headwords: ["screenplay", "screenwriter", "the", "writer"]
        )

        XCTAssertTrue(lexicon.suggestions(for: "sscreenplay").contains("screenplay"))
        XCTAssertTrue(lexicon.suggestions(for: "creenplay").contains("screenplay"))
        XCTAssertTrue(lexicon.suggestions(for: "xcreenplay").contains("screenplay"))
        XCTAssertTrue(lexicon.suggestions(for: "teh").contains("the"))
    }

    func testCompanionSuggestionsPreferTruePrefixCompletions() {
        let lexicon = MongrelDictionaryCompanionLexicon(
            headwords: ["scream", "screenplay", "screenwriter"]
        )

        XCTAssertEqual(
            lexicon.suggestions(for: "screenw", limit: 2).first,
            "screenwriter"
        )
    }

    private func makeEditor(_ text: String) -> (FormattingBridge, NSTextView) {
        let bridge = FormattingBridge()
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        bridge.configureTypingAttributes(for: .action, in: textView)
        return (bridge, textView)
    }

    private func screenplayTag(in textView: NSTextView, location: Int = 0) -> ScreenplayElement? {
        guard let raw = textView.textStorage?.attribute(
            .screenplayElement,
            at: location,
            effectiveRange: nil
        ) as? String else {
            return nil
        }
        return ScreenplayElement(rawValue: raw)
    }

    private func paragraphElements(in textView: NSTextView) -> [ScreenplayElement] {
        let text = textView.string as NSString
        var result: [ScreenplayElement] = []
        var location = 0
        while location < text.length {
            let range = text.paragraphRange(for: NSRange(location: location, length: 0))
            if let element = screenplayTag(in: textView, location: range.location) {
                result.append(element)
            }
            location = NSMaxRange(range)
        }
        return result
    }
}
