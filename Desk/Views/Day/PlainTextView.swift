import SwiftUI
import AppKit

/// NSTextView wrapper tuned for notes: plain text, tabs insert tabs, no smart substitutions,
/// continuous spell check, per-editor undo so ⌘Z here never touches block history.
struct PlainTextView: NSViewRepresentable {
    @Binding var text: String
    /// Changes to a non-zero value request keyboard focus.
    var focusToken: Int = 0
    var fontSize: CGFloat = 15.5

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder

        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = false
        tv.textContainerInset = NSSize(width: 0, height: 6)
        tv.textContainer?.lineFragmentPadding = 1
        tv.textContainer?.widthTracksTextView = true
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.setAccessibilityLabel("Brain dump")
        tv.setAccessibilityIdentifier("brainDump")

        applyTypography(to: tv)
        tv.string = text
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if tv.string != text {
            let selection = tv.selectedRanges
            tv.string = text
            applyTypography(to: tv)
            if let first = selection.first?.rangeValue, first.location <= (tv.string as NSString).length {
                tv.setSelectedRange(NSRange(location: min(first.location, (tv.string as NSString).length), length: 0))
            }
        }
        if focusToken != 0, focusToken != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
            }
        }
    }

    private func applyTypography(to tv: NSTextView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.28
        paragraph.paragraphSpacing = 2
        paragraph.defaultTabInterval = 28
        paragraph.tabStops = []
        let ink = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: 0xECE8E1) : NSColor(hex: 0x242424)
        }
        tv.font = font
        tv.textColor = ink
        tv.insertionPointColor = ink
        tv.defaultParagraphStyle = paragraph
        tv.typingAttributes = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
        if tv.textStorage?.length ?? 0 > 0 {
            tv.textStorage?.addAttributes([.font: font, .foregroundColor: ink, .paragraphStyle: paragraph],
                                          range: NSRange(location: 0, length: tv.textStorage!.length))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlainTextView
        weak var textView: NSTextView?
        let undoManager = UndoManager()
        var lastFocusToken = 0

        init(_ parent: PlainTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }
    }
}
