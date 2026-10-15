import AppKit
import Combine
import SwiftUI

final class WindowControlsPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class WindowControlsCoordinator {
    private let accessibility: AccessibilityService
    private let preferences: PreferencesService
    private let windowManager: WindowManagerService
    private var panel: WindowControlsPanel?
    private var timer: Timer?
    private var preferenceCancellable: AnyCancellable?
    private var currentIdentity: WindowIdentity?
    private var dragStartFrame: CGRect?

    init(
        accessibility: AccessibilityService,
        preferences: PreferencesService,
        windowManager: WindowManagerService
    ) {
        self.accessibility = accessibility
        self.preferences = preferences
        self.windowManager = windowManager
    }

    func start() {
        stop()
        preferenceCancellable = Publishers.CombineLatest3(
            preferences.$windowManagementEnabled,
            preferences.$windowsStyleControlsEnabled,
            preferences.$windowControlsShowTitle
        )
        .sink { [weak self] _, _, _ in
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        preferenceCancellable = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        currentIdentity = nil
    }

    private func refresh() {
        accessibility.refreshAuthorization()
        guard preferences.windowManagementEnabled,
              preferences.windowsStyleControlsEnabled,
              accessibility.isTrusted,
              let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.activationPolicy == .regular,
              let window = accessibility.focusedWindow(for: application),
              !window.isMinimized,
              !accessibility.isFullScreen(window),
              let quartzFrame = accessibility.frame(of: window),
              quartzFrame.width >= 300,
              let workArea = ScreenWorkArea.containing(
                quartzPoint: CGPoint(x: quartzFrame.midX, y: quartzFrame.midY),
                in: ScreenWorkArea.current(taskbarHeight: 0, taskbarDisplayIDs: [])
              )
        else {
            hide()
            return
        }

        let showsTitle = preferences.windowControlsShowTitle
        let preferredWidth = min(460, max(310, quartzFrame.width * 0.46))
        let panelWidth: CGFloat = showsTitle
            ? min(quartzFrame.width - 14, preferredWidth)
            : 184
        let panelHeight: CGFloat = 34
        let appKitWindowFrame = workArea.appKitRect(fromQuartz: quartzFrame)
        let frame = CGRect(
            x: appKitWindowFrame.maxX - panelWidth - 7,
            y: appKitWindowFrame.maxY - panelHeight - 4,
            width: panelWidth,
            height: panelHeight
        )

        let controlsPanel = panel ?? makePanel(frame: frame)
        if currentIdentity != window.identity
            || controlsPanel.frame.size != frame.size {
            controlsPanel.contentView = NSHostingView(
                rootView: WindowsWindowControlsView(
                    title: window.title,
                    appIcon: application.icon,
                    showsTitle: showsTitle,
                    snapLayoutsEnabled: preferences.snapLayoutsEnabled,
                    minimize: { [weak self] in
                        self?.accessibility.minimize(window)
                        self?.hide()
                    },
                    toggleMaximize: { [weak self] in
                        _ = self?.windowManager.toggleMaximize(window)
                        self?.refresh()
                    },
                    showSnapLayouts: { [weak self] in
                        self?.windowManager.showSnapLayouts(for: window)
                    },
                    moveWindow: { [weak self] translation, ended in
                        self?.move(window, by: translation, ended: ended)
                    },
                    close: { [weak self] in
                        self?.accessibility.close(window)
                        self?.hide()
                    }
                )
            )
            currentIdentity = window.identity
        }
        controlsPanel.setFrame(frame, display: true)
        controlsPanel.orderFrontRegardless()
        panel = controlsPanel
    }

    private func makePanel(frame: CGRect) -> WindowControlsPanel {
        let panel = WindowControlsPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return panel
    }

    private func hide() {
        panel?.orderOut(nil)
        currentIdentity = nil
        dragStartFrame = nil
    }

    private func move(
        _ window: AccessibilityWindow,
        by translation: CGSize,
        ended: Bool
    ) {
        if dragStartFrame == nil {
            dragStartFrame = accessibility.frame(of: window)
        }
        if let start = dragStartFrame {
            _ = accessibility.setPosition(
                CGPoint(
                    x: start.minX + translation.width,
                    y: start.minY + translation.height
                ),
                for: window
            )
        }
        if ended { dragStartFrame = nil }
    }
}

private struct WindowsWindowControlsView: View {
    let title: String
    let appIcon: NSImage?
    let showsTitle: Bool
    let snapLayoutsEnabled: Bool
    let minimize: () -> Void
    let toggleMaximize: () -> Void
    let showSnapLayouts: () -> Void
    let moveWindow: (CGSize, Bool) -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if showsTitle {
                HStack(spacing: 7) {
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 17, height: 17)
                    }
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                }
                .padding(.leading, 10)
                .contentShape(Rectangle())
                .help("Drag to move window")
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { moveWindow($0.translation, false) }
                        .onEnded { moveWindow($0.translation, true) }
                )
            }

            captionButton("minus", help: "Minimize", action: minimize)
            captionButton(
                "square.on.square",
                help: "Snap layouts",
                isEnabled: snapLayoutsEnabled,
                action: showSnapLayouts
            )
            captionButton("square", help: "Maximize or restore", action: toggleMaximize)
            captionButton("xmark", help: "Close", isClose: true, action: close)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.white.opacity(0.94))
        .background {
            VisualEffectView()
            Color(red: 0.055, green: 0.07, blue: 0.10).opacity(0.94)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .preferredColorScheme(.dark)
    }

    private func captionButton(
        _ symbol: String,
        help: String,
        isEnabled: Bool = true,
        isClose: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        WindowsCaptionButton(
            symbol: symbol,
            help: help,
            isEnabled: isEnabled,
            isClose: isClose,
            action: action
        )
    }
}

private struct WindowsCaptionButton: View {
    let symbol: String
    let help: String
    let isEnabled: Bool
    let isClose: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .frame(width: 46, height: 34)
                .background(backgroundColor)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        guard isHovering, isEnabled else { return .clear }
        return isClose ? Color.red.opacity(0.78) : Color.white.opacity(0.12)
    }
}
