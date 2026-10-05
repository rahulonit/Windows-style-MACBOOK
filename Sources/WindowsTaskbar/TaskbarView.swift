import SwiftUI
import UniformTypeIdentifiers

struct TaskbarView: View {
    @ObservedObject var state: TaskbarState
    @ObservedObject private var preferences: PreferencesService
    @State private var leftRegionWidth: CGFloat = 0
    @State private var rightRegionWidth: CGFloat = 0

    init(state: TaskbarState) {
        self.state = state
        self.preferences = state.preferencesService
    }

    private var appIconSize: CGFloat { CGFloat(preferences.taskbarIconSize) }
    private var navigationIconSize: CGFloat {
        CGFloat(preferences.navigationIconSize)
    }
    private var startIconSize: CGFloat {
        TaskbarTheme.startIconSize(for: appIconSize)
    }
    private var adaptiveTrayIconSize: CGFloat {
        TaskbarTheme.trayIconSize(for: appIconSize)
    }
    private var buttonSize: CGFloat { TaskbarTheme.buttonSize(for: appIconSize) }
    private var buttonSpacing: CGFloat { TaskbarTheme.buttonSpacing(for: appIconSize) }
    private var taskbarHeight: CGFloat { TaskbarTheme.height(for: appIconSize) }
    private var trayControlWidth: CGFloat {
        TaskbarTheme.trayControlWidth(for: buttonSize)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VisualEffectView()
                Color(red: 0.05, green: 0.08, blue: 0.13).opacity(0.58)

                Rectangle()
                    .fill(Color(red: 0.56, green: 0.59, blue: 0.64).opacity(0.34))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .top)

                HStack(spacing: 0) {
                    leftRegion
                        .background(regionWidthReader(LeftRegionWidthKey.self))
                    Spacer(minLength: 0)
                    rightRegion
                        .background(regionWidthReader(RightRegionWidthKey.self))
                }
                .padding(.horizontal, TaskbarTheme.horizontalPadding)

