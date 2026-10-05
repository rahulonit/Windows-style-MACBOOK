import AppKit
import SwiftUI

struct StartSearchField: NSViewRepresentable {
    @Binding var text: String
    let onMoveSelection: (Int) -> Void
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CommandSearchField {
        let field = CommandSearchField()
        field.placeholderString = "Search apps"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.onMoveSelection = onMoveSelection
        field.onSubmit = onSubmit
        field.onEscape = onEscape
        return field
    }

    func updateNSView(_ field: CommandSearchField, context: Context) {
        context.coordinator.parent = self
        field.onMoveSelection = onMoveSelection
        field.onSubmit = onSubmit
        field.onEscape = onEscape
        if field.stringValue != text {
            field.stringValue = text
        }
        if !context.coordinator.didRequestFocus, field.window != nil {
            context.coordinator.didRequestFocus = true
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: StartSearchField
        var didRequestFocus = false

        init(parent: StartSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
    }
}

final class CommandSearchField: NSSearchField {
    var onMoveSelection: ((Int) -> Void)?
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        case 36:
            onSubmit?()
        case 53:
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}
