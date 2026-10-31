import AppKit
import SwiftUI

struct NativeURLInputField: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    // The extra-large circular button draws a 32-point bezel in its 40-point layout frame.
    static let height: CGFloat = 32

    @Binding var text: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isEnabled = isEnabled
        field.cell = CenteredTextFieldCell(textCell: text)
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.drawsBackground = true
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderString = "Video veya playlist linki yapıştır"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.isAutomaticTextCompletionEnabled = false
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("YouTube linki")

        if #available(macOS 26.0, *) {
            field.borderShape = .capsule
            field.controlSize = .extraLarge
        } else {
            field.bezelStyle = .roundedBezel
            field.controlSize = .large
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if isEnabled == false, nsView.currentEditor() != nil { nsView.window?.makeFirstResponder(nil) }
        nsView.isEnabled = isEnabled
        nsView.isEditable = isEnabled
        nsView.isSelectable = isEnabled
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width, height: Self.height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeURLInputField

        init(parent: NativeURLInputField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField, field.isEnabled else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }

    final class CenteredTextFieldCell: NSTextFieldCell {
        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            var interior = super.drawingRect(forBounds: rect)
            interior.origin.x += 4
            interior.size.width = max(0, interior.width - 4)
            let textHeight = ceil((font?.ascender ?? 12) - (font?.descender ?? -3) + (font?.leading ?? 0))
            if interior.height > textHeight {
                interior.origin.y += floor((interior.height - textHeight) / 2)
                interior.size.height = textHeight
            }
            return interior
        }
    }
}
