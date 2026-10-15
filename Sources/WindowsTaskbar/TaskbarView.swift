import SwiftUI
import UniformTypeIdentifiers

struct TaskbarView: View {
    @ObservedObject var state: TaskbarState
    @ObservedObject private var preferences: PreferencesService
    @ObservedObject private var dockGeometry: DockGeometryService
    @State private var leftRegionWidth: CGFloat = 0
    @State private var rightRegionWidth: CGFloat = 0

    init(state: TaskbarState) {
        self.state = state
        self.preferences = state.preferencesService
        self.dockGeometry = state.dockGeometryService
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
    private var taskbarHeight: CGFloat {
        dockGeometry.taskbarHeight(for: appIconSize)
    }
    private var trayControlWidth: CGFloat {
        TaskbarTheme.trayControlWidth(for: buttonSize)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VisualEffectView()
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.10, blue: 0.24).opacity(0.76),
                        Color(red: 0.05, green: 0.08, blue: 0.16).opacity(0.82),
                        Color(red: 0.09, green: 0.07, blue: 0.18).opacity(0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        TaskbarTheme.accentPurple.opacity(0.14),
                        .clear,
                        TaskbarTheme.accentCyan.opacity(0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                TaskbarTheme.accentPurple.opacity(0.32),
                                Color.white.opacity(0.16)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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

    @ViewBuilder
    private var leftRegion: some View {
        if preferences.showWeatherWidget {
            Button {
                state.perform(SystemActions.openWeather)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: navigationIconSize))
                        .symbolRenderingMode(.multicolor)
                    Text("Weather")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TaskbarTheme.foreground)
                }
                .frame(width: max(86, buttonSize * 1.75), height: buttonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(WindowsTaskbarButtonStyle())
            .help("Open Apple Weather")
            .accessibilityLabel("Open Apple Weather")
        }
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
                StartMenuLogoView(
                    style: preferences.startMenuLogoStyle,
                    size: startIconSize
                )
            }

            if preferences.showSearchButton {
                TaskbarButton(accessibilityLabel: "Search", buttonSize: buttonSize) {
                    state.perform(SystemActions.openSpotlight)
                } content: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: navigationIconSize, weight: .regular))
                        .foregroundStyle(TaskbarTheme.foreground)
                }
            }

            if preferences.showTaskViewButton {
                TaskbarButton(accessibilityLabel: "Task View", buttonSize: buttonSize) {
                    state.perform(SystemActions.openMissionControl)
                } content: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: navigationIconSize, weight: .regular))
                        .foregroundStyle(TaskbarTheme.foreground)
                }
                .padding(.trailing, TaskbarTheme.navigationAppSeparation)
            }

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
            if preferences.showQuickSettingsButton {
                compactButton(
                    "Hidden system controls",
                    symbol: "chevron.up",
                    iconSize: adaptiveTrayIconSize,
                    controlWidth: trayControlWidth
                ) {
                    state.toggleFlyout(.quickSettings)
                }
            }
            if preferences.showNetworkButton {
                NetworkTrayButton(
                    service: state.networkService,
                    iconSize: TaskbarTheme.systemTrayIconSize,
                    controlHeight: buttonSize,
                    controlWidth: trayControlWidth
                ) {
                    state.toggleFlyout(.network)
                }
            }
            if preferences.showVolumeButton {
                AudioTrayButton(
                    service: state.audioService,
                    iconSize: TaskbarTheme.systemTrayIconSize,
                    controlHeight: buttonSize,
                    controlWidth: trayControlWidth
                ) {
                    state.toggleFlyout(.volume)
                }
            }
            if preferences.showBatteryButton {
                BatteryTrayButton(
                    service: state.batteryService,
                    iconSize: TaskbarTheme.systemTrayIconSize,
                    controlHeight: buttonSize,
                    controlWidth: max(62, trayControlWidth * 1.8)
                ) {
                    state.toggleFlyout(.battery)
                }
            }
            if preferences.showClock {
                Button {
                    state.toggleFlyout(.calendar)
                } label: {
                    ClockView(width: 82, height: buttonSize)
                }
                .buttonStyle(WindowsTaskbarButtonStyle())
                .help("Calendar and date")
            }
            if preferences.showNotificationButton {
                NotificationTrayButton(
                    service: state.notificationService,
                    iconSize: adaptiveTrayIconSize,
                    controlHeight: buttonSize,
                    controlWidth: trayControlWidth
                ) {
                    state.toggleFlyout(.notificationCenter)
                }
                .contextMenu {
                    Button("Open macOS Notification Center") {
                        state.perform(SystemActions.openNotificationCenter)
                    }
                }
            }

            if preferences.showDesktopButton {
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
