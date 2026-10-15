import AppKit
import SwiftUI

struct TaskbarButton<Content: View>: View {
    let accessibilityLabel: String
    let buttonSize: CGFloat
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: buttonSize, height: buttonSize)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(WindowsTaskbarButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

struct WindowsTaskbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        WindowsTaskbarButtonStyleBody(configuration: configuration)
    }
}

private struct WindowsTaskbarButtonStyleBody: View {
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label
            .background(TaskbarHoverBackground(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct TaskbarHoverBackground: NSViewRepresentable {
    let isPressed: Bool

    func makeNSView(context: Context) -> TaskbarHoverNSView {
        TaskbarHoverNSView()
    }

    func updateNSView(_ view: TaskbarHoverNSView, context: Context) {
        view.isPressed = isPressed
    }
}

private final class TaskbarHoverNSView: NSView {
    var isPressed = false {
        didSet { updateBackground() }
    }

    private var isHovered = false {
        didSet { updateBackground() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        updateBackground()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func updateBackground() {
        let color: NSColor
        if isPressed {
            color = NSColor(calibratedRed: 0.37, green: 0.24, blue: 0.72, alpha: 0.26)
        } else if isHovered {
            color = NSColor(calibratedRed: 0.47, green: 0.38, blue: 0.82, alpha: 0.20)
        } else {
            color = .clear
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        layer?.backgroundColor = color.cgColor
        layer?.borderWidth = isHovered || isPressed ? 0.75 : 0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.17).cgColor
        CATransaction.commit()
    }
}

struct TaskbarAppButton: View {
    let app: AppDescriptor
    let isRunning: Bool
    let isActive: Bool
    let windowCount: Int
    let iconSize: CGFloat
    let buttonSize: CGFloat
    let action: () -> Void

    var body: some View {
        TaskbarButton(
            accessibilityLabel: app.displayName,
            buttonSize: buttonSize,
            action: action
        ) {
            VStack(spacing: 1) {
                Image(nsImage: app.icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)

                HStack(spacing: 2) {
                    if isRunning {
                        Capsule()
                            .fill(
                                isActive
                                    ? TaskbarTheme.activeIndicator
                                    : TaskbarTheme.runningIndicator
                            )
                            .frame(width: isActive ? 16 : 6, height: 3)
                        if windowCount > 1 {
                            Capsule()
                                .fill(TaskbarTheme.runningIndicator)
                                .frame(width: 6, height: 3)
                        }
                    }
                }
                .frame(height: 4)
                .animation(.easeOut(duration: 0.16), value: isActive)
            }
            .frame(width: buttonSize, height: buttonSize, alignment: .center)
        }
        .help(app.displayName)
    }
}