                centerRegion(
                    screenWidth: geometry.size.width,
                    leadingRegionWidth: leftRegionWidth,
                    trailingRegionWidth: rightRegionWidth
                )
            }
        }
        .onPreferenceChange(LeftRegionWidthKey.self) { leftRegionWidth = $0 }
        .onPreferenceChange(RightRegionWidthKey.self) { rightRegionWidth = $0 }
        .frame(height: taskbarHeight)
        .preferredColorScheme(.dark)
    }

    private func regionWidthReader<Key: PreferenceKey>(
        _ key: Key.Type
    ) -> some View where Key.Value == CGFloat {
        GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.width)
        }
    }

    private var leftRegion: some View {
        Button {
            state.toggleFlyout(.notificationCenter)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "cloud.sun.fill")
                    .font(.system(size: navigationIconSize))
                    .symbolRenderingMode(.multicolor)
                Text("Widgets")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TaskbarTheme.foreground)
            }
            .frame(width: max(86, buttonSize * 1.75), height: buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(WindowsTaskbarButtonStyle())
        .help("Widgets and notifications")
        .accessibilityLabel("Widgets and notifications")
    }

    @ViewBuilder
    private func centerRegion(
        screenWidth: CGFloat,
        leadingRegionWidth: CGFloat,
        trailingRegionWidth: CGFloat
    ) -> some View {
        let layout = TaskbarLayoutPolicy.calculate(
            screenWidth: screenWidth,
            appCount: state.taskbarApps.count,
            iconSize: appIconSize,
            leadingRegionWidth: leadingRegionWidth,
            trailingRegionWidth: trailingRegionWidth
        )
        let visibleApps = Array(state.taskbarApps.prefix(layout.visibleAppCount))
        let overflowApps = Array(state.taskbarApps.dropFirst(layout.visibleAppCount))

        HStack(spacing: buttonSpacing) {
            TaskbarButton(accessibilityLabel: "Start", buttonSize: buttonSize) {
                state.toggleFlyout(.start)
            } content: {
                Image(systemName: "apple.logo")
                    .font(.system(size: startIconSize, weight: .medium))
                    .foregroundStyle(TaskbarTheme.foreground)
            }

            TaskbarButton(accessibilityLabel: "Search", buttonSize: buttonSize) {
                state.perform(SystemActions.openSpotlight)
            } content: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: navigationIconSize, weight: .regular))
                    .foregroundStyle(TaskbarTheme.foreground)
            }

            TaskbarButton(accessibilityLabel: "Task View", buttonSize: buttonSize) {
                state.perform(SystemActions.openMissionControl)
            } content: {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: navigationIconSize, weight: .regular))
                    .foregroundStyle(TaskbarTheme.foreground)
            }
            .padding(.trailing, TaskbarTheme.navigationAppSeparation)

            ForEach(visibleApps) { app in
                TaskbarAppButton(
                    app: app,
                    isRunning: state.isRunning(app),
                    isActive: state.isActive(app),
                    windowCount: state.windowCount(for: app),
                    iconSize: appIconSize,
                    buttonSize: buttonSize
                ) {
                    state.activate(app)
                }
                .contextMenu {
                    if state.isPinned(app) {
                        Button("Unpin from taskbar") { state.unpin(app) }
                        Button("Move left") { state.movePinnedApp(app, offset: -1) }
                        Button("Move right") { state.movePinnedApp(app, offset: 1) }
                    } else {
                        Button("Pin to taskbar") { state.pin(app) }
                    }
                    if state.isRunning(app) {
                        if state.accessibilityService.isTrusted,
                           state.windowCount(for: app) > 0 {
                            Button("Show windows") { state.showWindows(for: app) }
                        } else if !state.accessibilityService.isTrusted {
                            Button("Enable window controls") {
                                state.showAccessibilityOnboarding()
                            }
                        }
                        if state.accessibilityService.isTrusted,
                           state.windowCount(for: app) > 0 {
                            Divider()
                            Button("Maximize") { state.snap(app, to: .maximize) }
                            Button("Snap left") { state.snap(app, to: .leftHalf) }
                            Button("Snap right") { state.snap(app, to: .rightHalf) }
                            Button("Restore") { state.restoreWindow(for: app) }
                            Button("Minimize") { state.minimizeWindow(for: app) }
                        }
                        if app.bundleIdentifier != TaskbarState.finderBundleIdentifier {
                            Divider()
                            Button("Quit \(app.displayName)") { state.quit(app) }
                        }
                    }
                }
                .onDrag {
                    state.beginDragging(app)
                    return NSItemProvider(object: app.bundleIdentifier as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: PinnedAppDropDelegate(target: app, state: state)
                )
            }

            if layout.overflowCount > 0 {
                TaskbarButton(
                    accessibilityLabel: "\(layout.overflowCount) more applications",
                    buttonSize: buttonSize
                ) {
                    state.showOverflow(overflowApps)
                } content: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: navigationIconSize, weight: .semibold))
                        .foregroundStyle(TaskbarTheme.foreground)
                }
                .help("\(layout.overflowCount) more applications")
            }
        }
    }

    private var rightRegion: some View {
        HStack(alignment: .center, spacing: TaskbarTheme.traySpacing) {
            compactButton(
                "Hidden system controls",
                symbol: "chevron.up",
                iconSize: adaptiveTrayIconSize,
                controlWidth: trayControlWidth
            ) {
                state.toggleFlyout(.quickSettings)
            }
            NetworkTrayButton(
                service: state.networkService,
                iconSize: TaskbarTheme.systemTrayIconSize,
                controlHeight: buttonSize,
                controlWidth: trayControlWidth
            ) {
                state.toggleFlyout(.network)
            }
            AudioTrayButton(
                service: state.audioService,
                iconSize: TaskbarTheme.systemTrayIconSize,
                controlHeight: buttonSize,
                controlWidth: trayControlWidth
            ) {
                state.toggleFlyout(.volume)
            }
            BatteryTrayButton(
                service: state.batteryService,
                iconSize: TaskbarTheme.systemTrayIconSize,
                controlHeight: buttonSize,
                controlWidth: max(62, trayControlWidth * 1.8)
            ) {
                state.toggleFlyout(.battery)
            }
            Button {
                state.toggleFlyout(.calendar)
            } label: {
                ClockView(width: 82, height: buttonSize)
            }
            .buttonStyle(WindowsTaskbarButtonStyle())
            .help("Calendar and date")
            NotificationTrayButton(
                service: state.notificationService,
                iconSize: adaptiveTrayIconSize,
                controlHeight: buttonSize,
                controlWidth: trayControlWidth
            ) {
                state.toggleFlyout(.notificationCenter)
            }

            Button {
                state.perform(SystemActions.showDesktop)
            } label: {
                ZStack(alignment: .trailing) {
                    Color.white.opacity(0.035)
                    Rectangle()
                        .fill(Color.white.opacity(0.42))
                        .frame(width: 2)
                        .padding(.vertical, 5)
                }
                .frame(width: 28, height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(WindowsTaskbarButtonStyle())
            .help("Show desktop")
            .accessibilityLabel("Show desktop")
        }
        .foregroundStyle(TaskbarTheme.foreground)
    }

    private func compactButton(
        _ label: String,
        symbol: String,
        iconSize: CGFloat,
        controlWidth: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize))
                .frame(width: controlWidth, height: buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(WindowsTaskbarButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct LeftRegionWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct RightRegionWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PinnedAppDropDelegate: DropDelegate {
    let target: AppDescriptor
    let state: TaskbarState

    func dropEntered(info: DropInfo) {
        state.moveDraggedPinnedApp(over: target)
    }

    func performDrop(info: DropInfo) -> Bool {
        state.endDragging()
        return true
    }

    func dropExited(info: DropInfo) {}
}
