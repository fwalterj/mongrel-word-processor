import AppKit

/// Keeps display geometry separate from document formatting and print geometry.
final class EditorScrollView: NSScrollView {
    enum LayoutMode { case reflow, unwrapped, screenplay }
    struct Anchor {
        let location: Int
        let viewportOffset: NSPoint
    }

    var layoutMode: LayoutMode = .reflow
    private var isAdjustingGeometry = false
    private var previousViewportSize = NSSize.zero

    override func setFrameSize(_ newSize: NSSize) {
        guard frame.size != newSize, !isAdjustingGeometry else { super.setFrameSize(newSize); return }
        preservingAnchor { super.setFrameSize(newSize) }
    }

    override func tile() {
        guard !isAdjustingGeometry else { super.tile(); return }
        let anchor = captureAnchor()
        isAdjustingGeometry = true
        super.tile()
        if previousViewportSize != contentView.bounds.size {
            synchronizeDocumentGeometry()
            restoreAnchor(anchor)
        }
        isAdjustingGeometry = false
    }

    func setEditorMagnification(_ value: CGFloat) {
        guard value.isFinite else { return }
        preservingAnchor { magnification = min(max(value, minMagnification), maxMagnification) }
    }

    func preservingAnchor(_ change: () -> Void) {
        guard !isAdjustingGeometry else { change(); return }
        let anchor = captureAnchor()
        isAdjustingGeometry = true
        change()
        synchronizeDocumentGeometry()
        restoreAnchor(anchor)
        isAdjustingGeometry = false
    }

    func synchronizeDocumentGeometry() {
        guard let editor = documentView as? NSTextView else { return }
        let visible = contentView.bounds.size
        guard visible.width.isFinite, visible.height.isFinite, visible.width > 0, visible.height > 0 else { return }
        previousViewportSize = visible
        if layoutMode == .screenplay {
            editor.setFrameSize(NSSize(width: ScreenplayPageLayout.pageSize.width, height: max(editor.frame.height, visible.height)))
            return
        }
        let wraps = layoutMode == .reflow
        editor.minSize = NSSize(width: visible.width, height: visible.height)
        editor.maxSize = NSSize(width: wraps ? visible.width : .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        editor.isHorizontallyResizable = !wraps
        editor.isVerticallyResizable = true
        editor.autoresizingMask = []
        editor.textContainer?.widthTracksTextView = wraps
        if !wraps {
            editor.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        editor.setFrameSize(NSSize(width: wraps ? visible.width : max(visible.width, editor.frame.width), height: max(visible.height, editor.frame.height)))
        if let manager = editor.textLayoutManager {
            manager.ensureLayout(for: manager.documentRange)
            let usage = manager.usageBoundsForTextContainer
            if usage.maxX.isFinite, usage.maxY.isFinite {
                editor.setFrameSize(NSSize(
                    width: wraps ? visible.width : max(visible.width, ceil(usage.maxX + editor.textContainerInset.width * 2 + (editor.textContainer?.lineFragmentPadding ?? 0))),
                    height: max(visible.height, ceil(usage.maxY + editor.textContainerInset.height * 2))
                ))
            }
        } else {
            editor.sizeToFit()
        }
        if wraps {
            contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.minY))
            reflectScrolledClipView(contentView)
        }
    }

    func captureAnchor() -> Anchor? {
        guard let editor = documentView as? NSTextView, editor.window != nil, editor.string.utf16.count > 0 else { return nil }
        let visible = contentView.bounds
        let selection = editor.selectedRange()
        let caret = characterRect(at: min(selection.location, editor.string.utf16.count), in: editor)
        let location: Int
        let rect: NSRect
        if let caret, caret.intersects(visible) {
            location = min(selection.location, editor.string.utf16.count)
            rect = caret
        } else {
            location = editor.characterIndexForInsertion(at: NSPoint(x: visible.minX + editor.textContainerInset.width + 2, y: visible.minY + 2))
            guard let readingRect = characterRect(at: location, in: editor) else { return nil }
            rect = readingRect
        }
        return Anchor(location: location, viewportOffset: NSPoint(x: (rect.minX - visible.minX) * magnification, y: (rect.minY - visible.minY) * magnification))
    }

    func restoreAnchor(_ anchor: Anchor?) {
        guard let anchor, let editor = documentView as? NSTextView,
              let rect = characterRect(at: min(anchor.location, editor.string.utf16.count), in: editor) else { return }
        let visible = contentView.bounds
        let offsetY = min(max(1 - rect.height, anchor.viewportOffset.y / magnification), max(0, visible.height - rect.height))
        let origin = NSPoint(
            x: layoutMode == .unwrapped ? max(0, rect.minX - anchor.viewportOffset.x / magnification) : 0,
            y: max(0, rect.minY - offsetY)
        )
        contentView.scroll(to: NSPoint(x: min(origin.x, max(0, editor.frame.width - visible.width)), y: min(origin.y, max(0, editor.frame.height - visible.height))))
        reflectScrolledClipView(contentView)
    }

    private func characterRect(at location: Int, in editor: NSTextView) -> NSRect? {
        guard let window = editor.window, location >= 0, location <= editor.string.utf16.count else { return nil }
        if let manager = editor.textLayoutManager,
           let content = manager.textContentManager,
           let start = content.location(content.documentRange.location, offsetBy: location),
           let end = content.location(content.documentRange.location, offsetBy: min(location + 1, editor.string.utf16.count)),
           let range = NSTextRange(location: content.documentRange.location, end: end) {
            manager.ensureLayout(for: range)
            // firstRect is an input-method API and returns zero for characters
            // displaced outside the viewport during reflow. Query layout instead.
            if let caretRange = NSTextRange(location: start, end: start) {
                var result: NSRect?
                manager.enumerateTextSegments(in: caretRange, type: .standard, options: [.rangeNotRequired]) { _, rect, _, _ in
                    result = rect.offsetBy(dx: editor.textContainerOrigin.x, dy: editor.textContainerOrigin.y)
                    return false
                }
                if let result, result.height > 0 { return result }
            }
        }
        let screen = editor.firstRect(forCharacterRange: NSRange(location: location, length: 0), actualRange: nil)
        guard screen.height > 0, screen.minX.isFinite, screen.minY.isFinite else { return nil }
        return editor.convert(window.convertFromScreen(screen), from: nil)
    }
}
