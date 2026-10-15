import AppKit
import SwiftUI

final class WindowsSettingsWindow: NSWindow {
    private let captionHeight: CGFloat = 58
    private let captionButtonAreaWidth: CGFloat = 138

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let point = event.locationInWindow
            let isCaption = point.y >= frame.height - captionHeight
                && point.x < frame.width - captionButtonAreaWidth
            if isCaption {
                if event.clickCount == 2 {
                    zoom(nil)
                } else {
                    performDrag(with: event)
                }
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class SettingsWindowCoordinator: NSObject, NSWindowDelegate {
    private let state: TaskbarState
    private var window: WindowsSettingsWindow?

    init(state: TaskbarState) {
        self.state = state
    }

    func show() {
        let settingsWindow = window ?? makeWindow()
        if settingsWindow.isMiniaturized {
            settingsWindow.deminiaturize(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        window = settingsWindow
    }

    func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makeWindow() -> WindowsSettingsWindow {
        let settingsWindow = WindowsSettingsWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 720),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )
        settingsWindow.title = "Windows Skin Settings"
        settingsWindow.titleVisibility = .hidden
        settingsWindow.titlebarAppearsTransparent = true
        settingsWindow.isMovableByWindowBackground = false
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.minSize = CGSize(width: 760, height: 560)
        settingsWindow.backgroundColor = .clear
        settingsWindow.isOpaque = false
        settingsWindow.hasShadow = true
        settingsWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        settingsWindow.delegate = self
        settingsWindow.standardWindowButton(.closeButton)?.isHidden = true
        settingsWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        settingsWindow.standardWindowButton(.zoomButton)?.isHidden = true
        settingsWindow.contentView = NSHostingView(
            rootView: WindowsSettingsWindowView(
                state: state,
                minimize: { [weak settingsWindow] in
                    settingsWindow?.miniaturize(nil)
                },
                maximize: { [weak settingsWindow] in
                    settingsWindow?.zoom(nil)
                },
                close: { [weak settingsWindow] in
                    settingsWindow?.performClose(nil)
                }
            )
        )
        if !settingsWindow.setFrameUsingName("WindowsSkinSettingsWindow") {
            settingsWindow.center()
        }
        settingsWindow.setFrameAutosaveName("WindowsSkinSettingsWindow")
        return settingsWindow
    }
}

private struct WindowsSettingsWindowView: View {
    @ObservedObject var state: TaskbarState
    let minimize: () -> Void
    let maximize: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            TaskbarTheme.accentPurple,
                                            TaskbarTheme.accentCyan
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(
                                    color: TaskbarTheme.accentPurple.opacity(0.35),
                                    radius: 10,
                                    y: 4
                                )
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Windows Skin")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Text("Desktop personalization")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("0.3.2")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.72))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.07))
                        .overlay {
                            Capsule().stroke(Color.white.opacity(0.11), lineWidth: 0.7)
                        }
                        .clipShape(Capsule())
                    Spacer()
                }
                .padding(.leading, 16)

                settingsCaptionButton(.minimize, help: "Minimize", action: minimize)
                settingsCaptionButton(.maximize, help: "Maximize or restore", action: maximize)
                settingsCaptionButton(.close, help: "Close", action: close)
            }
            .frame(height: 58)
            .background {
                VisualEffectView()
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.08, blue: 0.18).opacity(0.9),
                        Color(red: 0.045, green: 0.06, blue: 0.12).opacity(0.88)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.13))
                    .frame(height: 0.5)
            }

            SettingsFlyout(
                state: state,
                service: state.preferencesService,
                showsHeader: false
            )
        }
        .foregroundStyle(Color.white.opacity(0.94))
        .background {
            VisualEffectView()
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.075, blue: 0.20).opacity(0.90),
                    Color(red: 0.055, green: 0.07, blue: 0.14).opacity(0.91),
                    Color(red: 0.07, green: 0.055, blue: 0.15).opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [TaskbarTheme.accentPurple.opacity(0.15), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 430
            )
            RadialGradient(
                colors: [TaskbarTheme.accentCyan.opacity(0.07), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 380
            )
        }
        .preferredColorScheme(.dark)
    }

    private func settingsCaptionButton(
        _ kind: SettingsCaptionButton.Kind,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        SettingsCaptionButton(
            kind: kind,
            help: help,
            action: action
        )
    }
}

private struct SettingsCaptionButton: View {
    enum Kind: Equatable {
        case minimize
        case maximize
        case close
    }

    let kind: Kind
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            captionGlyph
                .frame(width: 46, height: 42)
                .background(backgroundColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        guard isHovering else { return .clear }
        return kind == .close ? Color.red.opacity(0.82) : Color.white.opacity(0.11)
    }

    @ViewBuilder
    private var captionGlyph: some View {
        switch kind {
        case .minimize:
            Rectangle()
                .fill(Color.white.opacity(0.94))
                .frame(width: 11, height: 1.25)
                .offset(y: 4)
        case .maximize:
            RoundedRectangle(cornerRadius: 0.8)
                .stroke(Color.white.opacity(0.94), lineWidth: 1.25)
                .frame(width: 10.5, height: 10.5)
        case .close:
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 13, height: 1.25)
                    .rotationEffect(.degrees(45))
                Rectangle()
                    .fill(Color.white.opacity(0.96))
                    .frame(width: 13, height: 1.25)
                    .rotationEffect(.degrees(-45))
            }
        }
    }
}
